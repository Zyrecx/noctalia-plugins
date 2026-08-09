import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Bar capsule. Three visual states:
//
//   suspended  — dimmed icon, no text (nothing is using the dGPU)
//   active     — accent icon + temperature (or utilisation)
//   transition — "suspending"/"resuming" render as the dimmed state
//
// The widget never triggers a GPU query on its own; it only renders what
// Main.qml already knows.
Item {
  id: root

  property var pluginApi: null

  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property string screenName: screen?.name ?? ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)
  readonly property real iconSize: Style.toOdd(capsuleHeight * 0.55)

  readonly property var cfg: pluginApi?.pluginSettings || ({})
  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})
  readonly property bool hideWhenSuspended: cfg.hideWhenSuspended ?? defaults.hideWhenSuspended ?? false
  readonly property bool showTemperature: cfg.showTemperature ?? defaults.showTemperature ?? true
  readonly property string activeColor: cfg.activeColor ?? defaults.activeColor ?? "primary"

  readonly property var main: pluginApi?.mainInstance ?? null

  readonly property bool active: {
    const _rev = main?.revision ?? 0;
    return main?.isActive ?? false;
  }

  readonly property string label: {
    const _rev = main?.revision ?? 0;
    if (!main || !main.isActive)
      return "";
    if (root.showTemperature && main.temperatureC >= 0)
      return main.temperatureC + "°";
    if (main.utilizationPct >= 0)
      return main.utilizationPct + "%";
    return "";
  }

  readonly property string tooltipText: {
    const _rev = main?.revision ?? 0;
    if (!main)
      return "";
    if (!main.deviceFound)
      return pluginApi?.tr("bar.tooltip-no-device") ?? "";
    if (!main.isActive)
      return pluginApi?.tr("bar.tooltip-suspended", {
        "state": main.runtimeStatus
      }) ?? "";
    const procs = main.processes.length;
    return pluginApi?.tr("bar.tooltip-active", {
      "temp": main.temperatureC >= 0 ? main.temperatureC : "?",
      "util": main.utilizationPct >= 0 ? main.utilizationPct : "?",
      "watts": main.powerDrawW >= 0 ? main.powerDrawW.toFixed(1) : "?",
      "processes": procs
    }) ?? "";
  }

  // Hidden entirely when the user asked for that and the GPU is asleep.
  readonly property bool shouldShow: !(root.hideWhenSuspended && !root.active)

  visible: shouldShow

  readonly property real contentWidth: {
    if (!shouldShow)
      return 0;
    if (isVertical)
      return capsuleHeight;
    let w = iconSize + Style.marginM * 2;
    if (labelText.text !== "")
      w += Style.marginS + labelText.implicitWidth;
    return w;
  }

  implicitWidth: contentWidth
  implicitHeight: shouldShow ? capsuleHeight : 0

  Rectangle {
    id: capsule
    x: Style.pixelAlignCenter(parent.width, width)
    y: Style.pixelAlignCenter(parent.height, height)
    width: root.contentWidth
    height: root.capsuleHeight
    radius: Style.radiusL
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth
    visible: root.shouldShow

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.marginM
      anchors.rightMargin: Style.marginM
      spacing: Style.marginS

      NIcon {
        icon: "device-desktop-analytics"
        pointSize: root.iconSize
        color: root.active ? Color.resolveColorKey(root.activeColor) : Color.mOnSurfaceVariant
        opacity: root.active ? 1.0 : 0.55
        Layout.alignment: Qt.AlignVCenter

        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationFast
          }
        }
      }

      NText {
        id: labelText
        text: root.label
        visible: text !== "" && !root.isVertical
        pointSize: root.barFontSize
        applyUiScale: false
        color: Color.resolveColorKey(root.activeColor)
        Layout.alignment: Qt.AlignVCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton

      onClicked: mouse => {
        if (!root.pluginApi)
          return;
        if (mouse.button === Qt.LeftButton) {
          // togglePanel opens when closed and closes when open. The second
          // argument is the anchor: without it the panel drifts to the centre
          // of the screen instead of hanging off this widget.
          root.pluginApi.togglePanel(root.screen, root);
        } else {
          PanelService.showContextMenu(contextMenu, root, root.screen);
        }
      }

      onEntered: TooltipService.show(root, root.tooltipText, BarService.getTooltipDirection(root.screenName))
      onExited: TooltipService.hide()
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": pluginApi?.tr("context.settings"),
        "action": "settings",
        "icon": "settings"
      }
    ]

    onTriggered: action => {
      contextMenu.close();
      PanelService.closeContextMenu(root.screen);
      if (action === "settings" && root.pluginApi?.manifest)
        BarService.openPluginSettings(root.screen, root.pluginApi.manifest);
    }
  }
}
