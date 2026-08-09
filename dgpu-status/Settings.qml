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

  property string valuePciAddress: pluginApi?.pluginSettings?.pciAddress ?? ""
  property int valueStatusIntervalSec: pluginApi?.pluginSettings?.statusIntervalSec ?? 3
  property int valueActiveIntervalSec: pluginApi?.pluginSettings?.activeIntervalSec ?? 5
  property int valueIdleIntervalSec: pluginApi?.pluginSettings?.idleIntervalSec ?? 30
  property bool valueHideWhenSuspended: pluginApi?.pluginSettings?.hideWhenSuspended ?? false
  property bool valueShowTemperature: pluginApi?.pluginSettings?.showTemperature ?? true

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.hide-when-suspended")
    description: pluginApi?.tr("settings.hide-when-suspended-description")
    checked: root.valueHideWhenSuspended
    onToggled: checked => {
      root.valueHideWhenSuspended = checked;
    }
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.show-temperature")
    description: pluginApi?.tr("settings.show-temperature-description")
    checked: root.valueShowTemperature
    onToggled: checked => {
      root.valueShowTemperature = checked;
    }
  }

  // Reading runtime_status is a kernel-internal variable read, so this can be
  // frequent without any power cost.
  NSpinBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.status-interval")
    description: pluginApi?.tr("settings.status-interval-description")
    from: 2
    to: 30
    stepSize: 1
    suffix: " s"
    value: root.valueStatusIntervalSec
    onValueChanged: root.valueStatusIntervalSec = value
  }

  // This one does cost something — every tick runs nvidia-smi against a GPU
  // that is already awake. Main.qml enforces a 5 s floor.
  NSpinBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.active-interval")
    description: pluginApi?.tr("settings.active-interval-description")
    from: 5
    to: 60
    stepSize: 1
    suffix: " s"
    value: root.valueActiveIntervalSec
    onValueChanged: root.valueActiveIntervalSec = value
  }

  NSpinBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.idle-interval")
    description: pluginApi?.tr("settings.idle-interval-description")
    from: 10
    to: 300
    stepSize: 10
    suffix: " s"
    value: root.valueIdleIntervalSec
    onValueChanged: root.valueIdleIntervalSec = value
  }

  // Blank means "detect the first NVIDIA VGA device that has runtime PM".
  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.pci-address")
    description: pluginApi?.tr("settings.pci-address-description")
    placeholderText: "0000:01:00.0"
    text: root.valuePciAddress
    onEditingFinished: root.valuePciAddress = text
  }

  function saveSettings() {
    if (!pluginApi)
      return;
    pluginApi.pluginSettings.pciAddress = root.valuePciAddress;
    pluginApi.pluginSettings.statusIntervalSec = root.valueStatusIntervalSec;
    pluginApi.pluginSettings.activeIntervalSec = root.valueActiveIntervalSec;
    pluginApi.pluginSettings.idleIntervalSec = root.valueIdleIntervalSec;
    pluginApi.pluginSettings.hideWhenSuspended = root.valueHideWhenSuspended;
    pluginApi.pluginSettings.showTemperature = root.valueShowTemperature;
    pluginApi.saveSettings();
  }
}
