#!/usr/bin/env python3
"""Build, validate and activate matched, user-local Caelestia releases."""
import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


def run(*args, cwd=None, capture=False, **kwargs):
    return subprocess.run([str(a) for a in args], cwd=cwd, check=True,
                          text=True, stdout=subprocess.PIPE if capture else None,
                          **kwargs).stdout


def git(source, *args):
    return run('git', '-C', source, *args, capture=True).strip()


def atomic_link(target, link):
    link.parent.mkdir(parents=True, exist_ok=True)
    temporary = link.with_name(link.name + '.next')
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(target, target_is_directory=True)
    os.replace(temporary, link)


def build_jobs():
    memory = next(line for line in Path('/proc/meminfo').read_text().splitlines()
                  if line.startswith('MemAvailable:'))
    return max(1, min(os.cpu_count() or 1, int(memory.split()[1]) // (2 * 1024 * 1024), 8))


def build(source, data):
    """Install everything in one private prefix; no writes to package-owned files."""
    revision = git(source, 'rev-parse', 'HEAD')
    releases = data / 'releases'
    releases.mkdir(parents=True, exist_ok=True)
    release = Path(tempfile.mkdtemp(prefix=revision[:12] + '-', dir=releases))
    build_dir = source / 'build'
    try:
        run('cmake', '-S', source, '-B', build_dir, '-G', 'Ninja',
            '-DCMAKE_BUILD_TYPE=Release', f'-DCMAKE_INSTALL_PREFIX={release}',
            '-DINSTALL_QMLDIR=qml', '-DINSTALL_LIBDIR=lib', '-DINSTALL_QSCONFDIR=shell')
        run('cmake', '--build', build_dir, '--parallel', build_jobs())
        run('cmake', '--install', build_dir)
        shell = release / 'shell/shell.qml'
        # Quickshell reads Env pragmas before constructing the QML engine.
        # Absolute paths bind this QML snapshot to exactly its own installed plugin.
        for path in (release,):
            if any(c in str(path) for c in '\n\r:'):
                raise RuntimeError('Release paths must not contain newlines or colons')
        shell.write_text(f'//@ pragma Env QML2_IMPORT_PATH={release}/qml\n'
                         f'//@ pragma Env QML_IMPORT_PATH={release}/qml\n'
                         f'//@ pragma Env CAELESTIA_LIB_DIR={release}/lib\n' + shell.read_text())
        (release / 'release.json').write_text(json.dumps({
            'revision': revision,
            'qt': run('pkg-config', '--modversion', 'Qt6Core', capture=True).strip(),
            'quickshell': run('qs', '--version', capture=True).strip(),
        }, indent=2) + '\n')
        return release
    except BaseException:
        # Never remove a previously usable release on a failed rebuild.
        shutil.rmtree(release)
        raise



def add_feature_probe(shell):
    """Instantiate lazy fork UI on a transparent, input-empty test surface."""
    text = shell.read_text()
    text = text.replace('ShellRoot {', """import qs.components as ProbeComponents
import qs.modules.ai as ProbeAi
import qs.modules.nexus as ProbeNexus
import qs.modules.nexus.pages as ProbePages
import qs.modules.nexus.pages.display as ProbeDisplay

ShellRoot {""", 1)
    at = text.rfind('}')
    text = text[:at] + """
    PanelWindow {
        color: "transparent"
        mask: Region {}
        implicitWidth: 1
        implicitHeight: 1
        Loader {
            opacity: 0
            active: false
            Component.onCompleted: Qt.callLater(() => active = true)
            sourceComponent: Item {
                Component.onCompleted: console.info("Fork feature probe loaded")
        ProbeComponents.ScreenState { id: probeState; modelData: Quickshell.screens[0]; ai: true }
        ProbeNexus.NexusState { id: probeNexus; screen: Quickshell.screens[0] }
        ProbeAi.Content { screenState: probeState; maxHeight: 740 }
        ProbeAi.MessageItem { role: "user"; content: "Load test"; images: [] }
        ProbePages.DisplayPage { nState: probeNexus; width: 800 }
        ProbeDisplay.MonitorSection {
            monitorData: ({name: "TEST-1", width: 1920, height: 1080, refreshRate: 60,
                           scale: 1, availableModes: ["1920x1080@60Hz"]})
        }
            }
        }
    }
""" + text[at:]
    shell.write_text(text)

def smoke(release, log):
    """Use a distinct config/runtime and private state; do not claim session services."""
    with tempfile.TemporaryDirectory(prefix='caelestia-smoke-') as directory:
        scratch = Path(directory)
        runtime = scratch / 'runtime'
        runtime.mkdir(mode=0o700)
        shell = scratch / 'shell'
        shutil.copytree(release / 'shell', shell, symlinks=True)
        add_feature_probe(shell / 'shell.qml')
        env = os.environ.copy()
        display = env.get('WAYLAND_DISPLAY', '')
        if not display:
            raise RuntimeError('Run the update in a Wayland session (or use --no-restart for installation before login)')
        if not display.startswith('/'):
            display = str(Path(env.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / display)
        env.update(QT_QPA_PLATFORM='wayland', WAYLAND_DISPLAY=display,
                   XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(scratch / 'config'),
                   XDG_STATE_HOME=str(scratch / 'state'), XDG_CACHE_HOME=str(scratch / 'cache'),
                   HYPRLAND_INSTANCE_SIGNATURE='', DBUS_SESSION_BUS_ADDRESS='unix:path=' + str(scratch / 'no-bus'))
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open('w') as output:
            process = subprocess.Popen(['qs', '-p', str(shell), '--no-color'], env=env,
                                       stdout=output, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 15
                loaded_at = None
                while time.monotonic() < deadline:
                    text = log.read_text()
                    if process.poll() is not None or any(error in text for error in (
                            'Failed to load configuration', 'ReferenceError:', 'TypeError:')):
                        raise RuntimeError(f'Shell load failed; see {log}')
                    if 'Configuration Loaded' in text and 'Fork feature probe loaded' in text:
                        loaded_at = loaded_at or time.monotonic()
                        if time.monotonic() - loaded_at >= 2:
                            return
                    time.sleep(0.2)
                raise RuntimeError(f'Shell load timed out; see {log}')
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def instances(config):
    return json.loads(run('qs', '-p', config, 'list', '--json', capture=True) or '[]')


def stop(config):
    if not config or not (config / 'shell.qml').exists():
        return
    if not instances(config):
        return
    run('qs', '-p', config, 'kill')
    deadline = time.monotonic() + 8
    while instances(config):
        if time.monotonic() >= deadline:
            raise RuntimeError('Previous shell did not exit; refusing to start a duplicate')
        time.sleep(0.2)


def start(config):
    run('qs', '-p', config, '-n', '-d')
    time.sleep(2)
    if not instances(config):
        raise RuntimeError('New shell exited after launch')
    run('qs', '-p', config, 'ipc', 'show', capture=True)


def activate(release, config, data, restart=True):
    """Switch QML and plugin together; restore the old selection if launch fails."""
    previous = config.resolve() if config.exists() else None
    backup = None
    if restart:
        stop(previous)
    try:
        if config.exists() and not config.is_symlink():
            backup = config.with_name('caelestia.before-managed-' + str(time.time_ns()))
            config.rename(backup)
            previous = backup
            # Existing linked worktrees must still point at the moved Git directory.
            if (backup / '.git').is_dir():
                run('git', '-C', backup, 'worktree', 'repair')
        atomic_link(release / 'shell', config)
        if restart:
            start(config)
    except BaseException:
        if restart:
            with contextlib.suppress(Exception):
                stop(config.resolve())
        if backup:
            config.unlink(missing_ok=True)
            backup.rename(config)
            if (config / '.git').is_dir():
                run('git', '-C', config, 'worktree', 'repair')
        elif previous:
            atomic_link(previous, config)
        else:
            config.unlink(missing_ok=True)
        if restart and previous:
            with contextlib.suppress(Exception):
                start(config)
        raise
    if previous:
        atomic_link(previous, data / 'previous')
    print(f'Activated {release.name}', flush=True)


def save_edits(source):
    if git(source, 'branch', '--show-current') != 'mine':
        raise RuntimeError('Updates require branch mine; use build to test another branch')
    if git(source, 'diff', '--name-only', '--diff-filter=U'):
        raise RuntimeError('Resolve the existing Git conflicts before updating')
    for state in ('MERGE_HEAD', 'rebase-merge', 'rebase-apply'):
        if Path(git(source, 'rev-parse', '--path-format=absolute', '--git-path', state)).exists():
            raise RuntimeError('Finish the existing merge/rebase before updating')
    if git(source, 'status', '--porcelain'):
        run('git', '-C', source, 'add', '-A')
        run('git', '-C', source, 'commit', '-m', 'Save local changes before rice-update')


def managed_source(source, data):
    destination = data / 'source'
    if source.resolve() == destination.resolve():
        return source
    if destination.exists():
        raise RuntimeError(f'{destination} already exists; run its personal/update.sh instead')
    run('git', 'clone', '--no-hardlinks', '--branch', 'mine', source, destination)
    run('git', '-C', destination, 'remote', 'set-url', 'origin', git(source, 'remote', 'get-url', 'origin'))
    upstream = git(source, 'remote', 'get-url', 'upstream') if 'upstream' in git(source, 'remote').splitlines() else 'https://github.com/caelestia-dots/shell.git'
    run('git', '-C', destination, 'remote', 'add', 'upstream', upstream)
    return destination


@contextlib.contextmanager
def candidate(source, data, update):
    path = Path(tempfile.mkdtemp(prefix='candidate-', dir=data))
    run('git', '-C', source, 'worktree', 'add', '--detach', path, 'HEAD')
    try:
        if update:
            for ref in ('origin/mine', 'upstream/main'):
                try:
                    run('git', '-C', path, 'merge', '--no-edit', ref)
                except subprocess.CalledProcessError:
                    conflicts = git(path, 'diff', '--name-only', '--diff-filter=U')
                    if ref == 'upstream/main' and conflicts == 'README.md':
                        run('git', '-C', path, 'checkout', '--ours', 'README.md')
                        run('git', '-C', path, 'add', 'README.md')
                        run('git', '-C', path, 'commit', '--no-edit')
                    else:
                        raise RuntimeError(f'Merge of {ref} failed ({conflicts}); live shell unchanged')
        yield path
    finally:
        run('git', '-C', source, 'worktree', 'remove', '--force', path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('update', 'install', 'build', 'rollback'))
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--skip-system', '-s', action='store_true')
    parser.add_argument('--no-restart', action='store_true', help='Install for next login; skip graphical load test/restart')
    parser.add_argument('--no-push', action='store_true', help='Do not publish local commits')
    args = parser.parse_args()
    data = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'my-caelestia'
    config = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'quickshell/caelestia'
    data.mkdir(parents=True, exist_ok=True)
    with (data / 'update.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.action == 'rollback':
            previous = data / 'previous'
            if not previous.exists():
                raise RuntimeError('No previous release is available')
            # Legacy backups do not have a managed release.json, but remain launchable.
            old = previous.resolve()
            if not args.no_restart:
                stop(config.resolve())
            current = config.resolve()
            atomic_link(old, config)
            try:
                if not args.no_restart:
                    start(config)
            except BaseException:
                atomic_link(current, config)
                if not args.no_restart:
                    start(config)
                raise
            atomic_link(current, previous)
            return
        source = args.source.resolve()
        update = args.action == 'update'
        if args.action != 'build':
            save_edits(source)
            source = managed_source(source, data)
        if update and not args.skip_system:
            helper = shutil.which('yay') or shutil.which('paru')
            if not helper:
                raise RuntimeError('Install yay/paru or explicitly use --skip-system')
            run(helper, '-Syu')
        run('qs', '--version')  # Catch a broken Qt private ABI after the package update.
        if update:
            if 'upstream' not in git(source, 'remote').splitlines():
                run('git', '-C', source, 'remote', 'add', 'upstream', 'https://github.com/caelestia-dots/shell.git')
            run('git', '-C', source, 'fetch', 'origin', 'mine')
            run('git', '-C', source, 'fetch', 'upstream', 'main', '--tags')
        safe_head = git(source, 'rev-parse', 'HEAD')
        with candidate(source, data, update) as work:
            release = build(work, data)
            if not args.no_restart:
                smoke(release, data / 'last-smoke.log')
            if args.action == 'build':
                print(f'Prepared release: {release}')
                return
            if git(source, 'rev-parse', 'HEAD') != safe_head or git(source, 'status', '--porcelain'):
                raise RuntimeError('Source changed while building; refusing activation')
            run('git', '-C', source, 'merge', '--ff-only', git(work, 'rev-parse', 'HEAD'))
        # Keep existing personal/config symlink destinations valid after migration.
        (release / 'shell/personal').symlink_to(source / 'personal', target_is_directory=True)
        activate(release, config, data, restart=not args.no_restart)
        bin_dir = Path.home() / '.local/bin'
        atomic_link(source / 'personal/update.sh', bin_dir / 'rice-update')
        if update and not args.no_push:
            try:
                run('git', '-C', source, 'push', 'origin', 'mine')
            except subprocess.CalledProcessError:
                print('Update works locally, but GitHub push failed. Commits are retained; retry git push origin mine.', file=sys.stderr)
                return 2
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f'rice-update: {error}', file=sys.stderr)
        sys.exit(1)
