# Omarchy plugin authoring review

Checked against the official `omacom/omarchy` `quattro` documentation and the
installed Omarchy 4.5.0 shell on 2026-11-07. Upstream branch links can change;
the supported versions in this project's README describe what was actually
tested, rather than a promise about all Omarchy releases.

## Distribution and manifest

Keep `manifest.json` at the repository root. Users install a published Git URL
with `omarchy plugin add URL --enable`; subsequent plugin updates fast-forward
that checkout. Omarchy does not execute plugin install hooks or `install.sh`,
and does not install runtime packages. Therefore the setup panel and README
must explain dependency installation explicitly. A copy installer can remain
an optional local development path. [Official plugin user guide](https://github.com/omacom/omarchy/blob/quattro/manual/32-shell-plugins.md)

Use schema version **number** `1`, a non-reserved namespaced ID, name, version,
kinds, and an entry point for each declared kind. The existing
`user.phone-display` ID is valid; `omarchy.*` is reserved. Keep entry points
relative, and do not ship symlinks. Run `omarchy plugin validate .` before
publication and after installation. The validator intentionally skips Git's
internal directory while rejecting plugin-content symlinks.
[Official validator](https://github.com/omacom/omarchy/blob/quattro/bin/omarchy-plugin-validate)

## Shell integration

Run as an `Item` within the existing shell. The normal widget base supplies
`bar`, `moduleName`, and `settings`; `allowMultiple: false` does not prevent
one widget instance being constructed per monitor. Ordinary third-party code
receives scoped APIs, so use its own lifecycle/settings methods rather than
traversing host objects. Preferences belong inline on the widget entry in
`shell.json`. [Shell reference](https://github.com/omacom/omarchy/blob/quattro/docs/omarchy-shell.md),
[widget base](https://github.com/omacom/omarchy/blob/quattro/shell/Ui/BarWidget.qml),
[scoped settings API](https://github.com/omacom/omarchy/blob/quattro/shell/services/PluginShellApi.qml)

Build the popup with `KeyboardPanel`, anchor it to the bar button, and use the
host widget as its popout owner. Keep popup content lazy with `content:` and
handle keyboard dismissal/navigation. The shared component already handles
bar placement, available screen size, focus, dismissal, and popup animation.
[KeyboardPanel implementation](https://github.com/omacom/omarchy/blob/quattro/shell/Ui/KeyboardPanel.qml)

Execute backend operations through `Quickshell.Io.Process`, passing each
argument as a separate array element and collecting completion/errors through
its signals. This avoids shell quoting for user values and keeps work outside
the QML event loop. [Quickshell Process API](https://quickshell.org/docs/v0.2.1/types/Quickshell.Io/Process/)

## Resource use and UI safety

Prefer event streams, native signals, file watches, or explicit refreshes over
timers spawning processes. Polling from every monitor's widget multiplies
the work. Where a probe has no usable change event, gate it on an open panel
or active phone session, use a shared owner where possible, and document the
interval. Phone orientation is an example of an external state probe that
may require a bounded active-session poll.
[Official shell development guidance](https://github.com/omacom/omarchy/blob/quattro/agents/skills/shell-dev.md)

Use `Commons.Color` for theme colors, avoiding the Qt `Color` name collision.
Store plugin strings in `i18n/en.json` and read them with
`Commons.Translations`; English fallback is supported. Respect reduced motion
with `Style.duration`. Treat backend output, device names, and settings as
untrusted: bound parsed values and display them with `Text.PlainText`.
Shell-owned tooltip sinks need either static trusted strings or explicit
sanitization and regression coverage. A monitor map represents physical
coordinates, so its geometry must stay spatially accurate in RTL locales;
surrounding controls can mirror normally.
[Theme reference](https://github.com/omacom/omarchy/blob/quattro/docs/omarchy-shell.md#theme-tokens),
[official plugin customization and safety guidance](https://github.com/omacom/omarchy/blob/quattro/default/agents/skills/omarchy/plugins.md)

## Repository acceptance checks

Project-specific release checks, in addition to the upstream manifest check:

- Keep install commands relative or use the native Git plugin installer; remove
  workstation-specific paths from reusable instructions.
- Ignore caches, runtime state, logs, screenshots, device IDs, and local backups.
- Test lifecycle rollback, process ownership, geometry, rotation parsing,
  drag-to-coordinate conversion, and malformed output at their boundaries.
- Check QML in the supported installed shell; a valid manifest does not prove
  that imports, popup focus, or asynchronous operations work.
- Document USB debugging, authorization, AVNC setup, manual/automatic rotation,
  known capture limitations, and what remains unmeasured on real hardware.
- Keep package installation an explicit user action. Loading a plugin should
  not silently elevate privileges or execute downloaded installation scripts.
