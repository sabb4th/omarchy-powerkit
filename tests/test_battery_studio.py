"""Regression tests use synthetic sysfs and a simulated TLP; never touch hardware."""
import copy
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"scripts"))
import domain as d
import backend
import control
import setup as installer
import i18n

THINKPAD = """
+++ Battery Care
Plugin: thinkpad
Supported features: charge thresholds, recalibration
Parameter value ranges:
* START_CHARGE_THRESH_BAT0/1: 0(off)..96(default)..99
* STOP_CHARGE_THRESH_BAT0/1: 1..100(default)
"""
ASUS = """
Plugin: asus
Supported features: charge threshold
Parameter value range:
* STOP_CHARGE_THRESH_BAT0/1: 0(off)..100(default)
"""
LENOVO = """
Plugin: lenovo
Supported features: charge type
Parameter value range:
* STOP_CHARGE_THRESH_BAT0/1: 0(Standard)..1(Long_Life) -- charge type
"""


class FakeSys(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.sys = Path(self.tmp.name)
        self.p = self.sys/"class/power_supply/BAT0"
        self.p.mkdir(parents=True)
        self.write(type="Battery", present=1, status="Discharging", capacity=80,
                   energy_now=40_000_000, energy_full=50_000_000, energy_full_design=60_000_000,
                   power_now=10_000_000, voltage_now=12_000_000,
                   charge_control_start_threshold=75, charge_control_end_threshold=80)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, **values):
        for key, value in values.items():
            (self.p/key).write_text(str(value))

    def test_energy_units_power_and_runtime(self):
        b = d.battery_info(self.p)
        self.assertEqual(b["energy_wh"], 40)
        self.assertEqual(b["power_w"], 10)
        self.assertEqual(b["hours"], 4)
        self.assertAlmostEqual(b["health"], 100*50/60)

    def test_charge_only_battery(self):
        for name in ("energy_now", "energy_full", "energy_full_design", "power_now"):
            (self.p/name).unlink()
        self.write(charge_now=3_000_000, charge_full=4_000_000, charge_full_design=5_000_000,
                   current_now=1_000_000, voltage_min_design=11_000_000)
        b = d.battery_info(self.p)
        self.assertEqual(b["power_w"], 12)
        self.assertEqual(b["energy_wh"], 33)
        self.assertEqual(b["hours"], 3)
        self.assertEqual(b["health"], 80)
        self.assertTrue(b["derived_energy"])

    def test_fallback_power_from_current(self):
        (self.p/"power_now").unlink()
        self.write(current_now=-500_000)
        self.assertEqual(d.battery_info(self.p)["power_w"], 6)

    def test_missing_power_is_not_zero(self):
        (self.p/"power_now").unlink()
        b = d.battery_info(self.p)
        self.assertIsNone(b["power_w"])
        self.assertIsNone(b["hours"])
        self.assertIsNone(b["signed_power_w"])

    def test_charging_estimate_uses_stop_threshold(self):
        self.write(status="Charging", energy_now=30_000_000, capacity=60)
        b = d.battery_info(self.p)
        self.assertEqual(b["hours"], 1)
        self.assertEqual(b["signed_power_w"], -10)
        self.assertEqual(b["charge_target"], 80)

    def test_idle_source_remains_unknown(self):
        self.write(status="Not charging")
        sample = d.snapshot(self.sys)
        self.assertIsNone(sample["ac"])
        self.assertEqual(sample["aggregate"]["signed_power_w"], 0)

    def test_usb_c_supply_and_peripherals(self):
        charger = self.sys/"class/power_supply/ucsi-source"
        charger.mkdir()
        for key, value in {"type":"USB", "online":1}.items():
            (charger/key).write_text(str(value))
        device = self.sys/"class/power_supply/mouse"
        device.mkdir()
        for key, value in {"type":"Battery", "scope":"Device", "capacity":50}.items():
            (device/key).write_text(str(value))
        sample = d.snapshot(self.sys)
        self.assertTrue(sample["ac"])
        self.assertEqual(len(sample["batteries"]), 1)

    def test_zero_design_capacity_and_invalid_values(self):
        self.write(energy_full_design=0, temp="nan")
        b = d.battery_info(self.p)
        self.assertIsNone(b["health"])
        self.assertIsNone(b["temperature_c"])

    def test_weighted_multi_battery(self):
        a = d.battery_info(self.p)
        b = {**a, "id":"BAT1", "energy_wh":10, "full_wh":50,
             "design_wh":60, "percent":20, "signed_power_w":5}
        combined = d.aggregate([a, b])
        self.assertEqual(combined["percent"], 50)
        self.assertEqual(combined["power_w"], 15)
        self.assertAlmostEqual(combined["hours"], 50/15)

    def test_aggregate_does_not_fill_missing_sensors(self):
        a = d.battery_info(self.p)
        b = {**a, "id":"BAT1", "signed_power_w":None}
        self.assertIsNone(d.aggregate([a, b])["power_w"])

    def test_small_current_has_no_unrealistic_estimate(self):
        self.write(power_now=100_000)
        self.assertIsNone(d.battery_info(self.p)["hours"])


class Capabilities(unittest.TestCase):
    def test_thinkpad_defaults_and_dual_batteries(self):
        care = d.parse_care(THINKPAD)
        self.assertTrue(care["supported"])
        self.assertTrue(care["chargeonce"])
        self.assertEqual(care["parameters"]["0"]["start"]["default"], 96)
        self.assertEqual(d.limits_for(care, "BAT1", 2)["slot"], "1")

    def test_asus_has_no_start_threshold(self):
        limits = d.limits_for(d.parse_care(ASUS), "BATT")
        self.assertTrue(limits["supported"])
        self.assertFalse(limits["start_supported"])

    def test_lenovo_conservation_is_not_a_percentage(self):
        care = d.parse_care(LENOVO)
        self.assertTrue(care["fixed_conservation"])
        self.assertEqual(d.limits_for(care, "BAT1", 2)["slot"], "0")
        with self.assertRaises(ValueError):
            d.validate_value(80, care["parameters"]["0"]["stop"], "Fim")

    def test_discrete_range(self):
        limits = d.parse_range("80, 100(default)")
        self.assertEqual(limits["values"], [80, 100])
        with self.assertRaises(ValueError):
            d.validate_value(90, limits, "Fim")

    def test_unsupported_hardware_is_not_enabled_by_sysfs_alone(self):
        self.assertFalse(d.parse_care("Supported features: none available")["supported"])

    def test_status_legacy_and_current_tlp(self):
        self.assertEqual(d.parse_tlp_status("State = enabled\nMode = BAT (manual)")["profile"], "balanced")
        current = d.parse_tlp_status("tlp = enabled, last run: now\nTLP profile = power-saver/SAV\nPower source = battery")
        self.assertEqual(current["profile"], "power-saver")
        self.assertEqual(current["state"], "enabled")
        self.assertEqual(d.parse_tlp_status("tlp = disabled")["state"], "disabled")

    def test_config_output_and_versions(self):
        raw = '/etc/tlp.conf L0017: TLP_AUTO_SWITCH="1"\n/etc/tlp.d/99-test.conf L0002: STOP_CHARGE_THRESH_BAT0="80"'
        self.assertEqual(d.parse_config(raw)["STOP_CHARGE_THRESH_BAT0"], "80")
        self.assertGreater(d.version_tuple("TLP 1.10.2"), d.version_tuple("1.9.1"))


class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.history = backend.History(Path(self.tmp.name)/"history.sqlite3")
        self.now = time.time()

    def tearDown(self):
        self.history.close()
        self.tmp.cleanup()

    def sample(self, ts, power, status="Discharging", ac=False, health=88):
        b = {"id":"BAT0","percent":75,"signed_power_w":power,"health":health,"energy_wh":30,"status":status}
        return {"ts":ts,"batteries":[b],"aggregate":b,"ac":ac}

    def test_history_deduplication_and_discharge_average(self):
        self.history.record(self.sample(self.now-120, 8))
        self.history.record(self.sample(self.now-60, -20, "Charging", True))
        self.history.record(self.sample(self.now-60, -22, "Charging", True))
        result = self.history.query("BAT0", 1, now=self.now+1)
        self.assertEqual(result["samples"], 2)
        self.assertEqual(result["average_w"], 8)
        self.assertEqual(result["peak_w"], 8)
        self.assertEqual(self.history.db.execute("SELECT COUNT(*) FROM samples").fetchone()[0], 2)

    def test_retention_removes_old_data(self):
        self.history.record(self.sample(self.now-40*86400, 8))
        self.history.record(self.sample(self.now-60, 6))
        self.history.trim(30, now=self.now)
        self.assertEqual(self.history.db.execute("SELECT COUNT(*) FROM samples").fetchone()[0], 1)

    def test_history_null_measurements_and_sql_parameters(self):
        self.history.record(self.sample(self.now-60, None, health=None))
        result = self.history.query("BAT0", 1, now=self.now+1)
        self.assertIsNone(result["average_w"])
        self.assertIsNone(result["points"][0]["power"])
        self.assertEqual(self.history.query("BAT0' OR 1=1 --", 1)["samples"], 0)

    def test_csv_contains_units_sign_and_timezone(self):
        self.history.record(self.sample(self.now-60, 8))
        path = Path(self.tmp.name)/"export.csv"
        self.history.export(path, "BAT0", 24)
        raw = path.read_text(encoding="utf-8-sig")
        self.assertIn("fluxo_w_positivo_descarga", raw)
        self.assertIn("BAT0", raw)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_restart_does_not_invent_a_charger_event(self):
        self.history.record(self.sample(self.now-60, 8))
        count = self.history.db.execute("SELECT COUNT(*) FROM events").fetchone()[0]
        self.history.close()
        self.history = backend.History(Path(self.tmp.name)/"history.sqlite3")
        self.history.record(self.sample(self.now, 7))
        self.assertEqual(self.history.db.execute("SELECT COUNT(*) FROM events").fetchone()[0], count)

    def test_csv_export_can_use_english_headers(self):
        self.history.record(self.sample(self.now-60, 8))
        path = Path(self.tmp.name)/"english.csv"
        self.history.export(path, "BAT0", 24, language="en")
        header = path.read_text(encoding="utf-8-sig").splitlines()[0]
        self.assertIn("power_w_positive_discharge", header)
        self.assertIn("battery", header)


class PrivilegedControlTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.drop = Path(self.tmp.name)/"tlp.d/99-battery-studio.conf"
        self.orig = Path(self.tmp.name)/"state/original.json"
        self.calls = []
        self.patches = [
            patch.object(control, "DROPIN", self.drop),
            patch.object(control, "ORIGINAL", self.orig),
            patch.object(control, "battery_dirs", return_value=[]),
        ]
        for item in self.patches:
            item.start()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.tmp.cleanup()

    def checked(self, argv, timeout=12):
        self.calls.append(argv)
        if argv[-1] == "-c":
            return self.drop.read_text() if self.drop.exists() else ""
        return ""

    def test_only_allowlisted_config_is_written(self):
        with patch.object(control, "checked", side_effect=self.checked):
            control.persistent({"STOP_CHARGE_THRESH_BAT0":80}, lambda: None)
            self.assertEqual(d.parse_config(self.drop.read_text())["STOP_CHARGE_THRESH_BAT0"], "80")
            with self.assertRaises(ValueError):
                control.persistent({"PATH":"/tmp"}, lambda: None)

    def test_external_override_prevents_hardware_change(self):
        applied = []
        with patch.object(control, "checked", return_value='STOP_CHARGE_THRESH_BAT0="90"'):
            with self.assertRaisesRegex(ValueError, "precedência"):
                control.persistent({"STOP_CHARGE_THRESH_BAT0":80}, lambda: applied.append(True))
        self.assertFalse(applied)
        self.assertFalse(self.drop.exists())

    def test_hardware_failure_restores_config_and_original_state(self):
        self.drop.parent.mkdir()
        original = 'STOP_CHARGE_THRESH_BAT0="90"\n'
        self.drop.write_text(original)
        restored = []
        def fail():
            raise ValueError("Firmware rejeitou")
        with patch.object(control, "checked", side_effect=self.checked):
            with self.assertRaises(ValueError):
                control.persistent({"STOP_CHARGE_THRESH_BAT0":80}, fail, lambda: restored.append(True))
        self.assertEqual(self.drop.read_text(), original)
        self.assertEqual(restored, [True])

    def test_symlinks_and_injection_are_rejected(self):
        target = Path(self.tmp.name)/"unrelated"
        target.write_text("original")
        self.drop.parent.mkdir()
        self.drop.symlink_to(target)
        with self.assertRaises(ValueError):
            control.persistent({"TLP_AUTO_SWITCH":1}, lambda: None)
        self.assertEqual(target.read_text(), "original")
        self.drop.unlink()
        with self.assertRaises(ValueError):
            control.persistent({"TLP_AUTO_SWITCH":'1;touch /tmp/x'}, lambda: None)

    def test_unknown_operations_and_bad_arguments(self):
        for args in (["shell", "id"], ["threshold","BAT0","$(id)","80","1"], ["profile","--help"]):
            with patch.object(control, "require_ready", return_value={"state":"enabled"}), \
                 patch.object(control, "checked", return_value="TLP 1.10.2"):
                with self.assertRaises(ValueError):
                    control.dispatch(args)

    def test_cannot_control_when_another_manager_is_active(self):
        with patch.object(control, "installed"), patch.object(control, "conflict_services", return_value=["tuned.service"]):
            with self.assertRaisesRegex(ValueError, "tuned"):
                control.require_ready()

    def test_tlp_disabled_is_detected_in_new_status_format(self):
        with patch.object(control, "installed"), patch.object(control, "conflict_services", return_value=[]), \
             patch.object(control, "checked", return_value="tlp = disabled"):
            with self.assertRaisesRegex(ValueError, "TLP_ENABLE"):
                control.require_ready()

    def test_secondary_battery_cannot_be_an_arbitrary_path(self):
        with patch.object(control, "battery_dirs", return_value=[]):
            with self.assertRaises(ValueError):
                control.care_for("../../etc/passwd")


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.source = root/"source"
        self.source.mkdir()
        (self.source/"new.txt").write_text("new")
        self.plugins = root/"plugins"
        self.plugins.mkdir()
        self.target = self.plugins/"local.battery-studio"
        self.target.mkdir()
        (self.target/"original.txt").write_text("original")
        self.state = root/"state"
        self.state.mkdir()
        (self.state/"history.keep").write_text("history")
        self.patches = [
            patch.object(installer, "ROOT", self.source),
            patch.object(installer, "PLUGINS", self.plugins),
            patch.object(installer, "TARGET", self.target),
            patch.object(installer, "STATE", self.state),
            patch.object(installer, "validate"),
            patch.object(installer, "need_quattro"),
            patch.object(installer.os, "geteuid", return_value=1000),
        ]
        for item in self.patches:
            item.start()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.tmp.cleanup()

    def test_copy_failure_preserves_existing_plugin(self):
        with patch.object(installer.shutil, "copytree", side_effect=OSError("disk full")), \
             patch.object(installer, "invoke"):
            with self.assertRaises(OSError):
                installer.install(False)
        self.assertEqual((self.target/"original.txt").read_text(), "original")
        self.assertEqual((self.state/"history.keep").read_text(), "history")

    def test_enable_failure_restores_previous_plugin(self):
        def invoke(argv, **kwargs):
            if argv[:3] == ["omarchy", "plugin", "enable"]:
                raise RuntimeError("shell unavailable")
        with patch.object(installer, "invoke", side_effect=invoke):
            with self.assertRaises(RuntimeError):
                installer.install(False)
        self.assertEqual((self.target/"original.txt").read_text(), "original")
        self.assertFalse((self.target/"new.txt").exists())

    def test_cache_never_overrides_a_new_live_profile(self):
        version = "TLP 1.10.2"
        fingerprint = {"kernel":"test", "tlp":version, "batteries":[]}
        (self.state/"inspection.json").write_text(json.dumps({
            "ts":0, "fingerprint":fingerprint, "care":d.parse_care(THINKPAD),
            "tlp":{"profile":"performance", "config":{"TLP_AUTO_SWITCH":"2"}},
        }))
        current = {"tlp":{"version":version,"profile":"balanced","config":{"TLP_AUTO_SWITCH":"1"}},
                   "care":d.parse_care("")}
        with patch.object(backend, "state_dir", return_value=self.state), \
             patch.object(backend, "diagnostics", return_value=current), \
             patch.object(backend, "machine_fingerprint", return_value=fingerprint):
            result = backend.cached_diagnostics()
        self.assertTrue(result["care"]["supported"])
        self.assertEqual(result["tlp"]["profile"], "balanced")
        self.assertEqual(result["tlp"]["config"]["TLP_AUTO_SWITCH"], "1")


class PreferenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.state = Path(self.tmp.name)
        self.context = patch.object(backend, "state_dir", return_value=self.state)
        self.context.start()

    def tearDown(self):
        self.context.stop()
        self.tmp.cleanup()

    def test_old_preferences_migrate_without_losing_retention(self):
        (self.state/"preferences.json").write_text('{"retention_days":90}')
        self.assertEqual(backend.preferences(), {"retention_days":90,"language":"auto","display_mode":"full"})

    def test_language_mode_and_retention_survive_separate_updates(self):
        backend.save_preferences({"language":"en"})
        backend.save_preferences({"display_mode":"icon"})
        backend.save_preferences({"retention_days":7})
        self.assertEqual(backend.preferences(), {"language":"en","display_mode":"icon","retention_days":7})
        self.assertEqual((self.state/"preferences.json").stat().st_mode & 0o777, 0o600)

    def test_all_bar_modes_are_valid(self):
        for mode in backend.DISPLAY_MODES:
            backend.save_preferences({"display_mode":mode})
            self.assertEqual(backend.preferences()["display_mode"], mode)

    def test_invalid_preferences_do_not_overwrite_saved_state(self):
        backend.save_preferences({"language":"pt"})
        before = (self.state/"preferences.json").read_text()
        for invalid in ({"language":"unknown"}, {"display_mode":"shell"}, {"retention_days":0}, {"command":"id"}):
            with self.assertRaises(ValueError):
                backend.save_preferences(invalid)
        self.assertEqual((self.state/"preferences.json").read_text(), before)

    def test_corrupt_preference_file_uses_safe_defaults(self):
        for value in ("invalid-json", "[]", '{"display_mode":"wrong","language":1}'):
            (self.state/"preferences.json").write_text(value)
            self.assertEqual(backend.preferences(), backend.PREFERENCE_DEFAULTS)

    def test_automatic_language_respects_locale_priority(self):
        with patch.dict(os.environ, {"LANG":"en_US.UTF-8","LC_MESSAGES":"pt_BR.UTF-8","LC_ALL":""}):
            self.assertEqual(backend.effective_language({"language":"auto"}), "pt")
            self.assertEqual(backend.effective_language({"language":"en"}), "en")
        with patch.dict(os.environ, {"LANG":"pt_BR.UTF-8","LC_MESSAGES":"pt_BR.UTF-8","LC_ALL":"en_US.UTF-8"}):
            self.assertEqual(backend.effective_language({"language":"auto"}), "en")

    def test_operation_messages_are_bilingual(self):
        message = "Proteção de carga aplicada e salva para reiniciar."
        self.assertEqual(i18n.translate_message(message, "pt"), message)
        self.assertEqual(i18n.translate_message(message, "en"), "Charge protection applied and saved for reboot.")
        self.assertEqual(i18n.translate_message("Perfil aplicado: balanced.", "en"), "Profile applied: balanced.")


if __name__ == "__main__":
    unittest.main()
