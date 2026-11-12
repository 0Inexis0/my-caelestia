#!/usr/bin/env python3
"""Apply display changes serially and save only compositor-confirmed settings."""
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import time


def hypr(*args):
    result = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=10)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout


def monitors():
    return json.loads(hypr("monitors", "all", "-j"))


def internal(m):
    return m["name"].startswith(("eDP", "LVDS", "DSI"))


def external(m):
    return m["name"].startswith(("HDMI-", "DP-", "DVI-", "VGA-", "USB-"))


def apply(m, mode=None, scale=None, enabled=True, mirror=None):
    name = m["name"]
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", name):
        raise ValueError("Invalid output name")
    directory = Path.home() / ".config/hypr"
    if not enabled:
        active = [item for item in monitors() if not item.get("disabled") and item.get("mirrorOf", "none") in ("none", "", None)]
        if len(active) <= 1 and any(item["name"] == name for item in active):
            raise ValueError("The last active display must stay enabled")
        hypr("eval", f"hl.monitor({{ output={json.dumps(name)}, disabled=true }})")
        return
    if mode is None:
        mode = (f'{m["width"]}x{m["height"]}@{m["refreshRate"]}'
                if m.get("width", 0) > 0 and not m.get("disabled") else "preferred")
    mode = mode.removesuffix("Hz")
    if not re.fullmatch(r"(?:preferred|highres|highrr|[0-9]+x[0-9]+@[0-9.]+)", mode):
        raise ValueError("Invalid display mode")
    scale = float(scale if scale is not None else m.get("scale", 1) or 1)
    if not math.isfinite(scale) or not 0.25 <= scale <= 3:
        raise ValueError("Scale must be between 0.25 and 3")
    mirror = mirror if mirror is not None else m.get("mirrorOf", "none")
    mirror = "" if mirror in (None, "none") else mirror
    if mirror:
        source = next((item for item in monitors() if item["name"] == mirror), None)
        if not source or source.get("disabled") or source.get("mirrorOf", "none") not in (None, "", "none") or mirror == name:
            raise ValueError("Choose an enabled, independent display to mirror")
        (directory / f".auto-disable-{mirror}").unlink(missing_ok=True)
    fields = dict(output=name, disabled=False, mode=mode, position="auto", scale=scale,
                  transform=m.get("transform", 0), mirror=mirror)
    lua = "hl.monitor({ " + ", ".join(f"{key}={json.dumps(value)}" for key, value in fields.items()) + " })"
    hypr("eval", lua)
    # A successful IPC exit alone does not guarantee that a mode/scale was accepted.
    actual = None
    for _ in range(10):
        time.sleep(0.1)
        actual = next((item for item in monitors() if item["name"] == name), None)
        actual_mirror = (actual or {}).get("mirrorOf", "none")
        actual_mirror = "" if actual_mirror in (None, "none") else actual_mirror
        mode_ok = mode in ("preferred", "highres", "highrr")
        if actual and not mode_ok:
            size, refresh = mode.split("@")
            mode_ok = size == f'{actual["width"]}x{actual["height"]}' and abs(actual["refreshRate"] - float(refresh)) < 0.6
        if actual and not actual.get("disabled") and abs(actual["scale"] - scale) < 0.001 and actual_mirror == mirror and mode_ok:
            break
    else:
        raise RuntimeError(f"Display change was not accepted. Current scale: {(actual or {}).get('scale', '?')}")
    target = directory / "monitors.d" / f"{name}.conf"
    target.parent.mkdir(parents=True, exist_ok=True)
    # Replace the file, including legacy links into the source checkout.
    temporary = target.with_suffix(".conf.tmp")
    temporary.write_text(f"{mode},auto,{scale:.8g},{mirror}\n")
    os.replace(temporary, target)


def layout(kind):
    items = monitors()
    panels = [m for m in items if internal(m)]
    outputs = [m for m in items if external(m)]
    if not panels or not outputs:
        raise ValueError("Connect an external display first")
    if kind not in ("internal", "external", "extend", "mirror"):
        raise ValueError("Unknown display layout")
    # Enable destinations before disabling anything; mirroring needs an active source.
    if kind != "external":
        for m in panels:
            (Path.home() / f'.config/hypr/.auto-disable-{m["name"]}').unlink(missing_ok=True)
            apply(m, mirror="")
    if kind != "internal":
        for m in outputs:
            apply(m, mirror=panels[0]["name"] if kind == "mirror" else "")
    if kind == "external":
        for m in panels:
            apply(m, enabled=False)
    elif kind == "internal":
        for m in outputs:
            apply(m, enabled=False)


def main():
    try:
        request = json.loads(sys.argv[1])
        if "layout" in request:
            layout(request["layout"])
        else:
            name = request.pop("name")
            m = next(m for m in monitors() if m["name"] == name)
            apply(m, **request)
        print(json.dumps({"ok": True}))
    except Exception as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
