#!/usr/bin/env python3
"""Create an 802.1X profile through D-Bus; receive credentials only on stdin.

NetworkManager owns secret storage. A failed attempt deletes only the new,
unsaved profile, never an existing profile with the same SSID.
"""
import json
import os
from pathlib import Path
import pwd
import subprocess
import sys
import uuid


def settings_for(data, variant):
    def string(key, default=""):
        value = data.get(key, default)
        if not isinstance(value, str) or "\0" in value:
            raise ValueError("Invalid field")
        return value

    ssid = string("ssid")
    identity = string("identity").strip()
    password = string("password")
    eap = string("eap", "peap")
    phase2 = string("phase2", "mschapv2")
    domain = string("domain").strip()
    ca = string("caCert").strip()
    if not 1 <= len(ssid.encode()) <= 32 or not identity or not password:
        raise ValueError("Missing credentials")
    if eap not in ("peap", "ttls") or phase2 not in (
        ("mschapv2",) if eap == "peap" else ("mschapv2", "pap")
    ):
        raise ValueError("Unsupported EAP method")
    if any(c.isspace() for c in domain):
        raise ValueError("Invalid server domain")
    if ca:
        ca = str(Path(ca).expanduser().resolve(strict=True))
        if not Path(ca).is_file():
            raise ValueError("Invalid certificate")

    profile_uuid = str(uuid.uuid4())
    settings = {
        "connection": {
            "id": variant("s", ssid),
            "uuid": variant("s", profile_uuid),
            "type": variant("s", "802-11-wireless"),
            "autoconnect": variant("b", False),
            "permissions": variant("as", [f"user:{pwd.getpwuid(os.getuid()).pw_name}:"]),
        },
        "802-11-wireless": {
            "ssid": variant("ay", list(ssid.encode())),
            "mode": variant("s", "infrastructure"),
            "hidden": variant("b", bool(data.get("hidden", False))),
        },
        "802-11-wireless-security": {"key-mgmt": variant("s", "wpa-eap")},
        "802-1x": {
            "eap": variant("as", [eap]),
            "identity": variant("s", identity),
            "password": variant("s", password),
            "password-flags": variant("u", 0),
            "phase2-auth": variant("s", phase2),
            "system-ca-certs": variant("b", not bool(ca)),
        },
        "ipv4": {"method": variant("s", "auto")},
        "ipv6": {"method": variant("s", "auto")},
    }
    if domain:
        settings["802-1x"]["domain-suffix-match"] = variant("s", domain)
    anonymous = string("anonymousIdentity").strip()
    if anonymous:
        settings["802-1x"]["anonymous-identity"] = variant("s", anonymous)
    if ca:
        settings["802-1x"]["ca-cert"] = variant("ay", list(("file://" + ca + "\0").encode()))
    return profile_uuid, settings


def connect(data, bus, Gio, GLib, run=subprocess.run):
    profile_uuid, settings = settings_for(data, GLib.Variant)
    service = "org.freedesktop.NetworkManager"
    interface = service + ".Settings.Connection"

    def call(path, iface, method, parameters=None):
        return bus.call_sync(service, path, iface, method, parameters, None,
                             Gio.DBusCallFlags.NONE, 30000, None)

    path = call("/org/freedesktop/NetworkManager/Settings", service + ".Settings",
                "AddConnectionUnsaved", GLib.Variant("(a{sa{sv}})", (settings,))).unpack()[0]
    activated = False
    try:
        result = run(["nmcli", "--wait", "90", "connection", "up", "uuid", profile_uuid],
                     capture_output=True, timeout=100, check=False)
        if result.returncode:
            return {"success": False, "reason": "activation"}
        activated = True
        # Enable autoconnect only after credentials have been accepted.
        settings["connection"]["autoconnect"] = GLib.Variant("b", True)
        try:
            call(path, interface, "Update", GLib.Variant("(a{sa{sv}})", (settings,)))
        except GLib.Error:
            return {"success": True, "saved": False}
        return {"success": True, "saved": True}
    finally:
        if not activated:
            call(path, interface, "Delete")


def main():
    try:
        from gi.repository import Gio, GLib
    except ImportError:
        return {"success": False, "reason": "dependencies"}
    try:
        data = json.loads(sys.stdin.readline())
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        return connect(data, bus, Gio, GLib)
    except (ValueError, OSError):
        return {"success": False, "reason": "settings"}
    except (GLib.Error, subprocess.SubprocessError):
        # Do not echo subprocess output or exception text containing credentials.
        return {"success": False, "reason": "network"}


if __name__ == "__main__":
    print(json.dumps(main()), flush=True)
