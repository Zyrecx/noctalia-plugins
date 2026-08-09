import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// Background object. This plugin's real work happens in Provider.qml; Main
// exists only to own the IPC handler, which is what a keybind talks to.
//
// pluginApi.toggleLauncher() opens the launcher pre-filled with this plugin's
// prefix (">r ", derived from metadata.commandPrefix in manifest.json), and
// closes it again if it is already in that mode.
Item {
  id: root

  property var pluginApi: null

  IpcHandler {
    target: "plugin:run-path"

    // bind = SUPER, R, exec, qs -c noctalia-shell ipc call plugin:run-path toggle
    function toggle() {
      root.pluginApi?.withCurrentScreen(screen => {
        root.pluginApi?.toggleLauncher(screen);
      });
    }

    // Always open, never close — useful if you bind it somewhere that repeats.
    function open() {
      root.pluginApi?.withCurrentScreen(screen => {
        root.pluginApi?.openLauncher(screen);
      });
    }

    // Open already pointed at a directory, so a single key lands you where you
    // work instead of at an empty prompt:
    //
    //   bind = SUPER SHIFT, R, exec, qs -c noctalia-shell ipc call plugin:run-path openAt ~/Projects
    //
    // pluginApi has no pre-filled-launcher call, so this reaches PanelService
    // directly. Trailing slash included so the listing shows the directory's
    // contents rather than its siblings.
    function openAt(path: string): void {
      const prefix = root.pluginApi?.manifest?.metadata?.commandPrefix ?? "r";
      const target = path.endsWith("/") ? path : path + "/";
      root.pluginApi?.withCurrentScreen(screen => {
        PanelService.openLauncherWithSearch(screen, ">" + prefix + " " + target);
      });
    }
  }
}
