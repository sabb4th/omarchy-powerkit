"""Exercise source launches and optional migration without touching the desktop."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLUGIN_ID = "io.github.sabb4th.powerkit"


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="powerkit-distribution-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.shims = self.base / "shims"
        self.shims.mkdir()
        self.calls = self.base / "calls"
        self.env = dict(os.environ, PATH=str(self.shims) + ":/usr/bin:/bin",
                        XDG_CONFIG_HOME=str(self.base / "config"),
                        XDG_STATE_HOME=str(self.base / "state"),
                        XDG_CACHE_HOME=str(self.base / "cache"),
                        TEST_CALLS=str(self.calls))
        fake_batctl = self.shim("batctl", "exit 0\n")
        self.setup_script = self.base / "setup.sh"
        self.setup_script.write_text((ROOT / "scripts/setup.sh").read_text().replace(
            "/usr/bin/batctl", str(fake_batctl)))

    def shim(self, name, body):
        path = self.shims / name
        path.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + body)
        path.chmod(0o755)
        return path

    def ready_dependencies(self):
        for command in ("cargo", "cc", "pacman", "systemctl", "powerprofilesctl", "pkexec", "jq", "tee"):
            if command in ("jq", "tee"):
                continue
            self.shim(command, "exit 0\n")

    def setup_installer(self):
        self.ready_dependencies()
        self.shim("omarchy", '''printf '%s\\n' "$*" >> "$TEST_CALLS"
if [[ $* == 'plugin list --json' ]]; then printf '[]\\n'; fi
''')
        self.shim("omarchy-shell", 'printf "%s\\n" "$*" >> "$TEST_CALLS"\n')
        for command in ("omarchy-plugin-validate", "powerprofilesctl", "omarchy-powerprofiles-set", "pkexec"):
            self.shim(command, 'exit 0\n')
        binary = self.base / "prebuilt"
        binary.write_text("#!/bin/sh\nexit 0\n")
        binary.chmod(0o755)
        return binary

    def invoke(self, script, *args):
        return subprocess.run(["bash", str(ROOT / script), *map(str, args)],
                              env=self.env, text=True, capture_output=True, timeout=20)

    @unittest.skipUnless(Path("/usr/bin/batctl").is_file(), "Migration integration requires the documented /usr/bin/batctl dependency")
    def test_explicit_migration_preserves_layout_and_archives_legacy(self):
        binary = self.setup_installer()
        config = self.base / "config/omarchy"
        legacy = config / "plugins/local.battery-studio"
        legacy.mkdir(parents=True)
        (legacy / "marker").write_text("legacy")
        shell = config / "shell.json"
        settings = {"bar": {"position": "bottom", "layout": {"right": [
            {"id": "omarchy.tray"}, {"id": "local.battery-studio", "custom": 7},
            {"id": "omarchy.audio"}]}}, "unrelated": {"keep": True}}
        shell.write_text(json.dumps(settings))
        refused = self.invoke("install.sh", "--prebuilt", binary)
        self.assertEqual(refused.returncode, 2, refused.stderr)
        self.assertEqual(json.loads(shell.read_text()), settings)
        self.assertTrue(legacy.exists())
        installed = self.invoke("install.sh", "--migrate", "--prebuilt", binary)
        self.assertEqual(installed.returncode, 0, installed.stderr)
        current = json.loads(shell.read_text())
        self.assertEqual(current["bar"]["layout"]["right"][1], {"id": PLUGIN_ID, "custom": 7})
        self.assertEqual(current["unrelated"], settings["unrelated"])
        self.assertEqual(current["bar"]["position"], "bottom")
        self.assertNotIn("plugin enable", self.calls.read_text())
        backups = self.base / "state/omarchy-powerkit/backups"
        self.assertTrue(list(backups.glob("local.battery-studio-*/marker")))
        self.assertTrue(list(backups.glob("shell.json-*")))
        target = config / "plugins" / PLUGIN_ID
        self.assertTrue((target / "bin/powerkit").is_file())
        removed = self.invoke("uninstall.sh")
        self.assertEqual(removed.returncode, 0, removed.stderr)
        self.assertFalse(target.exists())
        self.assertTrue(backups.exists())

    def test_setup_decline_does_not_install_or_switch_services(self):
        self.ready_dependencies()
        self.shim("systemctl", 'exit 1\n')
        self.shim("omarchy", 'echo unexpected >> "$TEST_CALLS"\n')
        result = subprocess.run(["bash", str(self.setup_script)],
                                input="n\n", env=self.env, text=True,
                                capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(self.calls.exists())

    def test_setup_installs_missing_aur_dependency_after_confirmation(self):
        self.ready_dependencies()
        marker = self.base / "installed"
        self.env["TEST_INSTALLED"] = str(marker)
        self.shim("pacman", '[[ -e $TEST_INSTALLED ]]\n')
        self.shim("omarchy", 'echo "$*" >> "$TEST_CALLS"\nif [[ $* == "pkg aur add batctl-tui" ]]; then touch "$TEST_INSTALLED"; fi\n')
        result = subprocess.run(["bash", str(self.setup_script)],
                                input="y\n", env=self.env, text=True,
                                capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(),
                         ["pkg add base-devel git", "pkg aur add batctl-tui"])

    def test_active_competing_service_blocks_activation(self):
        self.ready_dependencies()
        self.shim("systemctl", '[[ $* == "is-active --quiet tlp.service" ]]\n')
        self.shim("omarchy", 'echo unexpected >> "$TEST_CALLS"\n')
        result = subprocess.run(["bash", str(self.setup_script)], input="y\n",
                                env=self.env, text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 1)
        self.assertIn("tlp.service is active", result.stderr)
        self.assertFalse(self.calls.exists())

    def test_first_run_decline_is_not_repeated(self):
        fixture = self.base / "plugin/scripts"
        fixture.mkdir(parents=True)
        shutil.copy2(ROOT / "scripts/first-run.sh", fixture / "first-run.sh")
        (fixture / "setup.sh").write_text("#!/bin/bash\nexit 2\n")
        self.shim("omarchy", '''printf 'prompt\\n' >> "$TEST_CALLS"
shift 2
"$@" </dev/null
''')
        for _ in range(2):
            result = subprocess.run(["bash", str(fixture / "first-run.sh")],
                                    env=self.env, text=True, capture_output=True, timeout=20)
            self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls.read_text().splitlines(), ["prompt"])

    def test_native_source_launcher_caches_and_rebuilds_after_source_changes(self):
        fixture = self.base / "source"
        (fixture / "bin").mkdir(parents=True)
        (fixture / "src").mkdir()
        (fixture / "scripts").mkdir()
        self.ready_dependencies()
        for source in ("Cargo.toml", "Cargo.lock", "bin/powerkit", "src/main.rs", "scripts/setup.sh", "scripts/first-run.sh"):
            origin = ROOT / source
            if source == "bin/powerkit" and (ROOT / "bin/powerkit-source").exists():
                origin = ROOT / "bin/powerkit-source"
            shutil.copy2(origin, fixture / source)
        shutil.copy2(self.setup_script, fixture / "scripts/setup.sh")
        self.shim("cargo", '''printf 'build\\n' >> "$TEST_CALLS"
while (( $# )); do
  if [[ $1 == --target-dir ]]; then target=$2; break; fi
  shift
done
mkdir -p "$target/release"
printf '#!/bin/sh\\nprintf "%%s\\\\n" "$@"\\n' > "$target/release/powerkit"
chmod +x "$target/release/powerkit"
''')
        def launch():
            return subprocess.run([str(fixture / "bin/powerkit"), "action", '{"op":"test"}'],
                                  env=self.env, text=True, capture_output=True, timeout=20)
        for _ in range(2):
            result = launch()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), ["action", '{"op":"test"}'])
        self.assertEqual(self.calls.read_text().splitlines(), ["build"])
        with (fixture / "src/main.rs").open("a") as file:
            file.write("\n// changed source\n")
        self.assertEqual(launch().returncode, 0)
        self.assertEqual(self.calls.read_text().splitlines(), ["build", "build"])


if __name__ == "__main__":
    unittest.main()
