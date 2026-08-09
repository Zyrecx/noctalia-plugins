import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

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
  }
}
