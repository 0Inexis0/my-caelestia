# Upstream integration review — 2026-09-14

## Fork reconciliation — 2026-11-18

- Continue draft #2 by merging fork main `002589ae` into its prior head
  `89c6e3c8`. Upstream is still `e72df8eb`; no new upstream behavior replaces
  a local patch. Both histories are retained.
- Preserve main's display persistence/login-display selection and Firefox
  language-pack resolution. The merge had no conflicts.
- Normalize declaration order/separators in the directly touched Dino and
  display QML; use Qt 6.12's no-argument signal formatting. Game logic, display
  operations and user-facing strings are unchanged by this style repair.
- Local checks: 64 Python tests (57 passed, 7 runtime-dependent skips),
  translations, personal shell syntax, Python compilation and whitespace pass.
  The convention checker falls from 42 to 28 existing violations in other files;
  it still fails and remains a merge gate.
- This tree has not been built or graphically loaded: local Qt 6,
  Quickshell and Nix are unavailable. Prior-head CI results do not verify this
  integrated tree. Require fresh build, format, semantic-lint and runtime checks.
  Keep the PR a draft; do not deploy or remove the Bluetooth workaround.

## Translation repair — 2026-11-16

- Upstream remains `e72df8eb`; continue draft PR #2 rather than creating another sync.
- Replace the six Dino `qsTr()` calls with the supported `Tr.tr()` helper and
  import `Caelestia.I18n`. The source strings, game logic and controls are unchanged.
- Repository-wide translation validation now passes. Local Python tests: 61 ran,
  54 passed, 7 skipped; personal shell syntax and whitespace checks pass.
- QML convention validation still finds 39 pre-existing violations across the
  repository. This repair does not change or relax any CI gate. QML format/lint,
  builds and graphical Dino tests require the Qt/Quickshell environment, which
  is absent locally. The Dino QML test now also requires the built Caelestia
  module on its import path. Do not merge until the relevant checks pass.
- Keep all hardware-sensitive local behavior. The Nix Quickshell pin already
  includes #808, but this is not a Bluetooth runtime test.

## Sync review — 2026-11-15

- Base: fork `main` at `0befbbd5`; upstream `main` at `e72df8eb`.
- Merge the one new upstream commit without rewriting either history. The only
  upstream file change is `flake.lock`: CLI `6bde2df2` → `9ab901f5` and nixpkgs
  `f9a75f41` → `d4f25a3e`. Quickshell and m3shapes pins are unchanged.
- The [CLI comparison](https://github.com/caelestia-dots/cli/compare/6bde2df241ccc0cda4baa51216ebf017fe042eb7...9ab901f592917454da396ea012c50dd2c3f37003)
  contains lock-file changes only. This sync does not replace shell behavior or
  remove any local feature.
- Keep the local Display page, mirroring, fractional scaling and monitor restart
  handling. Upstream display PR #2293 is not part of this upstream revision.
- Keep the Bluetooth `wpctl` workaround. Quickshell #808 has since merged, but
  replacing the workaround still needs a Bluetooth device test of slider,
  scroll and mute behavior on the user's runtime. No hardware test is claimed.
- Local checks: 61 Python tests ran successfully with 7 skipped (graphical or
  optional-runtime tests); all personal shell scripts passed `bash -n` and
  `git diff --check` passed. Nix and the Qt/Quickshell build environment are not
  installed in this check environment; build verification is left to PR CI.
- Translation validation still reports six existing `qsTr()` uses in
  `components/games/DinoGame.qml`, unchanged by the merge. This check must not be
  bypassed to merge the sync. QML lint/format baseline failures are also outside
  this lock-only change; the repository's path filters skip them on this PR.

The sections below record the original September integration, not current CI
results or current branch names.

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

Thirteen updater regression tests cover Git conflict handling, retained local history, failed saves,
failed builds/launches, atomic selection, and legacy linked-worktree migration.
GitHub CI uses a fork-owned Arch image because the upstream image denied access.

The first real activation exposed Quickshell emitting a plain-text empty-list message despite --json. The manager now handles that output explicitly, rejects unknown output, and restores the old shell even if stopping it fails midway. Regression coverage includes these cases.

A real headless Quickshell transaction test verifies activation and rollback through the stable configuration symlink. Process selection uses that alias, not the resolved release directory. Shutdown holds Linux pidfds and has bounded graceful/forced stages, avoiding stale PID reuse and indefinite waits in a stuck Quickshell shutdown. The runtime test is also enabled in the fork-owned CI container.
