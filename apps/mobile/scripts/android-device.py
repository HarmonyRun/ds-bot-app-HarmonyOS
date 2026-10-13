#!/usr/bin/env python3
"""Local Android handoff; Python standard library and official adb only."""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

PACKAGE = "app.dsbot.mobile"


def endpoint(value):
    match = re.fullmatch(r"([A-Za-z0-9_.-]+|\[[0-9A-Fa-f:]+\]):([0-9]{1,5})", value)
    if not match or not 1 <= int(match[2]) <= 65535:
        raise argparse.ArgumentTypeError("Use the current IP:port shown on the phone.")
    return value


def serial(value):
    if value.startswith("-") or not re.fullmatch(r"[A-Za-z0-9_.:\[\]-]+", value):
        raise argparse.ArgumentTypeError("Invalid device serial or connection address.")
    return value


class DeviceError(Exception):
    pass


def adb(args, command, interactive=False):
    executable = shutil.which(args.adb)
    if not executable:
        raise DeviceError("adb not found. Install official platform-tools or pass --adb PATH.")
    try:
        result = subprocess.run(
            [executable, *command], check=False, text=True,
            stdout=None if interactive else subprocess.PIPE,
            stderr=None if interactive else subprocess.PIPE,
            timeout=180 if interactive else 90,
        )
    except subprocess.TimeoutExpired:
        raise DeviceError("ADB timed out. Check Wi-Fi, the current port and device authorization.") from None
    except OSError:
        raise DeviceError("Could not start adb. Check the platform-tools installation.") from None
    if result.returncode:
        # Do not forward unknown tool/device output into diagnostic reports.
        if "INSTALL_FAILED_UPDATE_INCOMPATIBLE" in (result.stdout or "") + (result.stderr or ""):
            raise DeviceError("Signing certificate differs from the installed app. Keep the old signing key; do not clear or uninstall app data automatically.")
        raise DeviceError("ADB failed. Check the selected device, authorization and connection.")
    return result.stdout or ""


def selected(args, command):
    return adb(args, ["-s", args.serial, *command])


def ready(args):
    if selected(args, ["get-state"]).strip() != "device":
        raise DeviceError("The selected device is not authorized/connected.")


def checksum(path, explicit):
    expected = explicit
    manifest = path.parent / "SHA256SUMS"
    if not expected and manifest.is_file():
        for line in manifest.read_text(encoding="utf-8").splitlines():
            match = re.fullmatch(r"([0-9a-fA-F]{64})\s+\*?(.+)", line)
            if match and match[2] == path.name:
                expected = match[1]
                break
    if not expected:
        raise DeviceError("Provide --sha256 HASH or keep SHA256SUMS beside the APK.")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", expected):
        raise DeviceError("Invalid SHA-256 value.")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected.lower():
        raise DeviceError("APK checksum mismatch. Download the APK and matching checksum again.")


def metadata(args):
    info = {"package": PACKAGE}
    for field, prop, pattern in [
        ("android_api", "ro.build.version.sdk", r"[0-9]{1,3}"),
        ("abi", "ro.product.cpu.abi", r"[A-Za-z0-9_-]{1,40}"),
    ]:
        value = selected(args, ["shell", "getprop", prop]).strip()
        info[field] = value if re.fullmatch(pattern, value) else "unknown"
    dump = selected(args, ["shell", "dumpsys", "package", PACKAGE])
    version = re.search(r"\bversionName=([A-Za-z0-9_.+-]{1,80})(?:\s|$)", dump)
    info["installed"] = bool(version)
    info["version"] = version[1] if version else None
    services = selected(args, ["shell", "dumpsys", "activity", "services", PACKAGE])
    info["background_service_present"] = bool(re.search(
        r"ServiceRecord\{[^\n]*app\.dsbot\.mobile/app\.dsbot\.notifications\.BackgroundNotificationService\b", services
    ))
    return info


def crash_summary(raw):
    # Keep exception types/stack frames, discard arbitrary messages and payloads.
    output = []
    for line in raw.splitlines():
        match = re.search(r"\bE\s+AndroidRuntime\s*:\s*(.*)$", line)
        if not match:
            continue
        payload = match[1].strip()
        if payload.startswith("FATAL EXCEPTION:"):
            output.append("FATAL EXCEPTION (thread name omitted)")
            continue
        exception = re.match(r"(?:Caused by: |Suppressed: )?([A-Za-z_$][A-Za-z0-9_.$]*(?:Exception|Error))(?::|$)", payload)
        if exception:
            output.append(exception[1])
        elif re.fullmatch(r"at [A-Za-z_$][A-Za-z0-9_.$<>]*\((?:[A-Za-z0-9_.$-]+(?::[0-9]+)?|Native Method|Unknown Source)\)", payload):
            output.append(payload)
        if len(output) >= 120:
            break
    return output


def report(value, path):
    content = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    if path:
        with Path(path).open("x", encoding="utf-8") as stream:
            stream.write(content)
        print("Report saved. Review before sharing; existing reports are never overwritten.")
    else:
        print(content, end="")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb", help="Official adb path (or add platform-tools to PATH)")
    commands = parser.add_subparsers(dest="command", required=True)
    pair = commands.add_parser("pair", help="Enter the fresh pairing code interactively on this computer")
    pair.add_argument("address", type=endpoint)
    connect = commands.add_parser("connect", help="Use the main Wireless debugging page connection port")
    connect.add_argument("address", type=endpoint)
    install = commands.add_parser("install", help="Verify checksum, then update this device without clearing app data")
    install.add_argument("--serial", required=True, type=serial)
    install.add_argument("--apk", required=True, type=Path)
    install.add_argument("--sha256")
    install.add_argument("--launch", action="store_true")
    for name in ("status", "crash"):
        command = commands.add_parser(name, help="Metadata only" if name == "status" else "Whitelisted Java crash types/frames only; no raw log export")
        command.add_argument("--serial", required=True, type=serial)
        command.add_argument("--output", help="New JSON report path; never overwritten")
    args = parser.parse_args()
    try:
        if args.command == "pair":
            print("Enter the fresh code at adb's local prompt. Do not send it to chat or put it in a command.", flush=True)
            adb(args, ["pair", args.address], interactive=True)
            print("Pairing command completed. Next use connect with the separate connection port.")
        elif args.command == "connect":
            result = adb(args, ["connect", args.address])
            if not re.search(r"(?:^|\n)(?:already )?connected to ", result):
                raise DeviceError("Connection failed. Use the main Wireless debugging page IP:port, not the pairing port.")
            args.serial = args.address
            ready(args)
            print("Connected. Use this connection address as --serial for install/status/crash.")
        else:
            ready(args)
            if args.command == "install":
                if not args.apk.is_file():
                    raise DeviceError("APK file not found.")
                checksum(args.apk, args.sha256)
                result = selected(args, ["install", "-r", str(args.apk.resolve())])
                if not re.search(r"(?:^|\n)Success(?:\r?\n|$)", result):
                    raise DeviceError("Install did not report success. Check ABI, storage and signing certificate.")
                if args.launch:
                    result = selected(args, ["shell", "am", "start", "-n", PACKAGE + "/.MainActivity"])
                    if re.search(r"(?:Error|Exception)", result):
                        raise DeviceError("Installed, but launch failed. Open DS Bot on the phone manually.")
                print("Installed" + (" and launch requested." if args.launch else "."))
            else:
                value = metadata(args)
                if args.command == "crash":
                    # A crashed process has no live PID; filter by fixed package marker instead.
                    raw = selected(args, ["logcat", "-d", "-t", "400", "-v", "threadtime", "AndroidRuntime:E", "*:S"])
                    blocks = re.split(r"(?=^.*\bE\s+AndroidRuntime\s*:\s*FATAL EXCEPTION:)", raw, flags=re.MULTILINE)
                    frames = []
                    for block in blocks:
                        process = re.search(r"\bProcess:\s*app\.dsbot\.mobile,\s*PID:\s*([0-9]+)", block)
                        if process:
                            own_lines = []
                            for line in block.splitlines():
                                prefix = re.match(r"\d\d-\d\d\s+\S+\s+([0-9]+)\s+[0-9]+\s+E\s+AndroidRuntime\s*:", line)
                                if prefix and prefix[1] == process[1]:
                                    own_lines.append(line)
                            frames.extend(crash_summary("\n".join(own_lines)))
                    value["java_crash_frames"] = frames[-120:]
                    value["scope"] = "Recent Java crash summary only; native/JS failures and rotated logs may be absent. Messages are omitted."
                report(value, args.output)
    except (DeviceError, OSError, UnicodeError) as error:
        # OSError filenames may be local paths, but never include raw app/ADB logs.
        print("Error: " + (str(error) if isinstance(error, DeviceError) else "Cannot read/write the selected local file."), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
