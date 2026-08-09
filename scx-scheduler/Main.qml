import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Persistent background object for the scx-scheduler plugin.
//
// Owns all communication with scx_loader (the D-Bus service that loads
// sched-ext BPF schedulers) and exposes the current state to BarWidget.qml
// and Panel.qml through pluginApi.mainInstance.
//
// Two backends are used, deliberately:
//
//   * READS go through `busctl get-property` on org.scx.Loader. The service's
//     D-Bus policy (/usr/share/dbus-1/system.d/org.scx.Loader.conf) allows
//     org.freedesktop.DBus.Properties.Get for the default context, so reads
//     never prompt for authentication. `scxctl get` is read alongside it
//     purely to recover the *mode name* ("Auto", "Gaming", ...) — the
//     SchedulerMode D-Bus property is a bare uint whose numeric mapping is
//     not documented anywhere on disk, so we do not guess at it.
//
//   * WRITES go through `scxctl`, which speaks the same D-Bus interface but
//     already knows the mode-name -> enum mapping. Those methods are gated by
//     the polkit action org.scx.loader.manage-schedulers, whose default is
//     auth_admin_keep: the FIRST switch of a session pops a graphical polkit
//     prompt, later ones do not. A cancelled prompt makes scxctl exit
//     non-zero, which is why every action refreshes state afterwards instead
//     of optimistically assuming it succeeded.
Item {
  id: root

  property var pluginApi: null

  // --- Public state (read by BarWidget / Panel) ----------------------------

  // Running scheduler, in the canonical scx_loader form ("scx_lavd").
  // Empty string means no sched-ext scheduler is loaded, i.e. the kernel's
  // own scheduler (EEVDF) is in charge. scx_loader reports that state as the
  // literal string "unknown", which is translated away here so no consumer
  // ever has to know about that sentinel.
  property string currentScheduler: ""

  // Human mode name as printed by `scxctl get` ("Auto", "Gaming", ...).
  // Empty when nothing is running or when the output could not be parsed.
  property string currentMode: ""

  // Every scheduler scx_loader is willing to start, canonical form.
  property var supportedSchedulers: []

  // The scheduler configured as the boot default in /etc/scx_loader.toml.
  // Empty when no config file exists, which is the stock state — nothing is
  // loaded at boot and "Restore" has nothing to fall back to.
  property string defaultScheduler: ""

  // Bumped on every completed state refresh so bindings re-evaluate even
  // when an array is mutated in place.
  property int revision: 0

  // True while an action (start/switch/stop/restore) is in flight. The panel
  // disables its buttons on this so a slow polkit prompt cannot be
  // double-submitted.
  property bool busy: false

  // Last action failure, shown in the panel. Cleared at the start of every
  // action. A cancelled polkit prompt lands here.
  property string lastError: ""

  // False when scx_loader is not reachable at all (service masked, package
  // removed). The panel renders an explanatory empty state instead of a
  // scheduler list.
  property bool loaderAvailable: true

  readonly property bool schedulerRunning: currentScheduler !== ""

  // Short display form: "scx_lavd" -> "lavd".
  function shortName(name) {
    if (!name)
      return "";
    return name.indexOf("scx_") === 0 ? name.substring(4) : name;
  }

  // --- Settings ------------------------------------------------------------

  readonly property var cfg: pluginApi?.pluginSettings || ({})
  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})
  readonly property int pollIntervalSec: cfg.pollIntervalSec ?? defaults.pollIntervalSec ?? 5

  // --- State refresh -------------------------------------------------------

  // One shell invocation produces everything we need, separated by a marker:
  //
  //   <scxctl get output>
  //   @@SEP@@
  //   {"type":"s","data":"scx_lavd"}      <- CurrentScheduler
  //   {"type":"as","data":["scx_...",...]} <- SupportedSchedulers
  //
  // Both halves are allowed to fail independently; the parser treats missing
  // sections as "no information" rather than as an error.
  readonly property string refreshCommand: "scxctl get 2>/dev/null; printf '\\n@@SEP@@\\n'; busctl --system get-property --json=short org.scx.Loader /org/scx/Loader org.scx.Loader CurrentScheduler DefaultScheduler SupportedSchedulers 2>/dev/null"

  Process {
    id: refreshProc
    command: ["sh", "-c", root.refreshCommand]
    stdout: StdioCollector {
      id: refreshOut
    }
    onExited: root._parseState(refreshOut.text)
  }

  function refresh() {
    if (refreshProc.running)
      return;
    refreshProc.running = true;
  }

  function _parseState(out) {
    const text = out || "";
    const parts = text.split("@@SEP@@");
    const scxctlOut = parts[0] || "";
    const busctlOut = parts.length > 1 ? parts[1] : "";

    // --- D-Bus half: authoritative for the scheduler names and the list.
    //
    // busctl prints one JSON object per requested property, in the order they
    // were asked for, so these are read positionally rather than by type —
    // CurrentScheduler and DefaultScheduler are both plain strings and would
    // otherwise be indistinguishable.
    const values = [];
    const lines = busctlOut.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line === "")
        continue;
      try {
        values.push(JSON.parse(line).data);
      } catch (e) {
        continue;
      }
    }

    const dbusCurrent = values.length > 0 ? values[0] : null;
    const dbusDefault = values.length > 1 ? values[1] : null;
    const dbusSupported = values.length > 2 ? values[2] : null;

    root.loaderAvailable = values.length > 0;

    // "unknown" here means no default is configured — scx_loader reads it from
    // /etc/scx_loader.toml, which does not exist on a stock install. Without
    // one there is nothing for "Restore" to restore, and the panel says so.
    root.defaultScheduler = (dbusDefault === null || dbusDefault === "unknown" || dbusDefault === "none") ? "" : dbusDefault;

    if (dbusSupported !== null) {
      const sorted = dbusSupported.slice().sort();
      root.supportedSchedulers = sorted;
    }

    if (dbusCurrent !== null) {
      // "unknown" is scx_loader's way of saying "nothing loaded".
      root.currentScheduler = (dbusCurrent === "unknown" || dbusCurrent === "none") ? "" : dbusCurrent;
    } else if (/no scx scheduler running/i.test(scxctlOut)) {
      root.currentScheduler = "";
    }

    // --- scxctl half: only used for the mode name.
    //
    // The exact phrasing of `scxctl get` is not a stable contract, so this
    // looks for any of the five mode names scxctl itself accepts rather than
    // matching a fixed sentence shape. If the wording changes upstream we
    // lose the mode label and nothing else.
    if (root.currentScheduler === "") {
      root.currentMode = "";
    } else {
      const m = scxctlOut.match(/\b(auto|gaming|powersave|lowlatency|server)\b/i);
      root.currentMode = m ? (m[1].charAt(0).toUpperCase() + m[1].substring(1).toLowerCase()) : "";
    }

    root.revision++;
  }

  Timer {
    interval: Math.max(2, root.pollIntervalSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // --- Actions -------------------------------------------------------------

  // scxctl validates both --sched and --mode client-side, so a typo fails
  // fast without touching the running system.
  Process {
    id: actionProc
    stderr: StdioCollector {
      id: actionErr
    }
    onExited: exitCode => {
      root.busy = false;
      const err = (actionErr.text || "").trim();
      if (exitCode !== 0 && err !== "")
        root.lastError = err;
      if (exitCode !== 0 && root.lastError === "") {
        // Cancelled polkit prompts frequently exit non-zero with nothing on
        // stderr; give the user something better than silence.
        root.lastError = root.pluginApi?.tr("errors.action-failed") ?? "Action failed";
      }
      // Always read the real state back — never assume the action took.
      root.refresh();
    }
  }

  function _runAction(args) {
    if (root.busy)
      return;
    root.lastError = "";
    root.busy = true;
    actionProc.command = args;
    actionProc.running = true;
  }

  // Start `sched` if nothing is loaded, otherwise switch to it. mode is one
  // of auto|gaming|powersave|lowlatency|server.
  function applyScheduler(sched, mode) {
    if (!sched)
      return;
    const m = mode || root.cfg.defaultMode || "auto";
    const verb = root.schedulerRunning ? "switch" : "start";
    _runAction(["scxctl", verb, "-s", sched, "-m", m]);
  }

  // Change only the mode of the already-running scheduler.
  function applyMode(mode) {
    if (!root.schedulerRunning || !mode)
      return;
    _runAction(["scxctl", "switch", "-m", mode]);
  }

  // Unload sched-ext entirely; the kernel scheduler takes over again.
  function stopScheduler() {
    _runAction(["scxctl", "stop"]);
  }

  // Return to whatever /etc/scx_loader.toml declares as the default.
  function restoreDefault() {
    _runAction(["scxctl", "restore"]);
  }

  // --- Lifecycle -----------------------------------------------------------

  Component.onDestruction: {
    // Leave no orphaned children behind on shell reload / plugin unload.
    if (refreshProc.running)
      refreshProc.running = false;
    if (actionProc.running)
      actionProc.running = false;
  }

  // --- IPC -----------------------------------------------------------------
  //
  // Bindable from Hyprland, e.g.
  //   bind = SUPER, S, exec, qs -c noctalia-shell ipc call plugin:scx-scheduler toggle
  IpcHandler {
    target: "plugin:scx-scheduler"

    // Open/close the panel on the screen the cursor is on.
    function toggle() {
      root.pluginApi?.withCurrentScreen(screen => {
        root.pluginApi?.togglePanel(screen);
      });
    }

    // Switch without opening any UI: `... ipc call plugin:scx-scheduler switchTo scx_lavd gaming`
    function switchTo(sched: string, mode: string) {
      root.applyScheduler(sched, mode || "");
    }

    function stop() {
      root.stopScheduler();
    }

    function restore() {
      root.restoreDefault();
    }

    // Machine-readable state for scripts and status bars.
    function status(): string {
      return JSON.stringify({
        "scheduler": root.currentScheduler,
        "mode": root.currentMode,
        "running": root.schedulerRunning
      });
    }
  }
}
