# Hibernation on CachyOS with Btrfs and Limine

From the fork checkout, inspect the system without changing it:

```sh
python3 personal/hibernate.py check
```

To explicitly prepare hibernation (root authentication required):

```sh
sudo python3 personal/hibernate.py setup
```

The helper requires single-device Btrfs, Limine at `/boot`, the systemd mkinitcpio
hook, kernel hibernation support, and disabled kernel lockdown. It creates 36 GiB
of swap by default (`--size-gib N` overrides this, with at least RAM size required),
keeping at least 16 GiB free. It rejects conflicting swap mounts and resume settings.
Finish any running system update first; setup refuses an existing Pacman lock.

Storage lives in top-level `@caelestia-swap`, mounted at `/swap`, separately from root
snapshots. `btrfs filesystem mkswapfile` handles NOCOW and allocation;
`btrfs inspect-internal map-swapfile -r` validates the file and supplies the physical
resume offset. Existing files are never resized or replaced. Zram keeps its higher
priority; disk swap uses priority 10.

The helper backs up `/etc/fstab` and `/etc/default/limine` under
`/var/backups/caelestia-hibernate/<timestamp>/`, adds managed entries, and runs
`limine-mkinitcpio` to rebuild boot images and entries. Its output is saved beside
the backups. If rebuilding fails, setup is incomplete: inspect that log and fix the
reported error before rebooting. To undo configuration changes, restore `fstab` and
`limine` from that backup to their original paths and rebuild with
`sudo limine-mkinitcpio`. The helper deliberately leaves storage intact on failure.

No disk swap is activated in the current session: making hibernation available
could trigger a critical-battery daemon. Reboot manually when convenient to load
the new resume parameters and activate swap. The script never requests suspend,
hibernate, or reboot, and never writes to `/sys/power/resume`. Idle actions and
gestures continue to use their existing configuration.

After reboot, rerun `check`: `/proc/swaps` should include `/swap/caelestia.swap`,
the command line should include `resume=UUID=... resume_offset=...`, and logind
should report `CanHibernate: s "yes"` (or `"challenge"` if authentication is needed).
These checks validate configuration; a later manual hibernate/resume cycle is
still required to verify the hardware end to end. Do that only after saving work,
with sufficient battery charge. This setup does not configure NVIDIA drivers;
systems using NVIDIA may need additional driver-specific power-management setup.

References: [Btrfs swapfile documentation](https://btrfs.readthedocs.io/en/latest/Swapfile.html),
[systemd resume generator](https://www.freedesktop.org/software/systemd/man/latest/systemd-hibernate-resume-generator.html).
