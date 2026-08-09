# dgpu-status

Shows whether the discrete NVIDIA GPU is powered up, and — only while it already is — its
temperature, load, power draw, VRAM and the processes using it.

## The point of this plugin

On a Max-Q / hybrid laptop the dGPU spends most of its life runtime-suspended in D3cold. Every
obvious way to inspect it wakes it up:

- `nvidia-smi` — resumes the device
- `/proc/driver/nvidia/gpus/*/power` — resumes the device
- the PCI `power_state` attribute — resumes the device

A monitor that wakes the thing it monitors costs several watts of battery for as long as the
runtime-PM idle timer takes to put it back to sleep. So the polling loop here reads exactly one
file:

```
/sys/bus/pci/devices/<addr>/power/runtime_status
```

That is a variable inside the kernel's `struct dev_pm_info`, not a device access — reading it does
not resume anything. `nvidia-smi` runs **only** when that file already says `active`, and stops the
instant it stops saying so.

There is one deliberate exception: the **Wake GPU and read stats** button in the panel, which is
labelled as such. Waking the GPU should be something you choose, not a side effect of opening a
panel.

### Relationship to Noctalia's built-in setting

Settings → System → System Monitor has **Enable discrete GPU monitoring**, with a warning that it
wakes the dGPU. It does: once enabled, `SystemStatService` runs

```
nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits
```

every 5 seconds unconditionally (`gpuIntervalMs: 5000`, `SystemStatService.qml:38` / `:1489`) with
no check of `runtime_status`. It also only reads temperature.

**Leave that setting off while using this plugin.** With both enabled they fight: the built-in's
5 s loop holds the GPU awake, `runtime_status` never leaves `active`, and this plugin's gate — the
entire point of it — becomes meaningless.

### Back-off

"Active" doesn't mean "busy" — the GPU can be awake and idle at 3 W. After three consecutive
samples with no processes and 0% utilisation, the `nvidia-smi` cadence drops from
`activeIntervalSec` (5 s) to `idleIntervalSec` (30 s), so the queries themselves are less likely to
keep the device from reaching its own idle threshold. The panel says when this is in effect.

## Install

```fish
ln -s /mnt/SSD2/Projects/noctalia-plugins/dgpu-status ~/.config/noctalia/plugins/dgpu-status
```

Restart the shell (or toggle the plugin in Settings → Plugins → Installed), then add the widget in
Settings → Bar.

## Keybind (optional)

```
bind = SUPER, G, exec, qs -c noctalia-shell ipc call plugin:dgpu-status toggle
```

`qs -c noctalia-shell ipc call plugin:dgpu-status status` prints the current state as JSON and does
**not** wake the GPU — it only reports what the plugin already knows. `wakeAndSample` is the
explicit opposite.

## Detection

The PCI address is auto-detected by scanning `/sys/bus/pci/devices/*/` for a device with vendor
`0x10de` and a VGA/3D class that exposes `power/runtime_status`. `vendor` and `class` are served
from the kernel's cached copy of the PCI config header, so detection is also safe against a
suspended GPU. On this machine that resolves to `0000:01:00.0` (RTX 5060 Max-Q); the address can be
pinned in settings if it ever renumbers.

## Settings

- **Hide widget when suspended** — drop the capsule entirely while the GPU sleeps.
- **Show temperature in the bar** — otherwise utilisation percentage.
- **Power state interval** (2–30 s) — free, never touches the GPU.
- **Stats interval, active** (5–60 s) — nvidia-smi cadence while awake. 5 s floor is enforced in
  code.
- **Stats interval, awake but idle** (10–300 s) — the backed-off cadence.
- **PCI address** — blank to auto-detect.

## Known limitations / notes

- Process rows come from parsing the `Processes:` table of plain `nvidia-smi` output.
  `--query-compute-apps` would be cleaner but only reports compute (type C) clients and would miss
  games, which are graphics (type G) clients — the main thing worth seeing on this laptop.
- `fan.speed` reports `[N/A]` on this GPU, so it isn't shown.
- One thing that hasn't been measured: whether a 5 s `nvidia-smi` loop on an otherwise-idle awake
  GPU is itself enough to defer the runtime-PM idle timer. The back-off exists because that risk is
  real, not because it has been quantified. If you see the GPU staying awake longer than it used
  to, raise both intervals.
