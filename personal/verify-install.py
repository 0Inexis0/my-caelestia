#!/usr/bin/env python3
"""Read-only installation checks, usable after bootstrap or independently."""
import json
import os
from pathlib import Path
import subprocess
import sys


def verify(source, config, data, bin_dir, session=True):
    errors = []
    def require(condition, message):
        if not condition:
            errors.append(message)
    for name in ('shell.json', 'cli.json'):
        path = config / 'caelestia' / name
        try:
            json.loads(path.read_text())
        except (OSError, ValueError) as error:
            errors.append(f'{path}: {error}')
    paths = list((source / 'personal/config/hypr').rglob('*.lua'))
    paths += list((source / 'personal/config/hypr').rglob('*.sh'))
    paths += list((source / 'personal/config/caelestia').glob('*.sh'))
    for original in paths:
        if 'monitors.d' in original.parts:
            continue
        destination = config / original.relative_to(source / 'personal/config')
        require(destination.is_symlink() and destination.exists() and destination.resolve() == original.resolve(),
                f'Config link is missing or points elsewhere: {destination}')
    command = bin_dir / 'rice-update'
    require(command.is_symlink() and command.resolve() == (source / 'personal/update.sh').resolve()
            and os.access(command, os.X_OK), f'Updater command is not installed correctly: {command}')
    shell = config / 'quickshell/caelestia'
    release = shell.resolve().parent
    require(shell.is_symlink() and release.parent == (data / 'releases').resolve(),
            'Active shell does not point to a managed release')
    require((shell / 'shell.qml').is_file(), 'Active shell.qml is missing')
    for name in ('core', 'components', 'config', 'services'):
        require((release / f'qml/Caelestia/lib/libcaelestia-{name}.so').is_file(), f'Compiled plugin missing: {name}')
    try:
        metadata = json.loads((release / 'release.json').read_text())
        require(bool(metadata.get('revision')) and bool(metadata.get('qt')), 'Release metadata is incomplete')
    except (OSError, ValueError) as error:
        errors.append(f'Release metadata: {error}')
    checks = [['qs', '--private-check-compat']]
    if session:
        checks.append(['qs', '-p', str(shell), 'ipc', 'show'])
    for command in checks:
        try:
            subprocess.run(command, check=True, capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.SubprocessError) as error:
            errors.append(f'{command}: {error}\n{getattr(error, "stderr", "") or ""}')
    if errors:
        raise RuntimeError('\n'.join(errors))


if __name__ == '__main__':
    source = Path(__file__).resolve().parents[1]
    config = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config')))
    data = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'my-caelestia'
    try:
        verify(source, config, data, Path.home() / '.local/bin', bool(os.environ.get('WAYLAND_DISPLAY')))
    except RuntimeError as error:
        print(f'Installation verification failed:\n{error}', file=sys.stderr)
        sys.exit(1)
    print('Config links, JSON, compiled plugin, Qt compatibility and updater command verified.')
