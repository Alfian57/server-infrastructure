#!/usr/bin/env python3
"""Single operator-facing dispatcher for Ansible infrastructure actions."""

from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

DEPLOY_ACTIONS = {
    "deploy": "deploy",
    "reset-db": "reset-db",
    "check": "check",
    "platform": "platform",
    "preflight": "preflight",
    "helpers": "helpers",
    "dns": "dns",
    "decommission": "decommission",
    "consolidate": "consolidate",
    "all": "all",
    "rollout": "rollout",
    "resume-rollout": "resume-rollout",
    "security-hardening": "security-hardening",
}

ACTIONS = {
    "help", "list", "plan", *DEPLOY_ACTIONS, "cloud-services", "cloud-check", "inventory-ssh",
    "bootstrap", "validate", "validate-context", "env-check", "env-show",
    "repo-audit", "github-sync", "github-check", "trigger-workflows",
    "vault-view", "vault-edit", "ping",
}


def options_from_env() -> dict[str, str]:
    options = {key.lower(): os.environ.get(key, "").strip()
               for key in ("ACTION", "GROUP", "APP", "SERVICE", "DESTROY_DATA", "SOURCE_DIR", "ALL")}
    for key in ("destroy_data", "all"):
        if options[key].lower() in {"false", "no", "0"}:
            options[key] = ""
    return options


def validate_options(options: dict[str, str]) -> None:
    action = options["action"] or "help"
    if action not in ACTIONS:
        raise ValueError(f"Unknown ACTION: {action}. Use ACTION=help to list supported actions.")

    group, app, service = options["group"], options["app"], options["service"]
    destroy = options["destroy_data"]
    allowed = {
        "help": set(), "list": {"group", "app"}, "plan": {"group", "app"},
        "deploy": {"group", "app"}, "reset-db": {"group", "app"},
        "check": {"group", "app"}, "dns": {"group", "app"},
        "all": set(), "platform": {"service"}, "preflight": set(), "helpers": set(),
        "decommission": {"destroy_data"}, "consolidate": {"destroy_data"},
        "rollout": {"destroy_data"}, "resume-rollout": {"destroy_data"},
        "bootstrap": set(), "security-hardening": set(), "validate": set(),
        "validate-context": {"group"}, "env-check": {"group", "app"},
        "env-show": {"group", "app", "source_dir"}, "repo-audit": {"group", "app", "source_dir"},
        "github-sync": {"group", "app", "all"}, "github-check": {"group", "app", "all"},
        "trigger-workflows": {"group", "app", "all"}, "vault-view": {"group"},
        "vault-edit": {"group"}, "ping": set(), "cloud-check": set(), "inventory-ssh": set(),
        "cloud-services": {"group", "app"},
    }
    provided = {key for key, value in options.items() if key != "action" and value}
    unexpected = provided - allowed[action]
    if unexpected:
        names = ", ".join(name.upper() for name in sorted(unexpected))
        raise ValueError(f"ACTION={action} does not accept: {names}")

    if action in {"deploy", "check", "dns", "plan"} and not (group or app):
        raise ValueError(f"ACTION={action} requires GROUP or APP")
    if action == "reset-db" and not app:
        raise ValueError("ACTION=reset-db requires APP; it resets one enabled non-production application")
    if action == "cloud-services" and not (group or app):
        raise ValueError("ACTION=cloud-services requires GROUP or APP")
    if action == "platform" and not service:
        raise ValueError("ACTION=platform requires SERVICE")
    if action in {"decommission", "consolidate", "rollout", "resume-rollout"} and destroy.lower() != "yes":
        raise ValueError(f"ACTION={action} requires DESTROY_DATA=yes")
    if action == "validate-context" and not group:
        raise ValueError("ACTION=validate-context requires GROUP")
    if action in {"env-show"} and not app:
        raise ValueError("ACTION=env-show requires APP")
    if action in {"github-sync", "github-check", "trigger-workflows"} and not (group or app or options["all"].lower() in {"yes", "true", "1"}):
        raise ValueError(f"ACTION={action} requires GROUP, APP, or ALL=yes")
    if options["all"] and options["all"].lower() not in {"yes", "true", "1"}:
        raise ValueError("ALL accepts only yes")


def target_args(options: dict[str, str]) -> list[str]:
    args: list[str] = []
    if options["group"]:
        args += ["--group", options["group"]]
    if options["app"]:
        args += ["--app", options["app"]]
    return args


def command_for(options: dict[str, str]) -> list[str] | None:
    """Build a subprocess argv without shell interpolation."""
    action = options["action"] or "help"
    py = sys.executable
    targets = target_args(options)

    if action == "help":
        return None
    if action in {"list", "plan"}:
        return [py, "scripts/catalog.py", action, *targets]
    if action in DEPLOY_ACTIONS:
        args = [py, "scripts/deploy.py", DEPLOY_ACTIONS[action], *targets]
        if options["service"]:
            args += ["--service", options["service"]]
        if options["destroy_data"].lower() == "yes":
            args.append("--destroy-data")
        return args
    if action == "validate-context":
        return None
    if action == "env-check":
        return [py, "scripts/app-catalog.py", "env-check", *targets]
    if action == "env-show":
        return [py, "scripts/env-contracts.py", "show", *targets, *source_dir_args(options)]
    if action == "repo-audit":
        return [py, "scripts/repo-audit.py", "check", *targets, *source_dir_args(options)]
    if action in {"github-sync", "github-check"}:
        args = [py, "scripts/env-contracts.py", action, *targets]
        if options["all"].lower() in {"yes", "true", "1"}:
            args.append("--all")
        return args
    if action == "trigger-workflows":
        args = [py, "scripts/trigger-workflows.py", *targets]
        if options["all"].lower() in {"yes", "true", "1"}:
            args.append("--all")
        return args
    if action in {"vault-view", "vault-edit"}:
        if options["group"] and not re.fullmatch(r"[a-z0-9-]+", options["group"]):
            raise ValueError("GROUP must be a valid project group ID")
        vault = ROOT / (f"projects/{options['group']}/vault.yml" if options["group"] else "platform/vault.yml")
        if not vault.resolve().is_relative_to(ROOT.resolve()) or not vault.is_file():
            raise ValueError("The selected vault file does not exist")
        return ["ansible-vault", "view" if action == "vault-view" else "edit", str(vault)]
    if action == "ping":
        return ["ansible", "all", "-m", "ping"]
    if action == "cloud-check":
        return ["bash", "scripts/check-cloud-services.sh"]
    if action == "inventory-ssh":
        return ["bash", "scripts/update-inventory-ssh.sh"]
    raise ValueError(f"No dispatcher is configured for ACTION={action}")


def source_dir_args(options: dict[str, str]) -> list[str]:
    return ["--source-dir", options["source_dir"]] if options["source_dir"] else []


def help_text() -> str:
    return """One operator command for infrastructure and Ansible tasks:

  make infra ACTION=deploy GROUP=lomba APP=guardian-lab
  make infra ACTION=reset-db APP=ruang-tenang-api
  make infra ACTION=plan GROUP=uty
  make infra ACTION=platform SERVICE=postgres
  make infra ACTION=decommission DESTROY_DATA=yes

Actions: help, list, plan, deploy, reset-db, check, all, platform, preflight, helpers,
dns, decommission, consolidate, rollout, resume-rollout, bootstrap,
security-hardening, validate, validate-context, env-check, env-show,
repo-audit, github-sync, github-check, trigger-workflows, vault-view,
vault-edit, ping, cloud-services, cloud-check, inventory-ssh.
"""


def run_validation() -> int:
    commands = [
        [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"],
        ["ansible-playbook", "playbooks/deploy-group.yml", "--syntax-check"],
        ["ansible-playbook", "playbooks/platform.yml", "--syntax-check"],
        ["ansible-playbook", "playbooks/decommission.yml", "--syntax-check"],
        ["ansible-playbook", "playbooks/consolidate-postgres.yml", "--syntax-check"],
        ["ansible-playbook", "playbooks/install-helpers.yml", "--syntax-check"],
        ["ansible-playbook", "playbooks/security-hardening.yml", "--syntax-check"],
        ["ansible-playbook", "playbooks/public-hosts.yml", "--syntax-check"],
        ["ansible-playbook", "playbooks/bootstrap-ssh.yml", "--syntax-check"],
        ["ansible-playbook", "playbooks/validate-context.yml", "--syntax-check"],
        ["ansible-lint", "playbooks/deploy-group.yml", "playbooks/platform.yml", "playbooks/decommission.yml",
         "playbooks/consolidate-postgres.yml", "playbooks/install-helpers.yml", "playbooks/security-hardening.yml"],
        [sys.executable, "scripts/check-shell.py"],
        [sys.executable, "scripts/catalog.py", "doctor"],
        [sys.executable, "scripts/app-catalog.py", "doctor"],
    ]
    for command in commands:
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode:
            return result.returncode
    return 0


def run_bootstrap() -> int:
    result = subprocess.run(["bash", "scripts/prepare-bootstrap-inventory.sh"], cwd=ROOT)
    if result.returncode:
        return result.returncode
    auth_file = ROOT / ".ansible" / "bootstrap-auth-method"
    if not auth_file.is_file():
        raise RuntimeError("Bootstrap inventory preparation did not record an authentication method")
    command = ["ansible-playbook", "playbooks/bootstrap-ssh.yml", "-i", "inventory/hosts.ini",
               "--vault-password-file=.vault_pass"]
    if auth_file.read_text(encoding="utf-8").strip() == "password":
        command.append("--ask-pass")
    return subprocess.run(command, cwd=ROOT).returncode


def run_context_validation(group: str) -> int:
    commands = [
        [sys.executable, "scripts/catalog.py", "doctor", "--group", group],
        [sys.executable, "scripts/app-catalog.py", "env-check", "--group", group],
        ["ansible-playbook", "playbooks/validate-context.yml", "-i", "localhost,", "-e", f"deployment_group={group}"],
    ]
    for command in commands:
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode:
            return result.returncode
    return 0


def run_cloud_services(options: dict[str, str]) -> int:
    targets = target_args(options)
    commands = [
        [sys.executable, "scripts/catalog.py", "plan", *targets],
        [sys.executable, "scripts/env-contracts.py", "github-sync", *targets],
        [sys.executable, "scripts/deploy.py", "dns", *targets],
    ]
    for command in commands:
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode:
            return result.returncode
    return 0


def main() -> int:
    options = options_from_env()
    try:
        validate_options(options)
        action = options["action"] or "help"
        if action == "help":
            print(help_text())
            return 0
        if action == "bootstrap":
            return run_bootstrap()
        if action == "validate":
            return run_validation()
        if action == "validate-context":
            return run_context_validation(options["group"])
        if action == "cloud-services":
            return run_cloud_services(options)
        else:
            command = command_for(options)
        if command is None:
            raise RuntimeError("Unexpected empty command")
        return subprocess.run(command, cwd=ROOT).returncode
    except (ValueError, RuntimeError, OSError) as exc:
        print(f"infra: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
