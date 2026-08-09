# noctalia-plugins

Three plugins for [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell) 4.7.7, written
for this machine (CachyOS + Hyprland, RTX 5060 Max-Q + AMD iGPU).

| Plugin | What it does | Entry points |
|---|---|---|
| [`scx-scheduler`](scx-scheduler/) | Switch sched-ext CPU schedulers from the bar | main, barWidget, panel, settings |
| [`run-path`](run-path/) | `Super+R` prompt: type a path to open it, or anything else to run it | main, launcherProvider, settings |
| [`dgpu-status`](dgpu-status/) | dGPU power state + stats, without ever waking a sleeping GPU | main, barWidget, panel, settings |

Each folder has its own README with install, keybinds and design notes.

## Install all three

They are already symlinked into the shell's plugin directory:

```fish
ln -sfn /mnt/SSD2/Projects/noctalia-plugins/scx-scheduler ~/.config/noctalia/plugins/scx-scheduler
ln -sfn /mnt/SSD2/Projects/noctalia-plugins/run-path      ~/.config/noctalia/plugins/run-path
ln -sfn /mnt/SSD2/Projects/noctalia-plugins/dgpu-status   ~/.config/noctalia/plugins/dgpu-status
```

Symlinks work because the shell enumerates plugins with `for d in .../*/` plus a `[ -d "$d" ]`
test, both of which follow symlinks. A plugin update or uninstall through the GUI would only remove
the link, not this source tree — but don't uninstall through the GUI anyway, since these plugins
aren't in any registry.

**A shell restart is required after adding a plugin directory.** `PluginRegistry.scanPluginFolder()`
runs only at startup (`PluginRegistry.qml:134`), and nothing in the UI rescans the folder — the
refresh button on the Installed tab checks the git registry for updates, not the disk. Restart with:

```fish
qs kill -c noctalia-shell; sleep 1; qs -c noctalia-shell -d
```

A newly discovered plugin defaults to **disabled** (`PluginRegistry.isPluginEnabled` returns false
for anything with no saved state), so nothing loads until you switch it on in
**Settings → Plugins → Installed**.

To remove one: `rm ~/.config/noctalia/plugins/<name>` — that deletes the symlink only.

## Status

What has been verified: the shell commands each plugin runs (executed directly), the output
parsers (standalone JS harness, including a synthetic `nvidia-smi` process table), QML syntax
(`qmllint`), and that the shell's plugin scan discovers the symlinks.

**Not yet verified: whether the entry points actually instantiate inside the running shell.**
Enable them **one at a time** in Settings → Plugins → Installed and check that tab for an error
badge after each — `PluginService` records load errors per entry point and the Installed tab shows
them. Enabling all three at once makes a failure ambiguous about which plugin caused it.

If a panel's list renders collapsed or the panel mis-sizes on first open, look at the
`NScrollView { ColumnLayout { width: parent.width } }` blocks in `scx-scheduler/Panel.qml` and
`dgpu-status/Panel.qml`: `ScrollView` reparents its child, and setting `contentWidth:
availableWidth` on the NScrollView is the usual fix.

## Developing

Turn on debug mode in Noctalia's settings and `PluginService` will watch each plugin directory and
hot-reload on save. Two caveats:

- This tree is on an **ntfs3** mount, and `FileView`'s change watcher relies on inotify. If saves
  don't trigger a reload, that's why — toggle the plugin off and on in Settings instead.
- Hot reload re-instantiates entry points; it does not re-read `manifest.json` defaults into an
  existing `settings.json`. After changing `metadata.defaultSettings`, delete
  `~/.config/noctalia/plugins/<name>/settings.json` and reload.

`qmllint <file>.qml` catches syntax errors. It cannot resolve the `qs.*` imports (the shell has no
`qmldir` files), so it won't catch a misspelled `Style.` token — those only show up at runtime in
the shell's log.

## House rules these follow

Taken from the shell's own plugin contracts and the `clipboard` reference plugin:

- Every `pluginApi` access is optional-chained; the shell injects it *after* instantiation.
- `??` fallbacks in `Settings.qml` are byte-identical to `metadata.defaultSettings` in the manifest.
- `Component.onDestruction` stops every `Process` so a shell reload leaves no orphans.
- Process output is read in `onExited` from a named `StdioCollector`, never from `this` inside
  `onStreamFinished` — the two signals have no guaranteed ordering.
- A revision counter is bumped on in-place array mutations, and consumers read it inside bindings,
  because QML does not re-evaluate bindings when an array is mutated in place.
- Bar widgets declare `property ShellScreen screen` with the type, and pass themselves as the
  `caller` to `openPanel(screen, this)` so the panel anchors to the widget instead of drifting to
  screen centre.
