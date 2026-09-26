#!/usr/bin/env python3
"""Read the portfolio app catalog for local DX scripts."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path
from typing import Any

import yaml


PROJECT_DIR = Path(__file__).resolve().parents[1]
APPS_FILE = PROJECT_DIR / "group_vars" / "all" / "apps.yml"
VARS_FILE = PROJECT_DIR / "group_vars" / "all" / "vars.yml"


def load_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise SystemExit(f"{path} must contain a YAML mapping")
    return data

def git_file_state(path: Path) -> str:
    if not path.exists():
        return "missing"
    if not (PROJECT_DIR / ".git").exists():
        return "unknown"

    rel_path = path.relative_to(PROJECT_DIR).as_posix()
    ignored = subprocess.run(
        ["git", "check-ignore", "-q", rel_path],
        cwd=PROJECT_DIR,
        capture_output=True,
        check=False,
    )
    if ignored.returncode == 0:
        return "ignored"

    tracked = subprocess.run(
        ["git", "ls-files", "--error-unmatch", rel_path],
        cwd=PROJECT_DIR,
        capture_output=True,
        check=False,
        text=True,
    )
    if tracked.returncode == 0:
        return "tracked"
    return "untracked"


def apps() -> list[dict[str, Any]]:
    data = load_yaml(APPS_FILE)
    items = data.get("portfolio_apps", [])
    if not isinstance(items, list):
        raise SystemExit("portfolio_apps must be a list")
    enabled = [item for item in items if item.get("enabled", True)]
    pui = data.get("pui_app")
    if isinstance(pui, dict) and pui.get("enabled", True):
        enabled.append(pui)
    return enabled


def mobile_repositories() -> list[dict[str, Any]]:
    data = load_yaml(APPS_FILE)
    items = data.get("mobile_repositories", [])
    if not isinstance(items, list):
        raise SystemExit("mobile_repositories must be a list")
    return items


def owner() -> str:
    return str(load_yaml(VARS_FILE).get("github_username", ""))


def repo_owner(item: dict[str, Any]) -> str:
    return str(item.get("repo_owner") or owner())


def repo_name(item: dict[str, Any]) -> str:
    return str(item.get("repo", item["name"]))


def repo_ref(item: dict[str, Any]) -> str:
    return f"{repo_owner(item)}/{repo_name(item)}"

def find_app(app_name: str) -> dict[str, Any]:
    for app in apps():
        if app["name"] == app_name:
            return app
    raise SystemExit(f"Unknown app: {app_name}")


def image_name(item: dict[str, Any]) -> str:
    image = item.get("image")
    if image:
        return str(image).removeprefix("ghcr.io/").rsplit(":", 1)[0]
    return f"{repo_owner(item)}/{item.get('image_name', repo_name(item))}"


def cmd_list(_: argparse.Namespace) -> int:
    print(f"{'APP':32} {'STACK':10} {'REPO':42} {'IMAGE':42} DOMAIN")
    for app in apps():
        proxy = app.get("proxy", {})
        domain = proxy.get("domain") or proxy.get("subdomain", "-")
        print(f"{app.get('display_name', app['name']):32} {app['stack']:10} {repo_ref(app):42} {image_name(app):42} {domain}")
    return 0


def cmd_repos(_: argparse.Namespace) -> int:
    seen: set[str] = set()
    for app in apps() + mobile_repositories():
        repo = repo_name(app)
        if repo not in seen:
            print(repo)
            seen.add(repo)
    return 0


def cmd_repo_refs(_: argparse.Namespace) -> int:
    seen: set[str] = set()
    for app in apps() + mobile_repositories():
        ref = repo_ref(app)
        if ref not in seen:
            print(ref)
            seen.add(ref)
    return 0


def cmd_domains_shell(_: argparse.Namespace) -> int:
    domains: dict[str, list[str]] = {}
    for app in apps():
        dns = app.get("dns")
        if not dns:
            continue
        domain = dns["domain"]
        domains.setdefault(domain, [])
        for record in dns.get("records", []):
            if record not in domains[domain]:
                domains[domain].append(record)
    for domain, records in domains.items():
        print(f"{domain}:{' '.join(records)}")
    return 0


def cmd_mobile_vars(_: argparse.Namespace) -> int:
    for repo in mobile_repositories():
        variables = repo.get("variables", {})
        for key, value in variables.items():
            print(f"{repo_ref(repo)}\t{key}\t{value}")
    return 0


def cmd_workflows(_: argparse.Namespace) -> int:
    seen: set[str] = set()
    for app in apps() + mobile_repositories():
        ref = repo_ref(app)
        if ref in seen:
            continue
        seen.add(ref)
        workflow = (app.get("build", {}) or {}).get("workflow", "build-and-deploy.yml")
        print(f"{ref}\t{workflow}")
    return 0


def cmd_env_check(args: argparse.Namespace) -> int:
    selected = [app for app in apps() if not args.app or app["name"] == args.app]
    if args.app and not selected:
        print(f"Unknown app: {args.app}", file=sys.stderr)
        return 1

    failed = 0
    for app in selected:
        env_template = app.get("env_template")
        if not env_template:
            print(f"OK   {app['name']}: no env template required")
            continue
        path = PROJECT_DIR / env_template
        state = git_file_state(path)
        if state == "tracked" or state == "unknown":
            print(f"OK   {app['name']}: {env_template}")
        elif state == "ignored":
            print(f"MISS {app['name']}: {env_template} exists locally but is ignored by git")
            failed += 1
        elif state == "untracked":
            print(f"MISS {app['name']}: {env_template} exists locally but is not tracked by git")
            failed += 1
        else:
            print(f"MISS {app['name']}: {env_template}")
            failed += 1
    return 1 if failed else 0

def cmd_deploy_tags(args: argparse.Namespace) -> int:
    app = find_app(args.app)
    if app["name"] == "pui":
        print("pui-setup")
        return 0
    tags = ["portfolio-apps"]
    if args.include_runtime_deps and app.get("requires_warp_proxy", False):
        tags.insert(0, "cloudflare-warp-setup")
    print(",".join(tags))
    return 0


def cmd_doctor(_: argparse.Namespace) -> int:
    failed = 0
    names: set[str] = set()
    repos: set[str] = set()
    for app in apps():
        name = app.get("name")
        if not name or name in names:
            print(f"Invalid or duplicate app name: {name}", file=sys.stderr)
            failed += 1
        names.add(name)
        repo = repo_ref(app)
        repos.add(repo)
        if app.get("stack") not in {"laravel", "nextjs", "golang", "express", "php", "compose"}:
            print(f"{name}: unsupported stack {app.get('stack')}", file=sys.stderr)
            failed += 1
        if "proxy" in app and not (app["proxy"].get("domain") or app["proxy"].get("subdomain")):
            print(f"{name}: proxy needs domain or subdomain", file=sys.stderr)
            failed += 1
        if "proxy" in app and app["proxy"].get("forward_port") is not None:
            expected_port = app.get("app_port", 80 if app.get("stack") == "laravel" else 3000)
            if int(app["proxy"]["forward_port"]) != int(expected_port):
                print(
                    f"{name}: proxy.forward_port {app['proxy']['forward_port']} != app_port {expected_port}",
                    file=sys.stderr,
                )
                failed += 1
        build = app.get("build", {})
        if build and app.get("stack") != "compose" and not build.get("dockerfile"):
            print(f"{name}: build.dockerfile is empty", file=sys.stderr)
            failed += 1
        if build and not build.get("workflow"):
            print(f"{name}: build.workflow is empty", file=sys.stderr)
            failed += 1
        env_template = app.get("env_template")
        if env_template:
            env_path = PROJECT_DIR / env_template
            env_state = git_file_state(env_path)
            if env_state == "missing":
                print(f"{name}: missing env template {env_template}", file=sys.stderr)
                failed += 1
            elif env_state == "ignored":
                print(f"{name}: env template is ignored by git: {env_template}", file=sys.stderr)
                failed += 1
            elif env_state == "untracked":
                print(f"{name}: env template is not tracked by git: {env_template}", file=sys.stderr)
                failed += 1

    print(f"Apps: {len(names)}")
    print(f"Repositories: {len(repos)}")
    print(f"Mobile repositories: {len(mobile_repositories())}")
    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list").set_defaults(func=cmd_list)
    sub.add_parser("repos").set_defaults(func=cmd_repos)
    sub.add_parser("repo-refs").set_defaults(func=cmd_repo_refs)
    sub.add_parser("domains-shell").set_defaults(func=cmd_domains_shell)
    sub.add_parser("mobile-vars").set_defaults(func=cmd_mobile_vars)
    sub.add_parser("workflows").set_defaults(func=cmd_workflows)
    sub.add_parser("doctor").set_defaults(func=cmd_doctor)

    deploy_tags = sub.add_parser("deploy-tags")
    deploy_tags.add_argument("--app", required=True)
    deploy_tags.add_argument(
        "--include-runtime-deps",
        action="store_true",
        help="include infra/runtime tags required by the app (for real deploys, not dry-runs)",
    )
    deploy_tags.set_defaults(func=cmd_deploy_tags)

    env_check = sub.add_parser("env-check")
    env_check.add_argument("--app", default="")
    env_check.set_defaults(func=cmd_env_check)

    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
