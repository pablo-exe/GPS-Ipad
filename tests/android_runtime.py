"""Isolated API-35 emulator test. Never run against a personal/production device."""
from pathlib import Path
import json
import re
import socket
import subprocess
import time
import xml.etree.ElementTree as ET

PACKAGE = "es.pablo.gpsbridge"
OUT = Path("artifacts/android-runtime")
OUT.mkdir(parents=True, exist_ok=True)


def adb(*args, binary=False):
    return subprocess.check_output(["adb", *args], timeout=30, text=not binary)


def hierarchy():
    adb("shell", "uiautomator", "dump", "/sdcard/gps-ui.xml")
    return ET.fromstring(adb("shell", "cat", "/sdcard/gps-ui.xml"))


def screenshot(name):
    (OUT / name).write_bytes(adb("exec-out", "screencap", "-p", binary=True))


assert "emulator-" in adb("get-serialno"), "Refusing to operate a physical device"
adb("install", "-r", "artifacts/runtime-apk/app-debug.apk")
for permission in ["ACCESS_COARSE_LOCATION", "ACCESS_FINE_LOCATION", "POST_NOTIFICATIONS"]:
    adb("shell", "pm", "grant", PACKAGE, "android.permission." + permission)
adb("shell", "dumpsys", "deviceidle", "whitelist", "+" + PACKAGE)
adb("logcat", "-c")
client = None
samples = []
try:
    adb("shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
    root = hierarchy()
    ET.ElementTree(root).write(OUT / "sender-initial.xml", encoding="utf-8")
    button = next(n for n in root.iter("node") if n.get("text", "").casefold() == "iniciar gps en segundo plano")
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", button.attrib["bounds"]))
    adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
    token = None
    for _ in range(12):
        root = hierarchy()
        text = " ".join(n.get("text", "") for n in root.iter("node"))
        match = re.search(r"Código de sesión: (\d{6})", text)
        if match:
            token = match.group(1)
            break
        time.sleep(0.5)
    assert token, "Foreground service did not start from the app UI"
    screenshot("sender-active.png")
    adb("forward", "tcp:18865", "tcp:8765")
    client = socket.create_connection(("127.0.0.1", 18865), timeout=5)
    stream = client.makefile("rwb", buffering=0)
    stream.write((json.dumps({"v": 2, "token": token}, separators=(",", ":")) + "\n").encode())
    assert json.loads(stream.readline())["type"] == "hello"

    def sample(request):
        result = adb("emu", "geo", "fix", "-3.7038", "40.4168")
        assert "OK" in result, result
        time.sleep(1)
        stream.write((json.dumps({"v": 2, "request_id": request}, separators=(",", ":")) + "\n").encode())
        frame = json.loads(stream.readline())
        assert frame["request_id"] == request
        samples.append(frame)
        return frame

    # Allow the virtual GNSS HAL to deliver the new test point before entering Doze.
    acquired = False
    for request in range(1, 21):
        frame = sample(request)
        if frame["type"] == "fix" and abs(frame["lat"] - 40.4168) < 0.001 and abs(frame["lon"] + 3.7038) < 0.001:
            acquired = True
            break
    assert acquired, f"Emulator GNSS did not acquire the test point: {samples[-3:]}"
    adb("shell", "input", "keyevent", "223")  # KEYCODE_SLEEP: Activity.onStop must not end GPS.
    adb("shell", "dumpsys", "battery", "unplug")
    adb("shell", "dumpsys", "deviceidle", "force-idle")
    fixes = 0
    last_seq = 0
    for request in range(100, 160):
        frame = sample(request)
        if frame["type"] == "fix":
            assert abs(frame["lat"] - 40.4168) < 0.001
            assert 0 <= frame["age_ms"] < 2500
            assert frame["seq"] >= last_seq
            last_seq = frame["seq"]
            fixes += 1
    power = adb("shell", "dumpsys", "power")
    (OUT / "power-screen-off.txt").write_text(power)
    assert "mWakefulness=Asleep" in power, "Screen did not remain off"
    services = adb("shell", "dumpsys", "activity", "services", PACKAGE)
    (OUT / "service-screen-off.txt").write_text(services)
    assert "isForeground=true" in services, "Location foreground service stopped"
    assert fixes >= 30, f"GNSS continuity failed: {fixes}/60 fresh samples"
    adb("shell", "dumpsys", "deviceidle", "unforce")
    adb("shell", "dumpsys", "battery", "reset")
    adb("shell", "input", "keyevent", "224")
    adb("shell", "wm", "dismiss-keyguard")
    adb("shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
    root = hierarchy()
    button = next(n for n in root.iter("node") if n.get("text", "").casefold() == "detener gps")
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", button.attrib["bounds"]))
    adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
    assert stream.readline() == b"", "Stopping service did not close GPS socket"
    stopped_power = adb("shell", "dumpsys", "power")
    (OUT / "power-after-stop.txt").write_text(stopped_power)
    assert not re.search(r"^\s+PARTIAL_WAKE_LOCK.*'GPSBridge:Navigation'", stopped_power, re.MULTILINE), "GPS CPU lock leaked after stop"
    logs = adb("logcat", "-d")
    (OUT / "logcat.txt").write_text(logs)
    assert "FATAL EXCEPTION" not in logs
    print(f"PASS: UI-started foreground location service, locked screen, forced Doze with exemption, {fixes}/60 GNSS samples and explicit service/socket stop")
finally:
    if client:
        client.close()
    (OUT / "synthetic-samples.json").write_text(json.dumps(samples))
    # Cleanup only this disposable emulator package; GpsService stays non-exported.
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "dumpsys", "deviceidle", "unforce")
    adb("shell", "dumpsys", "battery", "reset")
    adb("shell", "input", "keyevent", "224")
    adb("shell", "wm", "dismiss-keyguard")
    adb("shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
    screenshot("sender-after-stop.png")
    (OUT / "logcat.txt").write_text(adb("logcat", "-d"))
