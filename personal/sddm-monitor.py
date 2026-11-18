#!/usr/bin/python3
"""SDDM Xsetup hook. Match DRM and Xorg outputs by EDID across GPU drivers."""
from pathlib import Path
import pwd
import re
import subprocess
import sys


def main(user):
    home = Path(pwd.getpwnam(user).pw_dir)
    # Read user-controlled paths with that user's privileges.
    result = subprocess.run(["runuser", "-u", user, "--", "head", "-c", "128",
                             home / ".config/hypr/primary-monitor"],
                            capture_output=True, timeout=2)
    name = result.stdout.decode("ascii").strip()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", name):
        return
    edids = {path.read_bytes().hex() for path in Path("/sys/class/drm").glob(
        f"card*-{name}/edid")}
    edids.discard("")
    props = subprocess.check_output(["xrandr", "--props"], text=True, timeout=5)
    for block in re.split(r"\n(?=\S)", props):
        output = re.match(r"([\w.-]+) connected\b", block)
        edid = re.search(r"\n[ \t]+EDID:[ \t]*\n((?:[ \t]+[\da-fA-F]{32}(?:\n|$))+)", block)
        if output and edid and "".join(edid[1].split()).lower() in edids:
            name = output[1]
            subprocess.run(["xrandr", "--output", name, "--auto", "--primary"], check=True)
            for other in re.findall(r"^([\w.-]+) connected\b", props, re.M):
                if other != name:
                    subprocess.run(["xrandr", "--output", other, "--off"], check=True)
            return


if __name__ == "__main__":
    main(sys.argv[1])
