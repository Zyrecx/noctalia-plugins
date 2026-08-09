import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Background object for the dGPU status plugin.
//
// THE ONE RULE THIS PLUGIN EXISTS TO RESPECT: never touch the GPU while it is
// runtime-suspended.
//
// On a Max-Q / hybrid laptop the discrete GPU spends most of its life in
// D3cold. Anything that reaches the device — `nvidia-smi`, reading
// /proc/driver/nvidia/gpus/*/power, reading the PCI `power_state` attribute —
// resumes it, which costs several watts of battery for as long as the runtime-
// PM idle timer takes to put it back to sleep. A monitor that wakes the thing
// it is monitoring is worse than no monitor.
//
// So the polling loop reads exactly one file:
//
//     /sys/bus/pci/devices/<addr>/power/runtime_status
//
// That is a PM-core variable inside the kernel's struct dev_pm_info. Reading it
// is not a device access and does not resume anything. Only when it reads
// "active" — meaning something else already woke the GPU — does this plugin
// run `nvidia-smi` for the detailed numbers.
//
// While active but idle (no processes, no load) the nvidia-smi cadence backs
// off to idleIntervalSec, so the queries themselves are less likely to keep the
// device from reaching its own idle threshold.
Item {
  id: root

  property var pluginApi: null

  // --- Settings ------------------------------------------------------------

  readonly property var cfg: pluginApi?.pluginSettings || ({})
  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  readonly property string configuredAddress: cfg.pciAddress ?? defaults.pciAddress ?? ""
  readonly property int statusIntervalSec: Math.max(2, cfg.statusIntervalSec ?? defaults.statusIntervalSec ?? 3)
  // Floor of 5 s is deliberate: a faster nvidia-smi loop is measurably more
  // likely to hold the GPU awake.
  readonly property int activeIntervalSec: Math.max(5, cfg.activeIntervalSec ?? defaults.activeIntervalSec ?? 5)
  readonly property int idleIntervalSec: Math.max(10, cfg.idleIntervalSec ?? defaults.idleIntervalSec ?? 30)

  // --- Device resolution ---------------------------------------------------

  // Resolved PCI address, e.g. "0000:01:00.0". Empty until detection finishes.
  property string pciAddress: ""

  // Set when no NVIDIA VGA device could be found at all.
  property bool deviceFound: true

  readonly property string statusPath: pciAddress !== "" ? "/sys/bus/pci/devices/" + pciAddress + "/power/runtime_status" : ""

  // Device detection reads only `vendor` and `class`. Both are served from the
  // kernel's cached copy of the PCI config header (struct pci_dev), not from
  // the device, so this is safe against a suspended GPU.
  Process {
    id: detectProc
    command: ["sh", "-c", "for d in /sys/bus/pci/devices/*/; do v=$(cat \"$d/vendor\" 2>/dev/null); c=$(cat \"$d/class\" 2>/dev/null); case \"$c\" in 0x0300*|0x0302*) [ \"$v\" = \"0x10de\" ] && [ -r \"$d/power/runtime_status\" ] && basename \"$d\";; esac; done"]
    stdout: StdioCollector {
      id: detectOut
    }
    onExited: {
      const found = (detectOut.text || "").split("\n").filter(l => l.trim() !== "");
      if (found.length > 0) {
        root.pciAddress = found[0].trim();
        root.deviceFound = true;
        Logger.i("dgpu-status", "Using NVIDIA device at " + root.pciAddress);
      } else {
        root.deviceFound = false;
        Logger.w("dgpu-status", "No NVIDIA VGA device with runtime PM found");
      }
    }
  }

  function detectDevice() {
    if (root.configuredAddress !== "") {
      root.pciAddress = root.configuredAddress;
      root.deviceFound = true;
      return;
    }
    if (!detectProc.running)
      detectProc.running = true;
  }

  Component.onCompleted: root.detectDevice()

  // Re-resolve if the user edits the address in settings.
  onConfiguredAddressChanged: root.detectDevice()

  // --- Runtime power state -------------------------------------------------

  // One of: "active", "suspended", "suspending", "resuming", "unsupported", "".
  property string runtimeStatus: ""
  readonly property bool isActive: runtimeStatus === "active"
  readonly property bool isSuspended: runtimeStatus === "suspended"

  // Bumped whenever anything a consumer might render has changed.
  property int revision: 0

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: false     // sysfs does not deliver inotify events
    printErrors: false

    onLoaded: {
      const value = String(statusFile.text()).trim();
      if (value !== root.runtimeStatus) {
        root.runtimeStatus = value;
        if (!root.isActive)
          root._clearLiveStats();
        root.revision++;
      }
    }
  }

  Timer {
    interval: root.statusIntervalSec * 1000
    running: root.statusPath !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: statusFile.reload()
  }

  // --- Detailed stats (only while active) ----------------------------------

  property string gpuName: ""
  property int temperatureC: -1
  property int utilizationPct: -1
  property int memUsedMiB: -1
  property int memTotalMiB: -1
  property real powerDrawW: -1
  property var processes: []          // [{ pid, type, name, memory }]
  property double lastSampleAt: 0
  property bool smiAvailable: true

  // Consecutive samples that found nothing running on the GPU. After three of
  // them the sampler backs off to idleIntervalSec.
  property int idleSamples: 0
  readonly property bool backedOff: idleSamples >= 3

  function _clearLiveStats() {
    root.temperatureC = -1;
    root.utilizationPct = -1;
    root.memUsedMiB = -1;
    root.memTotalMiB = -1;
    root.powerDrawW = -1;
    root.processes = [];
    root.idleSamples = 0;
  }

  // Two invocations in one shell: the CSV query for the scalars, then the
  // human-readable table for the process list. --query-compute-apps alone
  // would miss graphics clients (type G), which on a gaming laptop is exactly
  // what you want to see.
  Process {
    id: smiProc
    command: ["sh", "-c", "nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits 2>/dev/null; printf '@@SEP@@\\n'; nvidia-smi 2>/dev/null"]
    stdout: StdioCollector {
      id: smiOut
    }
    onExited: exitCode => {
      if (exitCode === 0) {
        root.smiAvailable = true;
        root._parseSample(smiOut.text);
      } else {
        // nvidia-smi missing or refusing to talk: stop the sampler rather
        // than retrying every few seconds forever.
        root.smiAvailable = false;
        root.revision++;
      }
    }
  }

  function sampleNow() {
    if (smiProc.running)
      return;
    smiProc.running = true;
  }

  function _num(s) {
    const v = parseFloat(String(s).trim());
    return isNaN(v) ? -1 : v;
  }

  function _parseSample(out) {
    const text = out || "";
    const halves = text.split("@@SEP@@");
    const csv = (halves[0] || "").trim();
    const table = halves.length > 1 ? halves[1] : "";

    if (csv !== "") {
      root.smiAvailable = true;
      // name may itself contain commas in principle; the six fields we ask
      // for are positional from the right, so split and read from the end.
      const parts = csv.split("\n")[0].split(",");
      if (parts.length >= 6) {
        const n = parts.length;
        root.powerDrawW = root._num(parts[n - 1]);
        root.memTotalMiB = root._num(parts[n - 2]);
        root.memUsedMiB = root._num(parts[n - 3]);
        root.utilizationPct = root._num(parts[n - 4]);
        root.temperatureC = root._num(parts[n - 5]);
        root.gpuName = parts.slice(0, n - 5).join(",").trim();
      }
    }

    root.processes = root._parseProcesses(table);

    // Back-off bookkeeping: "nothing is happening" means no clients and no
    // load. Power draw is not used here — an idle-but-awake GPU still draws a
    // few watts.
    const quiet = root.processes.length === 0 && root.utilizationPct <= 0;
    root.idleSamples = quiet ? Math.min(root.idleSamples + 1, 99) : 0;

    root.lastSampleAt = Date.now();
    root.revision++;
  }

  // Parses the trailing "Processes:" table of plain `nvidia-smi` output. Rows
  // look like:
  //   |    0   N/A  N/A     4242      G   /usr/bin/foo                 123MiB |
  function _parseProcesses(table) {
    const lines = String(table).split("\n");
    let inSection = false;
    let pastHeader = false;
    const out = [];

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (!inSection) {
        if (line.indexOf("Processes:") >= 0)
          inSection = true;
        continue;
      }
      if (!pastHeader) {
        // The "|=====|" rule separates the column headers from the rows.
        if (line.indexOf("|=") === 0)
          pastHeader = true;
        continue;
      }
      if (line.indexOf("+--") === 0)
        break;
      if (line.indexOf("|") !== 0)
        continue;
      if (line.indexOf("No running processes found") >= 0)
        break;

      const fields = line.replace(/\|/g, " ").trim().split(/\s+/);
      // gpu gi ci pid type name... memory
      if (fields.length < 6)
        continue;
      const pid = fields[3];
      const type = fields[4];
      const memory = fields[fields.length - 1];
      const name = fields.slice(5, fields.length - 1).join(" ");
      if (!/^\d+$/.test(pid))
        continue;

      out.push({
        "pid": pid,
        "type": type,
        "name": name,
        "memory": memory
      });
    }
    return out;
  }

  Timer {
    id: smiTimer
    interval: (root.backedOff ? root.idleIntervalSec : root.activeIntervalSec) * 1000
    // Stops the instant the GPU leaves the active state. This is the whole
    // point of the plugin.
    running: root.isActive && root.smiAvailable && root.pciAddress !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sampleNow()
  }

  // --- Lifecycle -----------------------------------------------------------

  Component.onDestruction: {
    if (smiProc.running)
      smiProc.running = false;
    if (detectProc.running)
      detectProc.running = false;
  }

  // --- IPC -----------------------------------------------------------------

  IpcHandler {
    target: "plugin:dgpu-status"

    function toggle() {
      root.pluginApi?.withCurrentScreen(screen => {
        root.pluginApi?.togglePanel(screen);
      });
    }

    // Machine-readable state. Reports only what is already known — calling
    // this while the GPU is suspended does NOT wake it.
    function status(): string {
      return JSON.stringify({
        "address": root.pciAddress,
        "runtimeStatus": root.runtimeStatus,
        "active": root.isActive,
        "temperatureC": root.temperatureC,
        "utilizationPct": root.utilizationPct,
        "powerDrawW": root.powerDrawW,
        "processes": root.processes.length
      });
    }

    // Explicit, user-initiated query. WILL resume a suspended GPU — it is
    // exposed so that is a deliberate act, never a side effect of polling.
    function wakeAndSample() {
      root.sampleNow();
    }
  }
}
