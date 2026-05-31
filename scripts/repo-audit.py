#!/usr/bin/env python3
"""Audit remote portfolio repositories against the local app catalog."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

import yaml

PROJECT_DIR = Path(__file__).resolve().parents[1]
APPS_FILE = PROJECT_DIR / "group_vars" / "all" / "apps.yml"
VARS_FILE = PROJECT_DIR / "group_vars" / "all" / "vars.yml"
ENV_FILE = PROJECT_DIR / ".env"

WORKFLOW_IMAGE_RE = re.compile(r"^\s*IMAGE_NAME:\s*(.+?)\s*$", re.MULTILINE)
WORKFLOW_FILE_RE = re.compile(r"^\s*file:\s*(.+?)\s*$", re.MULTILINE)
WORKFLOW_SECRET_RE = re.compile(r"secrets\.([A-Za-z_][A-Za-z0-9_]*)")
WORKFLOW_VAR_RE = re.compile(r"vars\.([A-Za-z_][A-Za-z0-9_]*)")
EXPOSE_RE = re.compile(r"^\s*EXPOSE\s+([0-9]+)", re.MULTILINE)
ENV_KEY_RE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$")

STACK_MARKERS = {
    "laravel": "composer.json",
    "golang": "go.mod",
    "nextjs": "package.json",
    "express": "package.json",
    "php": "index.php",
}


class AuditError(Exception):
    """Raised when remote GitHub data cannot be read."""


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise SystemExit(f"{path} must contain a YAML mapping")
    return data


def dotenv_token() -> str:
    if not ENV_FILE.exists():
        return ""
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        match = ENV_KEY_RE.match(line)
        if not match:
            continue
        if match.group(1) in {"GH_TOKEN", "GITHUB_TOKEN", "GITHUB_PAT_TOKEN"}:
            return match.group(2).strip().strip("\"'")
    return ""


def gh_env() -> dict[str, str]:
    env = os.environ.copy()
    if not env.get("GH_TOKEN"):
        token = dotenv_token()
        if token:
            env["GH_TOKEN"] = token
    return env


def gh_api(path: str, env: dict[str, str]) -> Any:
    result = subprocess.run(
        ["gh", "api", path],
        cwd=PROJECT_DIR,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise AuditError(result.stderr.strip() or f"gh api failed for {path}")
    return json.loads(result.stdout)


def repo_tree(owner: str, repo: str, env: dict[str, str]) -> set[str]:
    data = gh_api(f"repos/{owner}/{repo}/git/trees/HEAD?recursive=1", env)
    return {item["path"] for item in data.get("tree", []) if item.get("type") == "blob"}


def content(owner: str, repo: str, path: str, env: dict[str, str]) -> str:
    data = gh_api(f"repos/{owner}/{repo}/contents/{path}", env)
    raw = base64.b64decode(str(data["content"]))
    return raw.decode("utf-8")


def parse_env_example_port(text: str) -> int | None:
    for line in text.splitlines():
        match = ENV_KEY_RE.match(line)
        if not match:
            continue
        if match.group(1) in {"APP_PORT", "PORT"}:
            value = match.group(2).strip().strip("\"'")
            if value.isdigit():
                return int(value)
    return None


def workflow_dockerfile(workflow: str) -> str:
    match = WORKFLOW_FILE_RE.search(workflow)
    if not match:
        return "Dockerfile"
    return match.group(1).strip().strip("\"'").removeprefix("./")


def workflow_image(workflow: str, owner: str, repo: str) -> str:
    match = WORKFLOW_IMAGE_RE.search(workflow)
    if not match:
        return ""
    value = match.group(1).strip().strip("\"'")
    value = value.replace("${{ github.repository_owner }}", owner)
    value = value.replace("${{github.repository_owner}}", owner)
    value = value.replace("${{ github.repository }}", f"{owner}/{repo}")
    value = value.replace("${{github.repository}}", f"{owner}/{repo}")
    return value


def app_image_name(app: dict[str, Any]) -> str:
    image = app.get("image")
    if image:
        return str(image).removeprefix("ghcr.io/").rsplit(":", 1)[0]
    return str(app.get("image_name") or app.get("repo") or app["name"])

def repo_owner(app: dict[str, Any], default_owner: str) -> str:
    return str(app.get("repo_owner") or default_owner)

def repo_name(app: dict[str, Any]) -> str:
    return str(app.get("repo") or app["name"])

def app_path(app: dict[str, Any], path: str) -> str:
    root = str(app.get("app_root") or "").strip("/")
    clean_path = path.strip("/")
    return f"{root}/{clean_path}" if root else clean_path

def repo_ref(app: dict[str, Any], default_owner: str) -> str:
    return f"{repo_owner(app, default_owner)}/{repo_name(app)}"


def ci_config(data: dict[str, Any], app: dict[str, Any]) -> dict[str, dict[str, Any]]:
    defaults = data.get("github_actions_defaults", {}) or {}
    app_ci = app.get("ci", {}) or {}
    return {
        "secrets": {**(defaults.get("secrets", {}) or {}), **(app_ci.get("secrets", {}) or {})},
        "variables": {**(defaults.get("variables", {}) or {}), **(app_ci.get("variables", {}) or {})},
    }


def app_port(app: dict[str, Any]) -> int:
    if "app_port" in app:
        return int(app["app_port"])
    return 80 if app["stack"] == "laravel" else 3000


def audit_app(default_owner: str, data: dict[str, Any], app: dict[str, Any], env: dict[str, str], verbose: bool) -> bool:
    owner = repo_owner(app, default_owner)
    repo = repo_name(app)
    build = app.get("build", {}) or {}
    dockerfile = str(build.get("dockerfile") or "Dockerfile")
    workflow = str(build.get("workflow") or "build-and-deploy.yml")
    expected_image = app_image_name(app)
    if "/" not in expected_image:
        expected_image = f"{owner}/{expected_image}"
    errors: list[str] = []
    notes: list[str] = []

    try:
        tree = repo_tree(owner, repo, env)
    except AuditError as exc:
        print(f"FAIL {app['name']}: cannot read {owner}/{repo} ({exc})")
        return False

    marker = STACK_MARKERS.get(str(app["stack"]))
    marker_path = app_path(app, marker) if marker else ""
    if marker and marker not in tree:
        if marker_path not in tree:
            errors.append(f"missing stack marker {marker_path} for stack={app['stack']}")

    if dockerfile not in tree:
        errors.append(f"catalog build.dockerfile not found: {dockerfile}")

    workflow_path = f".github/workflows/{workflow}"
    if workflow_path not in tree:
        errors.append(f"catalog build.workflow not found: {workflow_path}")
        workflow_text = ""
    else:
        try:
            workflow_text = content(owner, repo, workflow_path, env)
        except AuditError as exc:
            errors.append(f"cannot read workflow {workflow_path}: {exc}")
            workflow_text = ""

    if workflow_text:
        actual_dockerfile = workflow_dockerfile(workflow_text)
        if actual_dockerfile != dockerfile:
            errors.append(f"workflow dockerfile is {actual_dockerfile}, catalog says {dockerfile}")
        actual_image = workflow_image(workflow_text, owner, repo)
        if actual_image and actual_image != expected_image:
            errors.append(f"workflow IMAGE_NAME is {actual_image}, catalog image is {expected_image}")
        if "workflow_dispatch:" not in workflow_text:
            errors.append(f"workflow {workflow} has no workflow_dispatch trigger")
        ci = ci_config(data, app)
        used_secrets = set(WORKFLOW_SECRET_RE.findall(workflow_text)) - {"GITHUB_TOKEN"}
        used_variables = set(WORKFLOW_VAR_RE.findall(workflow_text))
        missing_secrets = used_secrets - set(ci["secrets"])
        missing_variables = used_variables - set(ci["variables"])
        if missing_secrets:
            errors.append(f"workflow secrets not mapped in catalog: {sorted(missing_secrets)}")
        if missing_variables:
            errors.append(f"workflow variables not mapped in catalog: {sorted(missing_variables)}")

    dockerfile_text = ""
    if dockerfile in tree:
        try:
            dockerfile_text = content(owner, repo, dockerfile, env)
        except AuditError as exc:
            errors.append(f"cannot read Dockerfile {dockerfile}: {exc}")

    exposed_ports = {int(match) for match in EXPOSE_RE.findall(dockerfile_text)}
    if exposed_ports and app_port(app) not in exposed_ports:
        errors.append(f"catalog app_port={app_port(app)} but Dockerfile exposes {sorted(exposed_ports)}")

    env_contract_path = str(app.get("env_contract", {}).get("path") or app_path(app, ".env.example"))
    if app.get("env_contract", {}).get("required", True) and env_contract_path in tree:
        try:
            env_port = parse_env_example_port(content(owner, repo, env_contract_path, env))
        except AuditError:
            env_port = None
        if env_port is not None and env_port != app_port(app):
            errors.append(f".env.example port={env_port} but catalog app_port={app_port(app)}")

    proxy = app.get("proxy", {}) or {}
    if "forward_port" in proxy and int(proxy["forward_port"]) != app_port(app):
        errors.append(f"proxy.forward_port={proxy['forward_port']} but app_port={app_port(app)}")

    workflows = sorted(path.removeprefix(".github/workflows/") for path in tree if path.startswith(".github/workflows/"))
    if verbose and workflows:
        notes.append(f"workflows: {', '.join(workflows)}")
    if verbose and exposed_ports:
        notes.append(f"expose: {', '.join(str(port) for port in sorted(exposed_ports))}")

    if errors:
        print(f"FAIL {app['name']}: {owner}/{repo}")
        for error in errors:
            print(f"  - {error}")
        for note in notes:
            print(f"  {note}")
        return False

    print(f"OK   {app['name']}: {repo} ({app['stack']}, {dockerfile}, {workflow}, {expected_image})")
    for note in notes:
        print(f"  {note}")
    return True


def cmd_check(args: argparse.Namespace) -> int:
    data = load_yaml(APPS_FILE)
    default_owner = str(load_yaml(VARS_FILE).get("github_username", "")).strip()
    if not default_owner:
        raise SystemExit("github_username is not set")
    apps = [app for app in data.get("portfolio_apps", []) if app.get("enabled", True)]
    if args.app:
        apps = [
            app
            for app in apps
            if app["name"] == args.app or repo_name(app) == args.app or repo_ref(app, default_owner) == args.app
        ]
    if not apps:
        print(f"Unknown app: {args.app}", file=sys.stderr)
        return 1

    env = gh_env()
    failed = 0
    for app in apps:
        failed += 0 if audit_app(default_owner, data, app, env, args.verbose) else 1
    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    check = sub.add_parser("check", help="audit remote repo Dockerfile/workflow/image settings")
    check.add_argument("--app", default="")
    check.add_argument("--verbose", action="store_true")
    check.set_defaults(func=cmd_check)

    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
