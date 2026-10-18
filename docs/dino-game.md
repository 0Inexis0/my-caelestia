# Dino and neutral profile artwork

An empty notification sidebar contains a small Dino runner. Click it to start;
click, Space or Up jumps. P pauses, and Escape closes the sidebar. After a
collision, click or press Space to start a new run. The game pauses when the
sidebar closes, notifications arrive, another drawer takes focus, or focus leaves
the game. Returning requires an explicit click or key press to resume.

The high score is stored in `$XDG_STATE_HOME/caelestia-dino.ini` (normally
`~/.local/state/caelestia-dino.ini`). The game only ticks while running and visible.
Notification actions and the lock screen's notification view are unchanged.

The power selector uses a palette-colored power symbol in place of the bundled
anime GIF. An explicitly configured custom `paths.sessionGif` still works.

`personal/install-avatar.sh` installs `assets/user.svg` as `~/.face` only when
neither `~/.face` nor `~/.face.icon` already exists. The lock screen reads `.face`;
the Caelestia SDDM theme reads a copy in its assets directory. The personal installer
runs this helper automatically. With sudo already authenticated it also syncs
SDDM; otherwise run this in a terminal to authenticate:

```sh
bash ~/.local/share/my-caelestia/source/personal/install-avatar.sh --sync-sddm
```

This keeps personal avatars, does not replace the theme's packaged anime image,
and supplies the higher-priority `avatar.face` / `avatar.face.icon` override used by
the theme. After a theme reinstall, rerun the sync command if necessary.

Run the game tests without a desktop:

```sh
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml -o -,txt
```

They cover jumping and landing, collision and restart, clearing obstacles,
spawning, scoring, speed limits, long frame gaps, mouse/keyboard controls and pause
when the sidebar becomes unavailable.
