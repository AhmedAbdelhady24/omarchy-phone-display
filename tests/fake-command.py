#!/usr/bin/env python3
"""Hardware boundary for lifecycle tests. Never invokes the real desktop or ADB."""
import json
import os
from pathlib import Path
import re
import signal
import socket
import sys
import time
from urllib.parse import parse_qs, urlsplit

root = Path(os.environ["PHONE_TEST_ROOT"])
name, args = Path(sys.argv[0]).name, sys.argv[1:]
with (root / "calls").open("a") as log:
    log.write(json.dumps([name, *args]) + "\n")


def read(key, fallback=None):
    p = root / key
    return json.loads(p.read_text()) if p.exists() else fallback


def write(key, value):
    p = root / key
    tmp = root / (key + ".tmp")
    tmp.write_text(json.dumps(value))
    tmp.replace(p)


if name == "adb":
    if args[:2] == ["devices", "-l"]:
        print("List of devices attached")
        for serial, state, usb in read("devices", [["phone1", "device", True]]):
            print(f"{serial}\t{state} {'usb:1-2' if usb else ''} product:test")
    else:
        assert args[0] == "-s", args
        serial, args = args[1], args[2:]
        if args == ["get-state"]:
            if any(d[0] == serial and d[1] == "device" for d in read("devices", [["phone1", "device", True]])):
                print("device")
            else:
                sys.exit(1)
        elif args[:2] == ["shell", "pm"]:
            if not read("avnc-missing", False):
                print("package:/data/app/com.gaurav.avnc/base.apk")
        elif args == ["shell", "wm", "size"]:
            print("Physical size: 1080x2340")
        elif args[:3] == ["shell", "settings", "get"]:
            print("1")
        elif args[:4] == ["shell", "svc", "power", "stayon"]:
            write("stay-awake", args[4] == "true")
        elif args[0] == "shell" and "dumpsys input" in args[1]:
            landscape = read("orientation", "portrait") == "landscape"
            print(f'Viewport INTERNAL: displayId=0, orientation={1 if landscape else 0}, logicalFrame=[0, 0, {2340 if landscape else 1080}, {1080 if landscape else 2340}]')
        elif args[:2] == ["reverse", "--list"]:
            if read("reverse", False):
                print("UsbFfs tcp:5900 tcp:5900")
        elif args[:2] == ["reverse", "--no-rebind"]:
            if read("reverse", False):
                sys.exit(1)
            write("reverse", True)
        elif args[:2] == ["reverse", "--remove"]:
            write("reverse", False)
        elif args == ["shell", "sh"]:
            script = sys.stdin.read()
            uri = re.search(r'-d "([^"]+)"', script).group(1)
            query = parse_qs(urlsplit(uri).query)
            config = (root / "omarchy-phone-display-test/wayvnc.conf").read_text()
            password = next(line.removeprefix("password=") for line in config.splitlines() if line.startswith("password="))
            assert query["VncPassword"] == [password]
            assert query["VncUsername"] == ["phone-display"]
            assert query["SecurityType"] == ["19"]
            assert query["ChannelType"] == ["1"]
            assert query["SaveConnection"] == ["false"]
            write("authenticated-intent", True)
            if read("fail-intent", False):
                sys.exit(1)
elif name == "hyprctl":
    if args == ["-j", "monitors", "all"]:
        physical = read("physical", [{"name": "DP-1", "width": 2560, "height": 1440,
                                      "scale": 1.25, "x": -100, "y": 40, "transform": 0}])
        print(json.dumps(physical + read("monitor", [])))
    elif args[:3] == ["output", "create", "headless"]:
        write("monitor", [{"name": args[3], "width": 1920, "height": 1080,
                           "refreshRate": 60, "scale": 1, "x": 0, "y": 0, "transform": 0}])
        print("ok")
    elif args[:2] == ["output", "remove"]:
        write("monitor", [])
        print("ok")
    elif args[:2] == ["keyword", "monitor"] or args[0] == "eval":
        if read("fail-mode", False):
            print("invalid mode")
            sys.exit(0)  # Real hyprctl can return zero on a compositor error.
        if args[0] == "keyword" and read("lua", False):
            print("keyword can't work with non-legacy parsers. Use eval.")
            sys.exit(0)
        if args[0] == "eval":
            match = re.search(r'output="([^"]+)",mode="([^"]+)",position="([^"]+)",scale=([0-9.]+)', args[1])
            output, mode, pos, scale = match.groups()
        else:
            output, mode, pos, scale = args[2].split(",")
        width, height, hz = re.split("[x@]", mode)
        x, y = pos.split("x")
        write("monitor", [{"name": output, "width": int(width), "height": int(height),
                           "refreshRate": int(hz), "scale": float(scale), "x": int(x), "y": int(y), "transform": 0}])
        print("ok")
elif name == "wayvnc":
    if read("fail-wayvnc", False):
        print("Screencopy protocol unavailable", file=sys.stderr)
        sys.exit(1)
    control = args[args.index("--socket") + 1]
    sock = socket.socket(socket.AF_UNIX)
    sock.bind(control)
    write("server-pid", os.getpid())
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        while True:
            time.sleep(0.1)
    finally:
        (root / "server-pid").unlink(missing_ok=True)
        sock.close()
elif name == "ss":
    if read("port-conflict", False):
        print('LISTEN 0 16 127.0.0.1:5900 0.0.0.0:* users:(("other",pid=1,fd=3))')
    elif (pid := read("server-pid")):
        print(f'LISTEN 0 16 127.0.0.1:5900 0.0.0.0:* users:(("wayvnc",pid={pid},fd=3))')
else:
    raise AssertionError(name)
