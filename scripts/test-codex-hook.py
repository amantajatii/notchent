import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("install-codex-hook.py")
spec = importlib.util.spec_from_file_location("installer", SCRIPT)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

class HookInstallTests(unittest.TestCase):
    def test_preserves_user_hooks_is_idempotent_and_backs_up_exact_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            home = root / "codex"
            home.mkdir()
            target = home / "hooks.json"
            original = b'{"custom":true,"hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"existing-user-hook"}]}]}}'
            target.write_bytes(original)
            command = [sys.executable, str(SCRIPT), "--helper", "/usr/bin/true", "--support", str(root / "support"), "--codex-home", str(home)]
            subprocess.run(command, check=True, capture_output=True)
            first = target.read_bytes()
            self.assertEqual(json.loads(first)["hooks"]["PermissionRequest"][0]["hooks"][0]["command"], "existing-user-hook")
            self.assertEqual(next(home.glob("hooks.json.island-backup-*")).read_bytes(), original)
            self.assertTrue(json.loads(first)["custom"])
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(target.read_bytes(), first)
            self.assertEqual(len(list(home.glob("hooks.json.island-backup-*"))), 1)

    def test_malformed_configuration_is_rejected(self):
        with self.assertRaises(ValueError):
            installer.merged({"hooks": {"PermissionRequest": {}}}, "helper")

if __name__ == "__main__":
    unittest.main()
