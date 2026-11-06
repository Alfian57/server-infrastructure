from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("infra_dispatch", ROOT / "scripts" / "infra.py")
infra = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(infra)


def options(**overrides: str) -> dict[str, str]:
    values = {
        "action": "help", "group": "", "app": "", "service": "",
        "destroy_data": "", "source_dir": "", "all": "",
    }
    values.update(overrides)
    return values


class InfraDispatchTests(unittest.TestCase):
    def test_default_command_is_help(self) -> None:
        self.assertIsNone(infra.command_for(options()))

    def test_deploy_requires_explicit_target(self) -> None:
        with self.assertRaisesRegex(ValueError, "requires GROUP or APP"):
            infra.validate_options(options(action="deploy"))

    def test_deploy_maps_group_and_app_to_scoped_dispatcher(self) -> None:
        selected = options(action="deploy", group="lomba", app="guardian-lab")
        infra.validate_options(selected)
        command = infra.command_for(selected)
        self.assertEqual(command[-5:], ["deploy", "--group", "lomba", "--app", "guardian-lab"])

    def test_reset_db_requires_one_application_target(self) -> None:
        with self.assertRaisesRegex(ValueError, "requires APP"):
            infra.validate_options(options(action="reset-db", group="uty"))
        selected = options(action="reset-db", app="sistertika-uty-api")
        infra.validate_options(selected)
        self.assertEqual(infra.command_for(selected)[-3:], ["reset-db", "--app", "sistertika-uty-api"])

    def test_reset_db_does_not_accept_redundant_destroy_flag(self) -> None:
        with self.assertRaisesRegex(ValueError, "does not accept: DESTROY_DATA"):
            infra.validate_options(options(action="reset-db", app="pui", destroy_data="yes"))

    def test_destructive_operation_requires_explicit_confirmation(self) -> None:
        with self.assertRaisesRegex(ValueError, "DESTROY_DATA=yes"):
            infra.validate_options(options(action="decommission"))

    def test_destructive_confirmation_maps_to_internal_flag(self) -> None:
        selected = options(action="decommission", destroy_data="yes")
        infra.validate_options(selected)
        self.assertEqual(infra.command_for(selected)[-1], "--destroy-data")

    def test_unknown_and_legacy_actions_are_rejected(self) -> None:
        for action in ("deploy-aldera-router-staging", "server-setup", "unknown"):
            with self.subTest(action=action), self.assertRaisesRegex(ValueError, "Unknown ACTION"):
                infra.validate_options(options(action=action))

    def test_make_exposes_only_the_unified_operator_target(self) -> None:
        default = subprocess.run(["make", "-n", "infra"], cwd=ROOT, capture_output=True, text=True)
        legacy = subprocess.run(["make", "-n", "deploy"], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(default.returncode, 0, default.stderr)
        self.assertNotEqual(legacy.returncode, 0)

    def test_platform_requires_service(self) -> None:
        with self.assertRaisesRegex(ValueError, "requires SERVICE"):
            infra.validate_options(options(action="platform"))

    def test_vault_action_only_accepts_group(self) -> None:
        with self.assertRaisesRegex(ValueError, "does not accept: APP"):
            infra.validate_options(options(action="vault-view", app="guardian-lab"))

    def test_vault_group_cannot_traverse_paths(self) -> None:
        selected = options(action="vault-view", group="../platform")
        infra.validate_options(selected)
        with self.assertRaisesRegex(ValueError, "valid project group ID"):
            infra.command_for(selected)


if __name__ == "__main__":
    unittest.main()
