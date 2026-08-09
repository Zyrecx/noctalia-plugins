import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Settings page. Edits are buffered in the value* properties and only written
// when the shell calls saveSettings() (the global Apply button).
//
// Every `??` fallback below must stay identical to
// manifest.json -> metadata.defaultSettings.
ColumnLayout {
  id: root
  spacing: Style.marginM

  property var pluginApi: null

  property int valuePollIntervalSec: pluginApi?.pluginSettings?.pollIntervalSec ?? 5
  property bool valueShowLabel: pluginApi?.pluginSettings?.showLabel ?? true
  property string valueStoppedLabel: pluginApi?.pluginSettings?.stoppedLabel ?? "off"
  property string valueDefaultMode: pluginApi?.pluginSettings?.defaultMode ?? "auto"

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.show-label")
    description: pluginApi?.tr("settings.show-label-description")
    checked: root.valueShowLabel
    onToggled: checked => {
      root.valueShowLabel = checked;
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.stopped-label")
    description: pluginApi?.tr("settings.stopped-label-description")
    text: root.valueStoppedLabel
    onEditingFinished: root.valueStoppedLabel = text
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.default-mode")
    description: pluginApi?.tr("settings.default-mode-description")
    model: [
      {
        "key": "auto",
        "name": pluginApi?.tr("modes.auto")
      },
      {
        "key": "gaming",
        "name": pluginApi?.tr("modes.gaming")
      },
      {
        "key": "lowlatency",
        "name": pluginApi?.tr("modes.lowlatency")
      },
      {
        "key": "powersave",
        "name": pluginApi?.tr("modes.powersave")
      },
      {
        "key": "server",
        "name": pluginApi?.tr("modes.server")
      }
    ]
    currentKey: root.valueDefaultMode
    onSelected: key => {
      root.valueDefaultMode = key;
    }
  }

  // Polling exists because scx_loader's PropertiesChanged signal is not
  // consumed by this plugin (v1 keeps the backend to two plain CLI reads).
  // Anything below 2 s is refused by Main.qml.
  NSpinBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.poll-interval")
    description: pluginApi?.tr("settings.poll-interval-description")
    from: 2
    to: 60
    stepSize: 1
    suffix: " s"
    value: root.valuePollIntervalSec
    onValueChanged: root.valuePollIntervalSec = value
  }

  function saveSettings() {
    if (!pluginApi)
      return;
    pluginApi.pluginSettings.pollIntervalSec = root.valuePollIntervalSec;
    pluginApi.pluginSettings.showLabel = root.valueShowLabel;
    pluginApi.pluginSettings.stoppedLabel = root.valueStoppedLabel;
    pluginApi.pluginSettings.defaultMode = root.valueDefaultMode;
    pluginApi.saveSettings();
  }
}
