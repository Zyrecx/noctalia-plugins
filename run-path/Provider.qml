import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Launcher provider for the `>r ` prefix.
//
// Two behaviours share one prefix, chosen by what the input looks like:
//
//   >r ~/Pictures/wall        path mode    — completes as you type; Enter opens
//                                            the directory in your file manager
//   >r btop                   command mode — Enter runs it via sh -c
//
// Path mode is decided by the first character (`/`, `~` or `.`); everything
// else is a command. An empty input lists your home directory, so `Super+R`
// followed by nothing useful still shows something to click.
//
// Directory listings come from `ls` in a background Process. getResults() is
// synchronous — it answers from a cache and asks the launcher to re-query
// (launcher.updateResults()) once the listing lands.
Item {
  id: root

  // Injected by the shell / LauncherCore.
  property var pluginApi: null
  property var launcher: null

  property string name: pluginApi?.tr("provider.name") ?? "Run / Open Path"

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string iconMode: Settings.data.appLauncher.iconMode
  readonly property bool useTabler: iconMode === "tabler"

  readonly property var cfg: pluginApi?.pluginSettings || ({})
  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})
  readonly property string fileManager: cfg.fileManager ?? defaults.fileManager ?? "xdg-open"
  readonly property string fileOpener: cfg.fileOpener ?? defaults.fileOpener ?? "xdg-open"
  readonly property bool showHidden: cfg.showHidden ?? defaults.showHidden ?? false
  readonly property int maxResults: cfg.maxResults ?? defaults.maxResults ?? 20

  // Purely a label. A Wayland shell cannot grab global hotkeys itself — the
  // compositor owns them — so this only tells the user which key they bound in
  // their Hyprland config. It shows up in the launcher's `>` command list,
  // which is the one place someone browsing the launcher would look.
  readonly property string keybindHint: cfg.keybindHint ?? defaults.keybindHint ?? ""

  // --- Directory listing cache --------------------------------------------
  //
  // dir -> { entries: ["name", "subdir/"], exists: bool, fetchedAt: ms }
  // Names of directories keep the trailing slash `ls -p` adds; that is also
  // how a typed path is classified without spawning a second `stat`.
  property var cache: ({})
  property string listingDir: ""
  readonly property int cacheTtlMs: 4000

  Process {
    id: lsProc
    stdout: StdioCollector {
      id: lsOut
    }
    // Everything is handled here rather than in onStreamFinished: the two
    // signals have no guaranteed order relative to each other, and the
    // handler needs `listingDir` to still be set. The collector's text is
    // fully populated by the time the process exits.
    onExited: exitCode => {
      // A non-zero exit means the directory is gone or unreadable; record
      // that so the UI can say so instead of showing a stale listing.
      root._onListing(exitCode === 0 ? lsOut.text : "", exitCode === 0);
      root.listingDir = "";
    }
  }

  function _onListing(text, ok) {
    const dir = root.listingDir;
    if (dir === "")
      return;
    const entries = (text || "").split("\n").filter(e => e !== "");
    const prev = root.cache[dir];
    const changed = !prev || prev.exists !== ok || JSON.stringify(prev.entries) !== JSON.stringify(entries);

    // Replace the object rather than mutating it so QML sees a new reference.
    const next = Object.assign({}, root.cache);
    next[dir] = {
      "entries": entries,
      "exists": ok,
      "fetchedAt": Date.now()
    };
    root.cache = next;

    if (changed && root.launcher && root.launcher.updateResults)
      root.launcher.updateResults();
  }

  function _shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'";
  }

  // Returns the cached record for `dir` (possibly null) and kicks off a
  // refresh when the cache is missing or stale.
  function _listing(dir) {
    const rec = root.cache[dir] ?? null;
    const stale = !rec || (Date.now() - rec.fetchedAt) > root.cacheTtlMs;
    if (stale && !lsProc.running) {
      root.listingDir = dir;
      const flags = root.showHidden ? "-1Ap" : "-1p";
      lsProc.command = ["sh", "-c", "ls " + flags + " -- " + root._shellQuote(dir) + " 2>/dev/null"];
      lsProc.running = true;
    }
    return rec;
  }

  // --- Path helpers --------------------------------------------------------

  function _expand(p) {
    if (p === "~")
      return root.home;
    if (p.indexOf("~/") === 0)
      return root.home + p.substring(1);
    if (p.indexOf("/") === 0)
      return p;
    // "." and ".." are resolved against $HOME — the launcher has no notion of
    // a current working directory.
    if (p === "." || p === "..")
      return root.home + "/" + p;
    if (p.indexOf("./") === 0 || p.indexOf("../") === 0)
      return root.home + "/" + p;
    return p;
  }

  function _looksLikePath(input) {
    return input.indexOf("/") === 0 || input.indexOf("~") === 0 || input.indexOf(".") === 0;
  }

  // Split an absolute path into the directory to list and the fragment being
  // completed. "/etc/ho" -> ["/etc/", "ho"];  "/etc/" -> ["/etc/", ""].
  function _split(abs) {
    const idx = abs.lastIndexOf("/");
    if (idx < 0)
      return [root.home + "/", abs];
    return [abs.substring(0, idx + 1), abs.substring(idx + 1)];
  }

  function _basename(p) {
    const trimmed = p.length > 1 && p.charAt(p.length - 1) === "/" ? p.substring(0, p.length - 1) : p;
    const idx = trimmed.lastIndexOf("/");
    return idx < 0 ? trimmed : trimmed.substring(idx + 1);
  }

  // Collapse $HOME back to ~ for display.
  function _pretty(p) {
    if (root.home !== "" && p.indexOf(root.home) === 0)
      return "~" + p.substring(root.home.length);
    return p;
  }

  // --- Actions -------------------------------------------------------------

  function _openInFileManager(path) {
    root.launcher?.closeImmediately();
    Qt.callLater(() => {
      Logger.d("run-path", "Opening directory: " + path);
      Quickshell.execDetached([root.fileManager, path]);
    });
  }

  function _openFile(path) {
    root.launcher?.closeImmediately();
    Qt.callLater(() => {
      Logger.d("run-path", "Opening file: " + path);
      Quickshell.execDetached([root.fileOpener, path]);
    });
  }

  function _runCommand(cmd) {
    root.launcher?.closeImmediately();
    Qt.callLater(() => {
      Logger.d("run-path", "Running command: " + cmd);
      Quickshell.execDetached(["sh", "-c", cmd]);
    });
  }

  // Rewrite the search text so the user can descend without typing the name.
  function _descend(path) {
    root.launcher?.setSearchText(">r " + root._pretty(path));
  }

  // --- Provider contract ---------------------------------------------------

  function handleCommand(query) {
    return query === ">r" || query.indexOf(">r ") === 0;
  }

  function commands() {
    return [
      {
        "name": ">r",
        "description": root.keybindHint !== "" ? (pluginApi?.tr("provider.command-description-key", {
          "key": root.keybindHint
        }) ?? "") : (pluginApi?.tr("provider.command-description") ?? ""),
        "icon": root.useTabler ? "folder-open" : "system-file-manager",
        "isTablerIcon": root.useTabler,
        "isImage": false,
        "onActivate": function () {
          root.launcher?.setSearchText(">r ");
        }
      }
    ];
  }

  function getResults(query) {
    if (!root.handleCommand(query))
      return [];

    // Everything after the prefix. Computed from the prefix length rather
    // than a magic number so the two stay in sync.
    const input = query.substring(2).replace(/^\s+/, "").replace(/\s+$/, "");

    if (input !== "" && !root._looksLikePath(input))
      return root._commandResults(input);

    return root._pathResults(input === "" ? "~/" : input);
  }

  function _commandResults(input) {
    return [
      {
        "name": pluginApi?.tr("results.run", {
          "command": input
        }) ?? ("Run: " + input),
        "description": pluginApi?.tr("results.run-description") ?? "",
        "icon": root.useTabler ? "terminal-2" : "utilities-terminal",
        "isTablerIcon": root.useTabler,
        "isImage": false,
        "onActivate": function () {
          root._runCommand(input);
        }
      }
    ];
  }

  function _pathResults(input) {
    const abs = root._expand(input);
    const parts = root._split(abs);
    const dir = parts[0];
    const frag = parts[1];

    const rec = root._listing(dir);
    if (!rec) {
      // First keystroke into a new directory: the listing is in flight.
      return [
        {
          "name": pluginApi?.tr("results.loading") ?? "Loading…",
          "description": root._pretty(dir),
          "icon": root.useTabler ? "search" : "system-search",
          "isTablerIcon": root.useTabler,
          "isImage": false,
          "onActivate": function () {}
        }
      ];
    }

    if (!rec.exists) {
      return [
        {
          "name": pluginApi?.tr("results.no-such-directory") ?? "No such directory",
          "description": root._pretty(dir),
          "icon": root.useTabler ? "alert-circle" : "dialog-error",
          "isTablerIcon": root.useTabler,
          "isImage": false,
          "onActivate": function () {}
        }
      ];
    }

    const out = [];
    const fragLower = frag.toLowerCase();

    // Row 0 — the path as typed, when it resolves to something real. This is
    // the row the launcher preselects, so Enter opens what you typed.
    if (frag === "") {
      const dirPath = dir.length > 1 && dir.charAt(dir.length - 1) === "/" ? dir.substring(0, dir.length - 1) : dir;
      out.push(root._openDirRow(dirPath));
    } else if (rec.entries.indexOf(frag + "/") >= 0) {
      out.push(root._openDirRow(dir + frag));
    } else if (rec.entries.indexOf(frag) >= 0) {
      const filePath = dir + frag;
      out.push({
        "name": pluginApi?.tr("results.open-file", {
          "name": frag
        }) ?? ("Open " + frag),
        "description": root._pretty(filePath),
        "icon": root.useTabler ? "file-text" : "text-x-generic",
        "isTablerIcon": root.useTabler,
        "isImage": false,
        "onActivate": function () {
          root._openFile(filePath);
        }
      });
    }

    // Completion rows. Directories first, then files; both alphabetical,
    // which is the order `ls` already produced.
    const dirs = [];
    const files = [];
    for (let i = 0; i < rec.entries.length; i++) {
      const e = rec.entries[i];
      const isDir = e.charAt(e.length - 1) === "/";
      const bare = isDir ? e.substring(0, e.length - 1) : e;
      if (fragLower !== "" && bare.toLowerCase().indexOf(fragLower) !== 0)
        continue;
      if (fragLower !== "" && bare === frag)
        continue; // already shown as row 0
      (isDir ? dirs : files).push(bare);
    }

    const ordered = dirs.concat(files);
    const limit = Math.min(ordered.length, root.maxResults);
    for (let j = 0; j < limit; j++) {
      const bare = ordered[j];
      const isDir = j < dirs.length;
      const full = dir + bare;
      if (isDir) {
        out.push({
          "name": bare + "/",
          "description": pluginApi?.tr("results.descend") ?? "",
          "icon": root.useTabler ? "folder" : "folder",
          "isTablerIcon": root.useTabler,
          "isImage": false,
          "onActivate": function () {
            // Clicking a directory descends into it rather than opening it —
            // opening is what row 0 (and therefore Enter) does.
            root._descend(full + "/");
          }
        });
      } else {
        out.push({
          "name": bare,
          "description": pluginApi?.tr("results.open-file-description") ?? "",
          "icon": root.useTabler ? "file" : "text-x-generic",
          "isTablerIcon": root.useTabler,
          "isImage": false,
          "onActivate": function () {
            root._openFile(full);
          }
        });
      }
    }

    return out;
  }

  function _openDirRow(path) {
    return {
      "name": pluginApi?.tr("results.open-directory", {
        "name": root._basename(path) || "/"
      }) ?? ("Open " + path),
      "description": root._pretty(path),
      "icon": root.useTabler ? "folder-open" : "folder-open",
      "isTablerIcon": root.useTabler,
      "isImage": false,
      "onActivate": function () {
        root._openInFileManager(path);
      }
    };
  }

  Component.onDestruction: {
    if (lsProc.running)
      lsProc.running = false;
  }
}
