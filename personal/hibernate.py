#!/usr/bin/env python3
"""Inspect hibernation, or explicitly provision Btrfs swap on CachyOS/Limine.

Never suspends, hibernates, reboots, or writes to /sys/power/resume.
"""
import argparse
from datetime import datetime, timezone
import fcntl
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

GIB = 1024 ** 3
SWAP_DIR = Path('/swap')
SWAP_FILE = SWAP_DIR / 'caelestia.swap'
SUBVOL = '@caelestia-swap'
BEGIN = '# BEGIN caelestia hibernate'
END = '# END caelestia hibernate'


def run(*args):
    return subprocess.run(list(map(str, args)), check=True, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.strip()


def mount_info(path):
    return json.loads(run('findmnt', '-J', '-o', 'TARGET,FSTYPE,UUID,FSROOT',
                          '--target', path))['filesystems'][0]


def managed_block(original, content):
    """Replace only our block; preserve unrelated configuration verbatim."""
    if original.count(BEGIN) != original.count(END) or original.count(BEGIN) > 1:
        raise RuntimeError('Malformed managed configuration block')
    block = f'{BEGIN}\n{content.rstrip()}\n{END}\n'
    if BEGIN in original:
        return re.sub(re.escape(BEGIN) + r'\n.*?' + re.escape(END) + r'\n?',
                      lambda _: block, original, flags=re.S)
    return original + ('' if not original or original.endswith('\n') else '\n') + block


def resume_config(original, uuid, offset):
    unmanaged = re.sub(re.escape(BEGIN) + r'\n.*?' + re.escape(END) + r'\n?',
                       '', original, flags=re.S)
    active = '\n'.join(line for line in unmanaged.splitlines()
                       if not line.lstrip().startswith('#'))
    if re.search(r'\b(?:resume=|resume_offset=|noresume\b)', active):
        raise RuntimeError('Existing resume settings in Limine; reconcile them manually first')
    if not re.fullmatch(r'[a-fA-F0-9-]+', uuid) or not re.fullmatch(r'[0-9]+', str(offset)):
        raise RuntimeError('Invalid resume UUID or offset')
    return managed_block(original,
                         f'KERNEL_CMDLINE[default]+=" resume=UUID={uuid} resume_offset={offset}"')


def fstab_config(original, uuid):
    unmanaged = re.sub(re.escape(BEGIN) + r'\n.*?' + re.escape(END) + r'\n?',
                       '', original, flags=re.S)
    for line in unmanaged.splitlines():
        fields = line.split()
        if fields and not fields[0].startswith('#') and (
                fields[0] == str(SWAP_FILE) or (len(fields) > 1 and fields[1] == str(SWAP_DIR))):
            raise RuntimeError('Existing /swap configuration; reconcile it manually first')
    return managed_block(original,
                         f'UUID={uuid} /swap btrfs subvol=/{SUBVOL},noatime 0 0\n'
                         f'{SWAP_FILE} none swap defaults,pri=10 0 0')


def write_config(path, content):
    """Atomic replacement, retaining ownership and permissions of existing files."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(content.encode())
            stream.flush()
            os.fsync(stream.fileno())
            if path.exists():
                st = path.stat()
                os.chown(temporary, st.st_uid, st.st_gid)
                os.chmod(temporary, st.st_mode & 0o777)
            else:
                os.chmod(temporary, 0o644)
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def check():
    print('Read-only hibernation check (no power action):')
    print('Root:', json.dumps(mount_info('/')))
    print('Memory:', next(line for line in Path('/proc/meminfo').read_text().splitlines()
                          if line.startswith('MemTotal:')))
    print('Kernel states:', Path('/sys/power/state').read_text().strip())
    print('Resume device / offset:', Path('/sys/power/resume').read_text().strip(),
          '/', Path('/sys/power/resume_offset').read_text().strip())
    print('Kernel command line:', Path('/proc/cmdline').read_text().strip())
    print(Path('/proc/swaps').read_text().strip())
    for method in ('CanHibernate', 'CanSuspendThenHibernate'):
        print(method + ':', run('busctl', 'call', 'org.freedesktop.login1',
                                '/org/freedesktop/login1', 'org.freedesktop.login1.Manager', method))


def setup(size_gib):
    if os.geteuid() != 0:
        raise RuntimeError('Setup needs root: sudo python3 personal/hibernate.py setup')
    if Path('/var/lib/pacman/db.lck').exists():
        raise RuntimeError('A package update is active (pacman db.lck); finish it before setup')
    lock = Path('/run/caelestia-hibernate.lock').open('a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    # Root subprocesses must not resolve executables from the caller's PATH.
    os.environ['PATH'] = '/usr/sbin:/usr/bin:/sbin:/bin'
    for tool in ('btrfs', 'findmnt', 'mount', 'umount', 'limine-entry-tool', 'limine-mkinitcpio'):
        if not shutil.which(tool):
            raise RuntimeError(f'Missing required tool: {tool}')
    root = mount_info('/')
    uuid = root.get('uuid', '')
    if root['fstype'] != 'btrfs' or not re.fullmatch(r'[a-fA-F0-9-]+', uuid):
        raise RuntimeError('Automatic setup supports a Btrfs root filesystem only')
    if 'disk' not in Path('/sys/power/state').read_text().split():
        raise RuntimeError('Kernel does not expose hibernation')
    if '[none]' not in Path('/sys/kernel/security/lockdown').read_text():
        raise RuntimeError('Kernel lockdown is active')
    hooks = Path('/etc/mkinitcpio.conf').read_text()
    if not re.search(r'^HOOKS=\([^\n)]*\bsystemd\b', hooks, re.M):
        raise RuntimeError('Setup requires the systemd mkinitcpio hook')
    boot = Path('/etc/default/limine')
    boot_text = boot.read_text()
    kernel_names = sorted({path.read_text().strip()
                           for path in Path('/usr/lib/modules').glob('*/pkgbase')
                           if (path.parent / 'modules.builtin').is_file()})
    if not kernel_names:
        raise RuntimeError('No installed kernel found for the Limine rebuild')
    if mount_info('/boot')['target'] != '/boot' or 'ESP_PATH="/boot"' not in boot_text:
        raise RuntimeError('Setup requires the Limine ESP mounted at /boot')
    if shutil.disk_usage('/boot').free < 512 * 1024 ** 2:
        raise RuntimeError('Less than 512 MiB free on /boot; free space before rebuilding')
    if not re.search(r'Total devices\s+1\b', run('btrfs', 'filesystem', 'show', '/')):
        raise RuntimeError('Automatic setup requires single-device Btrfs')
    memory_kib = int(re.search(r'^MemTotal:\s+(\d+)', Path('/proc/meminfo').read_text(), re.M)[1])
    minimum = math.ceil(memory_kib * 1024 / GIB)
    if size_gib < minimum:
        raise RuntimeError(f'Use at least {minimum} GiB swap for this system')
    # Validate conflicting config before creating storage or editing anything.
    resume_config(boot_text, uuid, 0)
    fstab = Path('/etc/fstab')
    new_fstab = fstab_config(fstab.read_text(), uuid)
    if SWAP_DIR.is_symlink() or SWAP_FILE.is_symlink():
        raise RuntimeError('Refusing symlinks at managed swap paths')
    mounted = mount_info(SWAP_DIR if SWAP_DIR.exists() else '/')
    if mounted['target'] == str(SWAP_DIR):
        if mounted['uuid'] != uuid or mounted['fsroot'] != '/' + SUBVOL:
            raise RuntimeError('/swap is mounted from an unexpected filesystem or subvolume')
        if not (SWAP_DIR / '.caelestia-hibernate').is_file():
            raise RuntimeError('/swap is not managed by this script')
    else:
        if SWAP_DIR.exists() and any(SWAP_DIR.iterdir()):
            raise RuntimeError('/swap is not empty; refusing to change it')
    if not SWAP_FILE.exists() and shutil.disk_usage('/').free < (size_gib + 16) * GIB:
        raise RuntimeError('Insufficient free space for swap plus a 16 GiB reserve')
    for line in Path('/proc/swaps').read_text().splitlines()[1:]:
        path = line.split()[0]
        if not path.startswith('/dev/zram') and path != str(SWAP_FILE):
            raise RuntimeError(f'Existing disk swap {path}; configure its resume target manually')
    backup = Path('/var/backups/caelestia-hibernate') / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup.mkdir(parents=True, mode=0o700)
    for path in (boot, fstab):
        shutil.copy2(path, backup / path.name)
    print(f'Configuration backups: {backup}', flush=True)
    # A top-level subvolume stays separate from root snapshots and rollbacks.
    if mounted['target'] != str(SWAP_DIR):
        with tempfile.TemporaryDirectory(prefix='caelestia-swap-') as directory:
            run('mount', '-t', 'btrfs', '-o', 'subvolid=5', f'UUID={uuid}', directory)
            try:
                subvolume = Path(directory) / SUBVOL
                if not subvolume.exists():
                    run('btrfs', 'subvolume', 'create', subvolume)
                elif not (subvolume / '.caelestia-hibernate').is_file():
                    raise RuntimeError(f'Existing {SUBVOL} is not managed by this script')
                (subvolume / '.caelestia-hibernate').touch(mode=0o600)
            finally:
                run('umount', directory)
        SWAP_DIR.mkdir(mode=0o700, exist_ok=True)
        run('mount', '-t', 'btrfs', '-o', f'subvol=/{SUBVOL},noatime', f'UUID={uuid}', SWAP_DIR)
    if not SWAP_FILE.exists():
        run('btrfs', 'filesystem', 'mkswapfile', '--size', f'{size_gib}G', SWAP_FILE)
    elif SWAP_FILE.stat().st_size < size_gib * GIB:
        raise RuntimeError('Existing managed swap is too small; refusing to replace it')
    offset = run('btrfs', 'inspect-internal', 'map-swapfile', '-r', SWAP_FILE)
    new_boot = resume_config(boot_text, uuid, offset)
    # Do not enable disk swap in this session: a critical-battery daemon could
    # immediately start hibernation as soon as CanHibernate becomes available.
    write_config(fstab, new_fstab)
    write_config(boot, new_boot)
    for kernel_name in kernel_names:
        effective = run('limine-entry-tool', '--get-cmdline', kernel_name, '--no-mutex', '--no-hooks')
        options = effective.splitlines()[-1].split()
        resume = [option for option in options if option.startswith('resume=')]
        offsets = [option for option in options if option.startswith('resume_offset=')]
        if resume != [f'resume=UUID={uuid}'] or offsets != [f'resume_offset={offset}'] or 'noresume' in options:
            raise RuntimeError(f'Conflicting effective resume options for {kernel_name}; '
                               'boot images were not rebuilt')
    print('Rebuilding Limine boot images; this may take several minutes.', flush=True)
    result = subprocess.run(['limine-mkinitcpio'], text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    (backup / 'limine-mkinitcpio.log').write_text(result.stdout)
    if result.returncode:
        raise RuntimeError(f'Boot rebuild failed; inspect {backup}/limine-mkinitcpio.log. '
                           'Setup is incomplete. Configuration backups are in the same directory.')
    print(f'Prepared {SWAP_FILE} ({SWAP_FILE.stat().st_size // GIB} GiB), resume offset {offset}.')
    print('Reboot manually when convenient. Swap becomes active on the next boot.')
    print('No suspend, hibernate or reboot was requested. Idle actions were not changed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', nargs='?', choices=('check', 'setup'), default='check')
    parser.add_argument('--size-gib', type=int, default=36)
    args = parser.parse_args()
    try:
        if args.action == 'setup':
            setup(args.size_gib)
        else:
            check()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f'Error: {error}', file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr or '', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
