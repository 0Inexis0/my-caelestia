# Upstream integration review — 2026-09-14

## Baseline

- Fork: `0Inexis0/my-caelestia`, custom branch `mine` at `3aa77ae6`.
- Upstream: `caelestia-dots/shell`, `main` at `f435b2c1799c545c209a4ab15c9389070958bc86`.
- 52 upstream-only commits integrated; 48 fork-only commits preserved through a merge.
- The initial live checkout was clean. Integration was developed in a separate worktree; managed deployment retains the legacy checkout as a backup.

## Customization audit

| Area | Finding / decision |
| --- | --- |
| Bluetooth audio | Caelestia still writes node audio properties. The matching Quickshell issue [#807](https://github.com/quickshell-mirror/quickshell/issues/807) and fix [#808](https://github.com/quickshell-mirror/quickshell/pull/808) remain open. Retain the existing wpctl workaround; no hardware claim is made by this review. |
| Display settings | Upstream still has a commented-out Display entry. Preserve the page and component registry ordering. Resolve the registry conflict using the new translation API; add missing Caelestia.Config imports for Tokens in both DisplayPage and MonitorSection. |
| Ollama assistant | No equivalent upstream feature. Preserve ScreenState, shortcut, keyboard focus, drawer region and panel integration. Migrate strings to Caelestia.I18n and fix QML lint warnings. |
| Wallpaper Engine / monitor scripts | Fork-specific integrations remain necessary for this setup; no equivalent replacement is present in shell upstream. Retain them. Separate CLI, dotfiles and renderer repositories were not exhaustively audited. |
| Suspend / personal configuration | Retain personal choices. Shipped workspace keys remain valid; the removed perMonitorWorkspaces option is not present in the shipped shell.json. |
| README | Keep fork documentation, add current compatibility constraints instead of restoring the full upstream README. |
| GitHub CI | Enable build, lint and format on mine; build and use a fork-owned Arch image because the upstream registry denied access. Add translation validation; ensure local build types take precedence over installed Qt module defaults. |
| Bootstrap | Explicitly clone mine; installation no longer depends on the repository default branch. |

## Verification

- Full Release CMake/Ninja build: passed (222 build steps, GCC 16.2.1 / Qt 6.11.2).
- Compiler emitted warnings in unchanged upstream LazyListView / Qt QHash code; the build succeeded. This was not a -Werror build.
- QML semantic lint of all tracked QML with the freshly built module and generated Quickshell tooling: passed with no output.
- QML convention checker and translation checker: passed repository-wide.
- Isolated Wayland load with the installed matching plugin: reached `Configuration Loaded`; the updater also explicitly instantiates the lazy AI and Display UI before accepting a release.
- Smoke-test config/state/cache/runtime were temporary; session D-Bus and Hyprland access were disabled. Lazy UI is instantiated on a transparent, input-empty 1×1 surface. Expected service-unavailable warnings occurred. This is a load test, not an end-to-end Bluetooth/display/Ollama hardware test.

## Managed deployment

The selected strategy is latest upstream with a matching local plugin build.
`personal/manage.py` installs each QML/plugin pair into a separate user-local
release. The live configuration is switched only after a successful build and
isolated load check; failed starts restore the previous selection. Package-owned
plugins are untouched. The source checkout now lives under
`$XDG_DATA_HOME/my-caelestia/source` (default `~/.local/share`).

The updater merges origin/mine and upstream/main in a temporary worktree, preserves
history, and pushes normally after activation. It no longer selects release tags,
rebases, or force-pushes. Source edits are committed before merging; failed commits
are errors. An explicit --no-restart supports installation before graphical login.
A rollback selects both previous QML and plugin, but cannot undo a Qt/system upgrade.

All ten GitHub checks passed on the final code revision, including GCC, Clazy, Nix, QML/C++ lint, formatting, translations and updater tests.

Twelve updater regression tests cover Git conflict handling, retained local history, failed saves,
failed builds/launches, atomic selection, and legacy linked-worktree migration.
GitHub CI uses a fork-owned Arch image because the upstream image denied access.

The first real activation exposed Quickshell emitting a plain-text empty-list message despite --json. The manager now handles that output explicitly, rejects unknown output, and restores the old shell even if stopping it fails midway. Regression coverage includes these cases.
