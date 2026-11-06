"""Shared, non-secret application catalog. Loading a target never reads another group."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


def read(path: Path) -> dict:
    value = yaml.safe_load(path.read_text()) or {}
    if not isinstance(value, dict):
        raise ValueError(f"Expected a mapping: {path.relative_to(ROOT)}")
    return value


def index() -> dict:
    value = read(ROOT / "projects/index.yml")
    value["groups"] = value["group_registry"]
    return value


def group_for(app: str) -> str:
    try:
        return index()["applications"][app]
    except KeyError as exc:
        raise ValueError(f"Unknown application: {app}") from exc


def select(group: str = "", app: str = "", *, require_target: bool = False,
           enabled_only: bool = False, default_only: bool = False) -> list[dict]:
    registry = index()
    if app:
        actual_group = group_for(app)
        if group and group != actual_group:
            raise ValueError(f"{app} belongs to {actual_group}, not {group}")
        group = actual_group
    if group and group not in registry["groups"]:
        raise ValueError(f"Unknown group: {group}")
    if require_target and not (group or app):
        raise ValueError("A GROUP or APP target is required; use deploy-all explicitly")
    ids = [name for name, owner in registry["applications"].items()
           if (not group or owner == group) and (not app or name == app)]
    items = []
    for name in ids:
        owner = registry["applications"][name]
        item = read(ROOT / "projects" / owner / "apps" / name / "app.yml")
        if item.get("name") != name or item.get("group") != owner:
            raise ValueError(f"Catalog identity mismatch: {name}")
        if not isinstance(item.get("production"), bool):
            raise ValueError(f"Catalog production status must be a boolean: {name}")
        if enabled_only and not item.get("enabled", True):
            continue
        if default_only and not app and not item.get("default_deploy", True):
            continue
        items.append(item)
    if app and enabled_only and not items:
        raise ValueError(f"Application is disabled: {app}")
    return items


def catalog(group: str = "", app: str = "") -> dict:
    items = select(group, app)
    selected_groups = {a["group"] for a in items}
    data = read(ROOT / "platform/catalog.yml")
    data["portfolio_apps"] = [a for a in items if a["deployment"] == "portfolio"]
    data["pui_app"] = next((a for a in items if a["deployment"] == "pui"), {})
    data["guardian_lab_apps"] = [a for a in items if a["deployment"] == "guardian"]
    data["aldera_router_apps"] = [a for a in items if a["deployment"] == "aldera-router"]
    data["applications"] = items
    data["mobile_repositories"] = [m for g in sorted(selected_groups)
                                   for m in read(ROOT / "projects" / g / "vars.yml").get("mobile_repositories", [])]
    return data


def domains(item: dict) -> list[str]:
    hosts = item.get("proxy_hosts", []) + ([item["proxy"]] if item.get("proxy") else [])
    result = []
    for host in hosts:
        value = host.get("domain") or f"{host['subdomain']}.alfian-gading.my.id"
        result.extend(host.get("domains") or [value])
        result.extend(host.get("additional_domains", []))
    return list(dict.fromkeys(result))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["list", "plan", "export", "doctor"])
    parser.add_argument("--group", default="")
    parser.add_argument("--app", default="")
    args = parser.parse_args()
    try:
        items = select(args.group, args.app, require_target=args.command == "plan",
                       enabled_only=args.command == "plan", default_only=args.command == "plan")
        if args.command == "list":
            print(f"{'GROUP':14} {'APPLICATION':32} {'DEPLOY':9} {'PRODUCTION':14} DOMAINS")
            for a in items:
                deployment = 'enabled' if a.get('enabled', True) else 'disabled'
                production = 'production' if a['production'] else 'non-production'
                print(f"{a['group']:14} {a['name']:32} {deployment:9} {production:14} {', '.join(domains(a)) or '(internal)'}")
        elif args.command == "plan":
            print(json.dumps({"applications": [a["name"] for a in items],
                              "production_status": {a["name"]: a["production"] for a in items},
                              "services": sorted({s for a in items for s in a.get("requires", [])}),
                              "domains": [d for a in items for d in domains(a)],
                              "disabled_policy": "skip", "delete_resources": []}, indent=2))
        elif args.command == "export":
            print(json.dumps(catalog(args.group, args.app)))
        else:
            seen = {}
            for a in items:
                for domain in domains(a):
                    if domain in seen:
                        raise ValueError(f"Domain {domain} claimed by {seen[domain]} and {a['name']}")
                    seen[domain] = a["name"]
                if a.get("env_template") and not (ROOT / a["env_template"]).is_file():
                    raise ValueError(f"Missing environment template: {a['name']}")
            print(f"Validated {len(items)} applications; ownership and templates OK")
        return 0
    except (ValueError, OSError) as exc:
        parser.exit(2, f"{exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
