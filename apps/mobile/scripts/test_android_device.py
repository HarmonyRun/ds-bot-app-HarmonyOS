"""Command safety/diagnostic contracts with synthetic ADB; no device needed."""

import contextlib
import hashlib
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("android_device", Path(__file__).with_name("android-device.py"))
device = importlib.util.module_from_spec(spec)
spec.loader.exec_module(device)
SERIAL = "192.168.1.20:37002"


class LocalHandoff(unittest.TestCase):
    def invoke(self, arguments, respond):
        calls = []

        def run(command, **options):
            calls.append((command, options))
            return respond(command, options)

        out, err = io.StringIO(), io.StringIO()
        with patch.object(device.sys, "argv", ["android-device.py", *arguments]), \
                patch.object(device.shutil, "which", return_value="/mock/adb"), \
                patch.object(device.subprocess, "run", side_effect=run), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            result = device.main()
        return result, out.getvalue(), err.getvalue(), calls

    @staticmethod
    def response(command, _options):
        if command[-1] == "get-state":
            value = "device\n"
        elif "install" in command:
            value = "Performing Streamed Install\nSuccess\n"
        elif "start" in command:
            value = "Starting: Intent { cmp=app.dsbot.mobile/.MainActivity }\n"
        elif "getprop" in command:
            value = "36\n" if command[-1] == "ro.build.version.sdk" else "arm64-v8a\n"
        elif "package" in command:
            value = "versionName=0.1.0\nprivate synthetic content must not be exported"
        elif "services" in command:
            value = "ServiceRecord{123 u0 app.dsbot.mobile/app.dsbot.notifications.BackgroundNotificationService}\nprivate synthetic content must not be exported"
        else:
            value = ""
        return subprocess.CompletedProcess(command, 0, value, "")

    def test_pair_keeps_code_off_arguments_and_inherits_local_terminal(self):
        result, _, _, calls = self.invoke(["pair", "192.168.1.20:37001"], self.response)
        self.assertEqual(result, 0)
        self.assertEqual(calls[0][0], ["/mock/adb", "pair", "192.168.1.20:37001"])
        self.assertIsNone(calls[0][1]["stdout"])
        self.assertIsNone(calls[0][1]["stderr"])

    def test_connect_rejects_exit_zero_failure_text(self):
        result, _, _, calls = self.invoke(["connect", SERIAL], lambda c, _: subprocess.CompletedProcess(c, 0, "failed to connect", ""))
        self.assertEqual(result, 1)
        self.assertEqual(len(calls), 1)

    def test_connect_verifies_exact_device(self):
        def respond(command, options):
            if "connect" in command:
                return subprocess.CompletedProcess(command, 0, "connected to " + SERIAL, "")
            return self.response(command, options)
        result, _, _, calls = self.invoke(["connect", SERIAL], respond)
        self.assertEqual(result, 0)
        self.assertEqual(calls[-1][0], ["/mock/adb", "-s", SERIAL, "get-state"])

    def test_wrong_checksum_never_installs(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "test.apk"
            apk.write_bytes(b"synthetic APK")
            result, _, _, calls = self.invoke(["install", "--serial", SERIAL, "--apk", str(apk), "--sha256", "0" * 64], self.response)
        self.assertEqual(result, 1)
        self.assertFalse(any("install" in command for command, _ in calls))

    def test_install_updates_and_launches_only_selected_device(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "test.apk"
            apk.write_bytes(b"synthetic APK")
            (apk.parent / "SHA256SUMS").write_text(hashlib.sha256(apk.read_bytes()).hexdigest() + "  test.apk\n", encoding="utf-8")
            result, _, _, calls = self.invoke(["install", "--serial", SERIAL, "--apk", str(apk), "--launch"], self.response)
            self.assertEqual(calls[1][0], ["/mock/adb", "-s", SERIAL, "install", "-r", str(apk.resolve())])
        self.assertEqual(result, 0)
        self.assertTrue(all(command[1:3] == ["-s", SERIAL] for command, _ in calls))
        self.assertFalse(any("uninstall" in command or "clear" in command for command, _ in calls))

    def test_signature_conflict_stops_without_clear_or_raw_error_export(self):
        def respond(command, options):
            if "install" in command:
                return subprocess.CompletedProcess(command, 1, "", "INSTALL_FAILED_UPDATE_INCOMPATIBLE private synthetic payload")
            return self.response(command, options)
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "test.apk"
            apk.write_bytes(b"synthetic APK")
            result, out, err, calls = self.invoke(["install", "--serial", SERIAL, "--apk", str(apk), "--sha256", hashlib.sha256(apk.read_bytes()).hexdigest(), "--launch"], respond)
        self.assertEqual(result, 1)
        self.assertNotIn("private synthetic payload", out + err)
        self.assertFalse(any("uninstall" in command or "clear" in command or "start" in command for command, _ in calls))

    def test_crash_excludes_messages_foreign_process_and_raw_metadata(self):
        lines = [
            "10-11 15:00:00.000 100 101 E AndroidRuntime: FATAL EXCEPTION: main",
            "10-11 15:00:00.001 100 101 E AndroidRuntime: Process: app.dsbot.mobile, PID: 100",
            "10-11 15:00:00.002 100 101 E AndroidRuntime: java.lang.IllegalStateException: private synthetic payload",
            "10-11 15:00:00.003 100 101 E AndroidRuntime: at app.dsbot.notifications.Work.run(Work.kt:12)",
            "10-11 15:00:00.004 222 223 E AndroidRuntime: at other.app.Secret.run(Secret.kt:1)",
            "10-11 15:00:00.005 222 223 E AndroidRuntime: FATAL EXCEPTION: main",
            "10-11 15:00:00.006 222 223 E AndroidRuntime: Process: other.app, PID: 222",
            "10-11 15:00:00.007 222 223 E AndroidRuntime: java.lang.RuntimeException: unrelated private payload",
        ]

        def respond(command, options):
            if "logcat" in command:
                return subprocess.CompletedProcess(command, 0, "\n".join(lines), "")
            return self.response(command, options)

        result, out, _, calls = self.invoke(["crash", "--serial", SERIAL], respond)
        report = json.loads(out)
        self.assertEqual(result, 0)
        self.assertTrue(report["background_service_present"])
        self.assertEqual(report["java_crash_frames"], ["FATAL EXCEPTION (thread name omitted)", "java.lang.IllegalStateException", "at app.dsbot.notifications.Work.run(Work.kt:12)"])
        self.assertNotIn("payload", out)
        self.assertNotIn("other.app", out)
        self.assertNotIn("private synthetic", out)
        self.assertTrue(all(command[1:3] == ["-s", SERIAL] for command, _ in calls))

    def test_report_never_overwrites_existing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "report.json"
            report.write_text("keep this", encoding="utf-8")
            result, _, _, _ = self.invoke(["status", "--serial", SERIAL, "--output", str(report)], self.response)
            self.assertEqual(result, 1)
            self.assertEqual(report.read_text(encoding="utf-8"), "keep this")


if __name__ == "__main__":
    unittest.main()
