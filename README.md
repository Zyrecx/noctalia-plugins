# noctalia-plugins

Plugins for [Noctalia](https://github.com/noctalia-dev/noctalia-shell) v5.

| Plugin | What it does |
|---|---|
| [`run-path`](run-path/) | Type a path in the launcher to open it, with live completion, or type anything else to run it |
| [`nothing-ear`](nothing-ear/) | Battery, noise control, EQ and auto mono audio for Nothing and CMF earbuds, over Bluetooth |

Each folder has its own README.

Looking for the Noctalia v4 (QML) plugins, including `scx-scheduler` and `dgpu-status`? They're
on the [`v4` branch](https://github.com/Zyrecx/noctalia-plugins/tree/v4).

## Install

The easy way: install from **Settings → Plugins** if the plugin is in the
[community catalog](https://github.com/noctalia-dev/community-plugins).

From this repo: clone it and symlink the plugins you want into Noctalia's plugin directory.

```sh
git clone https://github.com/Zyrecx/noctalia-plugins.git ~/src/noctalia-plugins
ln -s ~/src/noctalia-plugins/run-path    ~/.local/share/noctalia/plugins/run-path
ln -s ~/src/noctalia-plugins/nothing-ear ~/.local/share/noctalia/plugins/nothing-ear
```

Then enable them in **Settings → Plugins**.

## License

MIT, see [LICENSE](LICENSE).
