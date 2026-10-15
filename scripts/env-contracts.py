#!/usr/bin/env python3
"""Check and sync app environment contracts from GitHub .env.example files."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

PROJECT_DIR = Path(__file__).resolve().parents[1]
APPS_FILE = PROJECT_DIR / "group_vars" / "all" / "apps.yml"
VARS_FILE = PROJECT_DIR / "group_vars" / "all" / "vars.yml"
VAULT_FILE = PROJECT_DIR / "group_vars" / "all" / "vault.yml"
VAULT_PASS_FILE = PROJECT_DIR / ".vault_pass"
ENV_FILE = PROJECT_DIR / ".env"

ENV_KEY_RE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=")
VAULT_REF_RE = re.compile(r"{{\s*(vault_[A-Za-z0-9_]+)\b")
SENSITIVE_RE = re.compile(
    r"(SECRET|TOKEN|PASSWORD|PRIVATE|CLIENT_SECRET|API_KEY|ACCESS_KEY|SECRET_KEY|APP_KEY|JWT|VAPID)",
    re.IGNORECASE,
)


class ContractError(Exception):
    """Raised when a remote contract cannot be fetched or parsed."""


@dataclass(frozen=True)
class TemplateEnv:
    keys: set[str]
    vault_refs: dict[str, set[str]]
    required_vault_refs: set[str]


def load_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise SystemExit(f"{path} must contain a YAML mapping")
    return data


def load_dotenv() -> dict[str, str]:
    values: dict[str, str] = {}
    if not ENV_FILE.exists():
        return values
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        match = ENV_KEY_RE.match(line)
        if not match:
            continue
        key = match.group(1)
        value = line.split("=", 1)[1].strip().strip("\"'")
        values[key] = value
    return values


def catalog() -> dict[str, Any]:
    return load_yaml(APPS_FILE)


def vars_data() -> dict[str, Any]:
    return load_yaml(VARS_FILE)


def enabled_apps(data: dict[str, Any]) -> list[dict[str, Any]]:
    items = data.get("portfolio_apps", [])
    if not isinstance(items, list):
        raise SystemExit("portfolio_apps must be a list")
    enabled = [item for item in items if item.get("enabled", True)]
    pui = data.get("pui_app")
    if isinstance(pui, dict) and pui.get("enabled", True):
        enabled.append(pui)
    return enabled


def mobile_repositories(data: dict[str, Any], enabled_only: bool = True) -> list[dict[str, Any]]:
    items = data.get("mobile_repositories", [])
    if not isinstance(items, list):
        raise SystemExit("mobile_repositories must be a list")
    if enabled_only:
        return [item for item in items if item.get("enabled", True)]
    return items


def github_owner() -> str:
    owner = str(vars_data().get("github_username", "")).strip()
    if not owner:
        raise SystemExit("github_username is not set in group_vars/all/vars.yml")
    return owner


def repo_owner(item: dict[str, Any], default_owner: str) -> str:
    return str(item.get("repo_owner") or default_owner)


def repo_name(item: dict[str, Any]) -> str:
    return str(item.get("repo", item["name"]))


def repo_ref(item: dict[str, Any], default_owner: str) -> str:
    return f"{repo_owner(item, default_owner)}/{repo_name(item)}"


def github_token(vault: dict[str, Any] | None = None) -> str:
    env_values = load_dotenv()
    for key in ("GH_TOKEN", "GITHUB_TOKEN", "GITHUB_PAT_TOKEN"):
        value = os.environ.get(key) or env_values.get(key)
        if value:
            return value
    if vault is None:
        vault = load_vault(required=False)
    return str(vault.get("vault_github_token", "") or "")


def request_json(url: str, token: str = "") -> Any:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "server-infra-env-contracts",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise ContractError(f"GitHub API returned HTTP {exc.code}") from exc
    except urllib.error.URLError as exc:
        raise ContractError(str(exc.reason)) from exc


def request_text(url: str, token: str = "") -> str:
    headers = {"User-Agent": "server-infra-env-contracts"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            return response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raise ContractError(f"raw GitHub returned HTTP {exc.code}") from exc
    except urllib.error.URLError as exc:
        raise ContractError(str(exc.reason)) from exc


def fetch_env_example(owner: str, repo: str, path: str, ref: str = "", token: str = "") -> str:
    quoted_path = urllib.parse.quote(path.lstrip("/"))
    query = f"?ref={urllib.parse.quote(ref)}" if ref else ""
    api_url = f"https://api.github.com/repos/{owner}/{repo}/contents/{quoted_path}{query}"
    api_error = ""
    try:
        data = request_json(api_url, token)
        if not isinstance(data, dict) or data.get("type") != "file":
            raise ContractError("content path is not a file")
        if data.get("encoding") != "base64":
            raise ContractError("content is not base64 encoded")
        return base64.b64decode(str(data["content"])).decode("utf-8")
    except ContractError as exc:
        api_error = str(exc)

    raw_ref = ref or "HEAD"
    raw_url = f"https://raw.githubusercontent.com/{owner}/{repo}/{raw_ref}/{quoted_path}"
    try:
        return request_text(raw_url, token)
    except ContractError as exc:
        raise ContractError(f"{api_error}; {exc}") from exc


def parse_env_keys(content: str) -> set[str]:
    keys: set[str] = set()
    for line in content.splitlines():
        match = ENV_KEY_RE.match(line)
        if match:
            keys.add(match.group(1))
    return keys


def parse_template(path: Path) -> TemplateEnv:
    if not path.exists():
        return TemplateEnv(set(), {}, set())

    keys: set[str] = set()
    refs: dict[str, set[str]] = {}
    required_refs: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        match = ENV_KEY_RE.match(line)
        if not match:
            continue
        key = match.group(1)
        keys.add(key)
        rhs = line.split("=", 1)[1]
        line_refs = set(VAULT_REF_RE.findall(rhs))
        if line_refs:
            refs[key] = line_refs
            if "| default(" not in rhs and "|default(" not in rhs:
                required_refs.update(line_refs)
    return TemplateEnv(keys, refs, required_refs)


def load_vault(required: bool = True) -> dict[str, Any]:
    if not VAULT_FILE.exists() or not VAULT_PASS_FILE.exists():
        if required:
            raise SystemExit("vault.yml or .vault_pass is missing")
        return {}
    command = [
        "ansible-vault",
        "view",
        str(VAULT_FILE),
        f"--vault-password-file={VAULT_PASS_FILE}",
    ]
    result = subprocess.run(command, cwd=PROJECT_DIR, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        if required:
            raise SystemExit("failed to read ansible vault")
        return {}
    data = yaml.safe_load(result.stdout) or {}
    if not isinstance(data, dict):
        raise SystemExit("vault.yml must contain a YAML mapping")
    return data


def contract_config(data: dict[str, Any], app: dict[str, Any]) -> dict[str, Any]:
    defaults = data.get("env_contract_defaults", {}) or {}
    config = dict(defaults)
    config.update(app.get("env_contract", {}) or {})
    config.setdefault("path", ".env.example")
    config.setdefault("ref", "")
    config.setdefault("required", True)
    config.setdefault("ignore_keys", [])
    return config


def ci_config(data: dict[str, Any], app: dict[str, Any]) -> dict[str, dict[str, Any]]:
    defaults = data.get("github_actions_defaults", {}) or {}
    app_ci = app.get("ci", {}) or {}
    return {
        "secrets": {**(defaults.get("secrets", {}) or {}), **(app_ci.get("secrets", {}) or {})},
        "variables": {**(defaults.get("variables", {}) or {}), **(app_ci.get("variables", {}) or {})},
    }


def is_sensitive(key: str) -> bool:
    return bool(SENSITIVE_RE.search(key))


def mapping_keys(mapping: dict[str, Any]) -> set[str]:
    return set(mapping.keys())


def check_mapping_sources(mapping: dict[str, Any], vault: dict[str, Any], label: str) -> list[str]:
    errors: list[str] = []
    for key, spec in mapping.items():
        if not isinstance(spec, dict):
            continue
        source = str(spec.get("source", ""))
        if source.startswith("vault:"):
            vault_key = source.split(":", 1)[1]
            if vault_key not in vault:
                errors.append(f"{label} {key} references missing {vault_key}")
    return errors


def evaluate_app(
    data: dict[str, Any],
    app: dict[str, Any],
    default_owner: str,
    token: str,
    vault: dict[str, Any],
) -> tuple[bool, dict[str, Any]]:
    config = contract_config(data, app)
    owner = repo_owner(app, default_owner)
    repo = repo_name(app)
    result: dict[str, Any] = {
        "app": app["name"],
        "repo": repo,
        "remote_keys": set(),
        "runtime_keys": set(),
        "missing_runtime": set(),
        "extra_runtime": set(),
        "uncovered_sensitive": set(),
        "missing_required_vault_refs": set(),
        "source_errors": [],
        "fetch_error": "",
        "required": bool(config.get("required", True)),
    }

    try:
        content = fetch_env_example(owner, repo, str(config["path"]), str(config.get("ref") or ""), token)
        remote_keys = parse_env_keys(content) - set(config.get("ignore_keys", []) or [])
    except ContractError as exc:
        result["fetch_error"] = str(exc)
        return (not result["required"], result)

    template = parse_template(PROJECT_DIR / app["env_template"]) if app.get("env_template") else TemplateEnv(set(), {}, set())
    ci = ci_config(data, app)
    covered_keys = template.keys | mapping_keys(ci["secrets"]) | mapping_keys(ci["variables"])
    result["remote_keys"] = remote_keys
    result["runtime_keys"] = template.keys
    result["missing_runtime"] = remote_keys - template.keys
    result["extra_runtime"] = template.keys - remote_keys
    result["uncovered_sensitive"] = {key for key in remote_keys if is_sensitive(key) and key not in covered_keys}
    result["missing_required_vault_refs"] = template.required_vault_refs - set(vault.keys())
    result["source_errors"] = (
        check_mapping_sources(ci["secrets"], vault, "secret")
        + check_mapping_sources(ci["variables"], vault, "variable")
    )
    ok = not (
        result["missing_runtime"]
        or result["uncovered_sensitive"]
        or result["missing_required_vault_refs"]
        or result["source_errors"]
    )
    return ok, result


def print_result(result: dict[str, Any], show_details: bool = False) -> None:
    app = result["app"]
    if result["fetch_error"]:
        level = "WARN" if not result["required"] else "FAIL"
        print(f"{level} {app}: cannot fetch env contract ({result['fetch_error']})")
        return
    missing = sorted(result["missing_runtime"])
    uncovered = sorted(result["uncovered_sensitive"])
    missing_vault = sorted(result["missing_required_vault_refs"])
    source_errors = sorted(result["source_errors"])
    if not (missing or uncovered or missing_vault or source_errors):
        print(f"OK   {app}: {len(result['remote_keys'])} remote keys covered")
    else:
        print(f"FAIL {app}: contract drift detected")
    if show_details or missing:
        print_list("  missing in runtime template", missing)
    if show_details:
        print_list("  extra in runtime template", sorted(result["extra_runtime"]))
    if show_details or uncovered:
        print_list("  sensitive keys without runtime/CI coverage", uncovered)
    if show_details or missing_vault:
        print_list("  required vault refs not found", missing_vault)
    if show_details or source_errors:
        print_list("  invalid CI source mappings", source_errors)


def print_list(label: str, values: list[str]) -> None:
    if not values:
        return
    print(f"{label}:")
    for value in values:
        print(f"    - {value}")


def resolve_value(spec: Any, vault: dict[str, Any], variables: dict[str, Any]) -> str:
    if not isinstance(spec, dict):
        return str(spec)
    if "value" in spec:
        return str(spec["value"])
    source = str(spec.get("source", ""))
    if not source:
        raise ContractError("mapping needs value or source")
    source_type, _, source_name = source.partition(":")
    if source_type == "vault":
        if source_name not in vault:
            raise ContractError(f"missing vault key {source_name}")
        return str(vault[source_name])
    if source_type == "vars":
        if source_name not in variables:
            raise ContractError(f"missing vars key {source_name}")
        return str(variables[source_name])
    if source_type == "env":
        env_values = load_dotenv()
        value = os.environ.get(source_name) or env_values.get(source_name)
        if value is None:
            raise ContractError(f"missing env key {source_name}")
        return value
    if source_type == "runtime":
        return runtime_value(source_name, vault, variables)
    if source_type == "file":
        file_path = Path(source_name).expanduser()
        if not file_path.is_absolute():
            file_path = PROJECT_DIR / file_path
        if not file_path.exists():
            raise ContractError(f"missing file {file_path}")
        return file_path.read_text(encoding="utf-8")
    raise ContractError(f"unsupported source {source}")


def runtime_value(name: str, vault: dict[str, Any], variables: dict[str, Any]) -> str:
    if name == "vps_host":
        for line in (PROJECT_DIR / "inventory" / "hosts.ini").read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped and not stripped.startswith("[") and not stripped.startswith("#"):
                return stripped.split()[0]
        raise ContractError("no host found in inventory/hosts.ini")
    if name in {"vps_user", "ci_deploy_user"}:
        return str(variables.get("ci_deploy_user") or variables.get("deploy_user", "deployer"))
    if name == "vps_ssh_port":
        for line in (PROJECT_DIR / "inventory" / "hosts.ini").read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped and not stripped.startswith("[") and not stripped.startswith("#"):
                for part in stripped.split():
                    if part.startswith("ansible_port="):
                        return part.split("=", 1)[1]
        return str(variables.get("ssh_port", "22"))
    if name == "vps_key":
        key_name = str(variables.get("ssh_key_name", "server_ed25519"))
        key_path = Path.home() / ".ssh" / key_name
        if not key_path.exists():
            return ""
        return key_path.read_text(encoding="utf-8")
    if name == "vps_password":
        value = vault.get("vault_deployer_plaintext_password")
        return str(value) if value else ""
    if name == "docker_token":
        value = vault.get("vault_github_token")
        if not value:
            raise ContractError("missing vault_github_token")
        return str(value)
    raise ContractError(f"unsupported runtime source runtime:{name}")


def gh_environment(vault: dict[str, Any]) -> dict[str, str]:
    env = os.environ.copy()
    token = github_token(vault)
    if token and not env.get("GH_TOKEN"):
        env["GH_TOKEN"] = token
    return env


def gh_set_secret(full_repo: str, key: str, value: str, dry_run: bool, env: dict[str, str]) -> bool:
    if dry_run:
        print(f"DRY  {full_repo}: secret {key}")
        return True
    result = subprocess.run(
        ["gh", "secret", "set", key, "--repo", full_repo],
        input=value,
        text=True,
        cwd=PROJECT_DIR,
        env=env,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        print(f"FAIL {full_repo}: secret {key}", file=sys.stderr)
        return False
    print(f"OK   {full_repo}: secret {key}")
    return True


def gh_set_variable(full_repo: str, key: str, value: str, dry_run: bool, env: dict[str, str]) -> bool:
    if dry_run:
        print(f"DRY  {full_repo}: variable {key}")
        return True
    result = subprocess.run(
        ["gh", "variable", "set", key, "--repo", full_repo, "--body", value],
        text=True,
        cwd=PROJECT_DIR,
        env=env,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        print(f"FAIL {full_repo}: variable {key}", file=sys.stderr)
        return False
    print(f"OK   {full_repo}: variable {key}")
    return True

def gh_list_repo_names(kind: str, full_repo: str, env: dict[str, str]) -> set[str]:
    result = subprocess.run(
        ["gh", kind, "list", "--repo", full_repo, "--json", "name"],
        text=True,
        cwd=PROJECT_DIR,
        env=env,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise ContractError(result.stderr.strip() or f"failed to list {kind} for {full_repo}")

    payload = json.loads(result.stdout or "[]")
    if not isinstance(payload, list):
        raise ContractError(f"unexpected {kind} list response for {full_repo}")
    return {
        str(item.get("name", "")).strip()
        for item in payload
        if isinstance(item, dict) and item.get("name")
    }


def sync_repo(
    full_repo: str,
    ci: dict[str, dict[str, Any]],
    vault: dict[str, Any],
    variables: dict[str, Any],
    dry_run: bool,
    env: dict[str, str],
) -> bool:
    ok = True
    for key, spec in ci["secrets"].items():
        try:
            value = resolve_value(spec, vault, variables)
        except ContractError as exc:
            print(f"FAIL {full_repo}: secret {key} ({exc})", file=sys.stderr)
            ok = False
            continue
        if not value:
            print(f"SKIP {full_repo}: secret {key} (empty value)")
            continue
        ok = gh_set_secret(full_repo, key, value, dry_run, env) and ok
    for key, spec in ci["variables"].items():
        try:
            value = resolve_value(spec, vault, variables)
        except ContractError as exc:
            print(f"FAIL {full_repo}: variable {key} ({exc})", file=sys.stderr)
            ok = False
            continue
        if not value:
            print(f"SKIP {full_repo}: variable {key} (empty value)")
            continue
        ok = gh_set_variable(full_repo, key, value, dry_run, env) and ok
    return ok

def check_remote_repo_sync(
    full_repo: str,
    ci: dict[str, dict[str, Any]],
    vault: dict[str, Any],
    env: dict[str, str],
) -> bool:
    source_errors = (
        check_mapping_sources(ci["secrets"], vault, "secret")
        + check_mapping_sources(ci["variables"], vault, "variable")
    )
    if source_errors:
        print(f"FAIL {full_repo}: invalid catalog mappings")
        for error in sorted(source_errors):
            print(f"  - {error}")
        return False

    try:
        remote_secrets = gh_list_repo_names("secret", full_repo, env)
        remote_variables = gh_list_repo_names("variable", full_repo, env)
    except ContractError as exc:
        print(f"FAIL {full_repo}: {exc}")
        return False

    expected_secrets = set(ci["secrets"].keys())
    expected_variables = set(ci["variables"].keys())
    missing_secrets = sorted(expected_secrets - remote_secrets)
    missing_variables = sorted(expected_variables - remote_variables)

    if not missing_secrets and not missing_variables:
        print(
            f"OK   {full_repo}: "
            f"{len(expected_secrets)} secrets, {len(expected_variables)} variables present"
        )
        return True

    print(f"FAIL {full_repo}: GitHub configuration drift detected")
    print_list("  missing secrets", missing_secrets)
    print_list("  missing variables", missing_variables)
    return False


def cmd_check(args: argparse.Namespace) -> int:
    data = catalog()
    default_owner = github_owner()
    vault = load_vault(required=False)
    token = github_token(vault)
    selected = [
        app
        for app in enabled_apps(data)
        if not args.app or app["name"] == args.app or repo_name(app) == args.app or repo_ref(app, default_owner) == args.app
    ]
    if args.app and not selected:
        print(f"Unknown app: {args.app}", file=sys.stderr)
        return 1
    failed = 0
    for app in selected:
        ok, result = evaluate_app(data, app, default_owner, token, vault)
        print_result(result, show_details=args.verbose)
        failed += 0 if ok else 1
    return 1 if failed else 0


def cmd_show(args: argparse.Namespace) -> int:
    data = catalog()
    default_owner = github_owner()
    vault = load_vault(required=False)
    token = github_token(vault)
    matches = [
        app
        for app in enabled_apps(data)
        if app["name"] == args.app or repo_name(app) == args.app or repo_ref(app, default_owner) == args.app
    ]
    if not matches:
        print(f"Unknown app: {args.app}", file=sys.stderr)
        return 1
    ok, result = evaluate_app(data, matches[0], default_owner, token, vault)
    print_result(result, show_details=True)
    return 0 if ok else 1


def cmd_github_sync(args: argparse.Namespace) -> int:
    data = catalog()
    default_owner = github_owner()
    vault = load_vault(required=True)
    variables = vars_data()
    env = gh_environment(vault)
    repo_filter = set(args.repo or [])
    ok = True

    for app in enabled_apps(data):
        full_repo = repo_ref(app, default_owner)
        repo = repo_name(app)
        if repo_filter and repo not in repo_filter and app["name"] not in repo_filter and full_repo not in repo_filter:
            continue
        ok = sync_repo(full_repo, ci_config(data, app), vault, variables, args.dry_run, env) and ok

    for mobile in mobile_repositories(data):
        repo = repo_name(mobile)
        full_repo = repo_ref(mobile, default_owner)
        if repo_filter and repo not in repo_filter and full_repo not in repo_filter:
            continue
        mobile_ci = mobile.get("ci", {}) or {}
        raw_variables = {key: {"value": value} for key, value in (mobile.get("variables", {}) or {}).items()}
        ci = {
            "secrets": mobile_ci.get("secrets", {}) or {},
            "variables": {
                **raw_variables,
                **(mobile_ci.get("variables", {}) or {}),
            },
        }
        ok = sync_repo(full_repo, ci, vault, variables, args.dry_run, env) and ok

    return 0 if ok else 1


def cmd_github_check(args: argparse.Namespace) -> int:
    data = catalog()
    default_owner = github_owner()
    vault = load_vault(required=False)
    env = gh_environment(vault)
    repo_filter = set(args.repo or [])
    ok = True

    for app in enabled_apps(data):
        full_repo = repo_ref(app, default_owner)
        repo = repo_name(app)
        if repo_filter and repo not in repo_filter and app["name"] not in repo_filter and full_repo not in repo_filter:
            continue
        ok = check_remote_repo_sync(full_repo, ci_config(data, app), vault, env) and ok

    for mobile in mobile_repositories(data):
        repo = repo_name(mobile)
        full_repo = repo_ref(mobile, default_owner)
        if repo_filter and repo not in repo_filter and full_repo not in repo_filter:
            continue
        mobile_ci = mobile.get("ci", {}) or {}
        raw_variables = {key: {"value": value} for key, value in (mobile.get("variables", {}) or {}).items()}
        ci = {
            "secrets": mobile_ci.get("secrets", {}) or {},
            "variables": {
                **raw_variables,
                **(mobile_ci.get("variables", {}) or {}),
            },
        }
        ok = check_remote_repo_sync(full_repo, ci, vault, env) and ok

    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    check = sub.add_parser("check", help="check remote .env.example against local runtime templates")
    check.add_argument("--app", default="")
    check.add_argument("--verbose", action="store_true")
    check.set_defaults(func=cmd_check)

    show = sub.add_parser("show", help="show detailed contract drift for one app")
    show.add_argument("--app", required=True)
    show.set_defaults(func=cmd_show)

    sync = sub.add_parser("github-sync", help="sync mapped GitHub secrets and variables")
    sync.add_argument("--repo", action="append", default=[])
    sync.add_argument("--dry-run", action="store_true")
    sync.set_defaults(func=cmd_github_sync)

    github_check = sub.add_parser("github-check", help="check mapped GitHub secrets and variables")
    github_check.add_argument("--repo", action="append", default=[])
    github_check.set_defaults(func=cmd_github_check)

    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
