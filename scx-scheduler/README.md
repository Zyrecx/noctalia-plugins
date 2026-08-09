# scx-scheduler

Switch [sched-ext](https://github.com/sched-ext/scx) CPU schedulers from the Noctalia bar.

`sched_ext` is a kernel framework that lets a CPU scheduler be loaded as a BPF program while the
system runs — no reboot, no kernel parameter. CachyOS ships the whole `scx` suite, so the machine
has a dozen alternative schedulers installed that are normally only reachable from a terminal.
This plugin puts them one click away: it shows which scheduler is loaded, lets you start, switch,
stop or restore one, and picks the mode (`auto`, `gaming`, `lowlatency`, `powersave`, `server`)
it runs in.

## Requirements

- `scx-tools` installed and the `scx_loader` service running:
  ```
  systemctl status scx_loader
  ```
  If it is not enabled: `systemctl enable --now scx_loader`
- A polkit authentication agent. Switching is gated by the polkit action
  `org.scx.loader.manage-schedulers`, whose default policy is `auth_admin_keep`: the **first**
  switch after login pops a graphical password prompt, later ones reuse it. No `sudo` needed.

Reading state needs no authentication at all — the D-Bus policy allows `Properties.Get` for
everyone.

## Install

```fish
ln -s /mnt/SSD2/Projects/noctalia-plugins/scx-scheduler ~/.config/noctalia/plugins/scx-scheduler
```

Then restart the shell (or toggle the plugin off/on in Settings → Plugins → Installed) and add the
widget to the bar in Settings → Bar.

## Keybinds

```
# Open/close the panel
bind = SUPER, S, exec, qs -c noctalia-shell ipc call plugin:scx-scheduler toggle

# Jump straight to a scheduler, no UI
bind = SUPER SHIFT, G, exec, qs -c noctalia-shell ipc call plugin:scx-scheduler switchTo scx_lavd gaming
bind = SUPER SHIFT, S, exec, qs -c noctalia-shell ipc call plugin:scx-scheduler stop
```

`qs -c noctalia-shell ipc call plugin:scx-scheduler status` prints the current state as JSON, which
is handy for scripts.

## How it works

Reads and writes deliberately use different backends:

| | backend | why |
|---|---|---|
| read state | `busctl get-property org.scx.Loader …` | structured JSON, never prompts for auth |
| read mode name | `scxctl get` | the `SchedulerMode` D-Bus property is a bare `uint` whose numeric mapping isn't documented on disk, so the name is parsed from `scxctl` instead of guessed |
| start/switch/stop/restore | `scxctl` | already knows the mode-name → enum mapping, and handles the polkit round-trip |

Every action re-reads the real state when it finishes, so a cancelled authentication prompt leaves
the UI showing what is actually loaded rather than what you asked for. Failures surface on the
error line at the bottom of the panel.

## Manual test

Nothing here has been exercised against a live switch — verifying it changes the running scheduler
on your machine and pops an auth prompt is yours to do:

```fish
scxctl get                  # before
scxctl switch -s scx_lavd -m gaming
scxctl get                  # after
scxctl stop                 # back to the kernel scheduler
```

The panel should track each of those within one refresh interval (5 s by default).

## Persistence

Switching a scheduler from this panel lasts until you stop it or reboot — nothing here writes
config. `scx_loader.service` is D-Bus activated and ships `disabled`, and there is no
`/etc/scx_loader.toml` on a stock CachyOS install, so `DefaultScheduler` reads `unknown` and the
**Restore** button is greyed out (its tooltip says why).

To make one load at boot, create `/etc/scx_loader.toml`:

```toml
default_sched = "scx_lavd"
default_mode = "Auto"
```

and `systemctl enable --now scx_loader`. Restore then becomes useful, and the panel picks the
default up on its next refresh.

## Settings

- **Show scheduler name in the bar** — icon only, or icon + `lavd`.
- **Label when stopped** — what the bar shows when no sched-ext scheduler is loaded.
- **Default mode** — pre-selected mode when the panel opens.
- **Refresh interval** — 2–60 s.

Bar text/icon colours are read from `activeColor` / `textColor` / `iconColor` in
`settings.json` but have no UI yet; edit the file directly if you want to change them.

## Known limitations

- Polls instead of subscribing to `PropertiesChanged`. The signal exists (all the properties are
  `emits-change`) and would remove the poll entirely — good v2 change.
- Scheduler descriptions in the panel only cover the six schedulers whose purpose is well
  established upstream. The rest render without a subtitle rather than with an invented one.
