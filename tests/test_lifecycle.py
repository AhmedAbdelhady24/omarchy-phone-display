"""Run with: python3 -m unittest discover -s tests -v"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

PLUGIN = Path(__file__).resolve().parents[1]


class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="phone-display-test-")
        self.root = Path(self.tmp.name)
        bindir = self.root / "bin"
        bindir.mkdir()
        for command in ["adb", "hyprctl", "wayvnc", "ss"]:
            shutil.copy(PLUGIN / "tests/fake-command.py", bindir / command)
            (bindir / command).chmod(0o755)
        self.env = dict(os.environ, PATH=f"{bindir}:{os.environ['PATH']}",
                        XDG_RUNTIME_DIR=str(self.root), WAYLAND_DISPLAY="wayland-test",
                        HYPRLAND_INSTANCE_SIGNATURE="test", PHONE_TEST_ROOT=str(self.root))
        self.env.pop("ANDROID_SERIAL", None)

    def tearDown(self):
        self.run_script("stop")
        # Let the watcher observe deleted state before TemporaryDirectory cleanup.
        time.sleep(0.05)
        self.tmp.cleanup()

    def put(self, key, value):
        (self.root / key).write_text(json.dumps(value))

    def get(self, key, default=None):
        p = self.root / key
        return json.loads(p.read_text()) if p.exists() else default

    def run_script(self, *args):
        return subprocess.run(["bash", str(PLUGIN / "phone-display.sh"), *args],
                              env=self.env, text=True, capture_output=True, timeout=20)

    def calls(self):
        return [json.loads(line) for line in (self.root / "calls").read_text().splitlines()]

    def test_start_stop_and_idempotent_start(self):
        result = self.run_script("start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.run_script("status").stdout),
                         {"active": True, "adb_connected": True, "resolution": "1080x2400@60"})
        self.assertEqual(self.get("monitor")[0]["x"], 1948)  # -100 + 2560/1.25
        self.assertEqual(self.run_script("start").returncode, 0)
        self.assertEqual(sum(c[:2] == ["hyprctl", "output"] and c[2] == "create" for c in self.calls()), 1)
        call = next(c for c in self.calls() if c[0] == "wayvnc")
        self.assertIn("--max-fps", call)
        self.assertIn("--disable-resizing", call)
        self.assertEqual(call[-2:], ["127.0.0.1", "5900"])
        self.assertIn(["adb", "-s", "phone1", "shell", "am", "start", "-W", "-a",
                       "android.intent.action.VIEW", "-d", "vnc://127.0.0.1:5900", "com.gaurav.avnc"], self.calls())
        self.assertEqual(self.run_script("stop").returncode, 0)
        self.assertFalse(self.get("reverse"))
        self.assertEqual(self.get("monitor"), [])
        self.assertIn(["adb", "-s", "phone1", "shell", "am", "force-stop", "com.gaurav.avnc"], self.calls())
        self.assertEqual(self.run_script("stop").returncode, 0)

    def test_lua_and_rotated_left_placement(self):
        self.put("lua", True)
        self.put("physical", [{"name": "DP-1", "width": 2560, "height": 1440,
                               "scale": 1.25, "x": -100, "y": -20, "transform": 1}])
        result = self.run_script("start", "1080", "1920", "left-of", "1.5", "90")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.get("monitor")[0]["x"], -820)
        self.assertEqual(self.get("monitor")[0]["refreshRate"], 90)
        self.assertTrue(any(c[0:2] == ["hyprctl", "eval"] for c in self.calls()))

    def test_unauthorized_multiple_and_wireless_rejected(self):
        for devices in [[["p", "unauthorized", True]],
                        [["a", "device", True], ["b", "device", True]],
                        [["wireless", "device", False]]]:
            self.put("devices", devices)
            self.assertNotEqual(self.run_script("start").returncode, 0)
            self.assertFalse(self.get("reverse", False))
        self.assertEqual(json.loads(self.run_script("status").stdout)["adb_connected"], False)

    def test_port_and_reverse_collisions_are_not_modified(self):
        self.put("port-conflict", True)
        self.assertNotEqual(self.run_script("start").returncode, 0)
        self.put("port-conflict", False)
        self.put("reverse", True)
        self.assertNotEqual(self.run_script("start").returncode, 0)
        self.assertTrue(self.get("reverse"))
        self.assertFalse(any(c[:2] == ["hyprctl", "output"] for c in self.calls()))

    def test_existing_output_is_not_removed(self):
        self.put("monitor", [{"name": "PHONE-DISPLAY"}])
        self.assertNotEqual(self.run_script("start").returncode, 0)
        self.run_script("stop")
        self.assertEqual(self.get("monitor"), [{"name": "PHONE-DISPLAY"}])

    def test_mode_encoder_and_intent_failures_roll_back(self):
        for failure in ["fail-mode", "fail-wayvnc", "fail-intent"]:
            self.put(failure, True)
            result = self.run_script("start")
            self.assertNotEqual(result.returncode, 0, failure)
            self.assertEqual(self.get("monitor"), [], result.stderr)
            self.assertFalse(self.get("reverse"), result.stderr)
            self.assertFalse((self.root / "omarchy-phone-display-test/state.json").exists())
            self.put(failure, False)

    def test_argument_validation_precedes_side_effects(self):
        for args in [("1080", "2400", "right-of", "1;touch /tmp/bad"),
                     ("1080", "2400", "right-of", "1.7"),
                     ("1080", "2400", "right-of", "4.5"),
                     ("100", "2400"), ("1080", "2400", "right-of", "1", "240")]:
            self.assertNotEqual(self.run_script("start", *args).returncode, 0)
        self.assertFalse((self.root / "calls").exists())

    def test_unplug_watchdog_cleans_up(self):
        self.assertEqual(self.run_script("start").returncode, 0)
        self.put("devices", [])
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline and self.get("monitor"):
            time.sleep(0.2)
        self.assertEqual(self.get("monitor"), [])
        self.assertEqual(json.loads(self.run_script("status").stdout)["active"], False)

    def test_stale_pid_does_not_kill_unrelated_process(self):
        victim = subprocess.Popen(["sleep", "20"])
        try:
            runtime = self.root / "omarchy-phone-display-test"
            runtime.mkdir()
            (runtime / "state.json").write_text(json.dumps({"serial": "phone1", "pid": str(victim.pid),
                "born": "wrong-birth", "token": "stale", "resolution": "1080x2400@60",
                "reverse": False, "monitor": False, "app": False}))
            self.assertEqual(self.run_script("stop").returncode, 0)
            self.assertIsNone(victim.poll())
        finally:
            victim.terminate()
            victim.wait()

    def test_two_toggles_are_serialized(self):
        command = ["bash", str(PLUGIN / "phone-display.sh"), "toggle"]
        first = subprocess.Popen(command, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(0.05)
        second = subprocess.Popen(command, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(first.communicate(timeout=20)[1], b"")
        self.assertEqual(second.communicate(timeout=20)[1], b"")
        self.assertEqual((first.returncode, second.returncode), (0, 0))
        self.assertEqual(self.get("monitor"), [])

    def test_native_landscape_fills_phone_aspect_ratio(self):
        self.put("orientation", "landscape")
        result = self.run_script("start", "native", "native", "right-of", "1.5", "60", "auto", "true")
        self.assertEqual(result.returncode, 0, result.stderr)
        monitor = self.get("monitor")[0]
        self.assertEqual((monitor["width"], monitor["height"]), (2340, 1080))
        self.assertTrue(self.get("stay-awake"))

    def test_missing_avnc_is_reported_and_start_rejected(self):
        self.put("avnc-missing", True)
        setup = json.loads(self.run_script("inspect").stdout)
        self.assertTrue(setup["usb"])
        self.assertFalse(setup["avnc"])
        self.assertEqual(setup["nativeSize"], "1080x2340")
        result = self.run_script("start")
        self.assertIn("AVNC is not installed", result.stderr)
        self.assertFalse(self.get("reverse", False))

    def test_configure_moves_and_rotates_without_restarting_vnc(self):
        self.assertEqual(self.run_script("start").returncode, 0)
        pid = self.get("server-pid")
        result = self.run_script("configure", "1080", "2400", "-1600x-10", "1.5", "60", "landscape")
        self.assertEqual(result.returncode, 0, result.stderr)
        monitor = self.get("monitor")[0]
        self.assertEqual((monitor["width"], monitor["height"], monitor["x"], monitor["y"]), (2400,1080,-1600,-10))
        self.assertEqual(self.get("server-pid"), pid)
        self.assertNotEqual(self.run_script("configure", "1080", "2400", "right-of", "1.5", "120").returncode, 0)

    def test_follow_phone_changes_shape_on_rotation(self):
        self.assertEqual(self.run_script("start", "native", "native", "left-of", "1.5", "60", "auto").returncode, 0)
        self.put("orientation", "landscape")
        deadline = time.monotonic()+8
        while time.monotonic() < deadline and self.get("monitor")[0]["width"] != 2340:
            time.sleep(.2)
        monitor = self.get("monitor")[0]
        self.assertEqual((monitor["width"],monitor["height"],monitor["x"]), (2340,1080,-1660))

    def test_awake_explicit_off_and_persistent_on(self):
        self.assertEqual(self.run_script("awake", "on").returncode, 0)
        self.assertTrue(self.get("stay-awake"))
        self.run_script("stop")
        self.assertTrue(self.get("stay-awake"))
        self.assertEqual(self.run_script("awake", "off").returncode, 0)
        self.assertFalse(self.get("stay-awake"))


if __name__ == "__main__":
    unittest.main()
