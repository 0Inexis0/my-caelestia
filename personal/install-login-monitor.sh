#!/usr/bin/env bash
# Configure the next X11 greeter without restarting SDDM.
set -eu
user=$(id -un)
[[ "$user" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]
dir=$(dirname "$(realpath "$0")")
sudo install -Dm755 "$dir/sddm-monitor.py" /usr/local/lib/caelestia/sddm-monitor.py
sudo install -d /etc/sddm.conf.d
printf '[X11]\nDisplayCommand=/usr/local/lib/caelestia/login-monitor\n' | sudo tee /etc/sddm.conf.d/90-primary-monitor.conf >/dev/null
printf '#!/bin/sh\n/usr/share/sddm/scripts/Xsetup\n/usr/local/lib/caelestia/sddm-monitor.py %s || true\n' "$user" | sudo tee /usr/local/lib/caelestia/login-monitor >/dev/null
sudo chmod 755 /usr/local/lib/caelestia/login-monitor
