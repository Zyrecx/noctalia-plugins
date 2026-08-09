import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Settings page. The `??` fallbacks must stay identical to
// manifest.json -> metadata.defaultSettings.
ColumnLayout {
  id: root
  spacing: Style.marginM

  property var pluginApi: null

  property string valueKeybindHint: pluginApi?.pluginSettings?.keybindHint ?? "Super+R"
  property string valueFileManager: pluginApi?.pluginSettings?.fileManager ?? "xdg-open"
  property string valueFileOpener: pluginApi?.pluginSettings?.fileOpener ?? "xdg-open"
  property bool valueShowHidden: pluginApi?.pluginSettings?.showHidden ?? false
  property int valueMaxResults: pluginApi?.pluginSettings?.maxResults ?? 20

  // A Wayland shell can't register a global hotkey — the compositor owns them.
  // So the plugin can't tell you its keybind, only remind you of the one you
  // set. This line is the thing to paste into your Hyprland config; the field
  // below is the label shown in the launcher's `>` command list.
  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.bind-line")
    description: pluginApi?.tr("settings.bind-line-description")
    readOnly: true
    showClearButton: false
    text: "bind = SUPER, R, exec, qs -c noctalia-shell ipc call plugin:run-path toggle"
  }

  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.keybind-hint")
    description: pluginApi?.tr("settings.keybind-hint-description")
    placeholderText: "Super+R"
    text: root.valueKeybindHint
    onEditingFinished: root.valueKeybindHint = text
  }

  // Defaults to xdg-open so the plugin follows the desktop's own default
  // handler (currently org.gnome.Nautilus.desktop on this machine). Put a
  // concrete binary here — `nautilus`, `thunar`, `dolphin` — to bypass it.
  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.file-manager")
    description: pluginApi?.tr("settings.file-manager-description")
    text: root.valueFileManager
    onEditingFinished: root.valueFileManager = text
  }

  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.file-opener")
    description: pluginApi?.tr("settings.file-opener-description")
    text: root.valueFileOpener
    onEditingFinished: root.valueFileOpener = text
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.show-hidden")
    description: pluginApi?.tr("settings.show-hidden-description")
    checked: root.valueShowHidden
    onToggled: checked => {
      root.valueShowHidden = checked;
    }
  }

  NSpinBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.max-results")
    description: pluginApi?.tr("settings.max-results-description")
    from: 5
    to: 100
    stepSize: 5
    value: root.valueMaxResults
    onValueChanged: root.valueMaxResults = value
  }

  function saveSettings() {
    if (!pluginApi)
      return;
    pluginApi.pluginSettings.keybindHint = root.valueKeybindHint;
    pluginApi.pluginSettings.fileManager = root.valueFileManager;
    pluginApi.pluginSettings.fileOpener = root.valueFileOpener;
    pluginApi.pluginSettings.showHidden = root.valueShowHidden;
    pluginApi.pluginSettings.maxResults = root.valueMaxResults;
    pluginApi.saveSettings();
  }
}
