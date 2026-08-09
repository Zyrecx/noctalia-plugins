import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Bar capsule: CPU icon plus the short name of the running scheduler
// ("lavd"), or the configured stopped-label when the kernel scheduler is in
// charge. Left click opens the panel, right click opens a context menu.
Item {
  id: root

  property var pluginApi: null

  // Injected by the shell after instantiation.
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

  readonly property bool showLabel: cfg.showLabel ?? defaults.showLabel ?? true
  readonly property string stoppedLabel: cfg.stoppedLabel ?? defaults.stoppedLabel ?? "off"
  readonly property string activeColor: cfg.activeColor ?? defaults.activeColor ?? "primary"
  readonly property string textColor: cfg.textColor ?? defaults.textColor ?? "none"
  readonly property string iconColor: cfg.iconColor ?? defaults.iconColor ?? "none"

  readonly property var main: pluginApi?.mainInstance ?? null

  // Reading `revision` inside these bindings is what makes them re-evaluate
  // when Main.qml refreshes its state.
  readonly property bool running: {
    const _rev = main?.revision ?? 0;
    return main?.schedulerRunning ?? false;
  }
  readonly property string label: {
    const _rev = main?.revision ?? 0;
    if (!main)
      return root.stoppedLabel;
    return main.schedulerRunning ? main.shortName(main.currentScheduler) : root.stoppedLabel;
  }

  readonly property string tooltipText: {
    const _rev = main?.revision ?? 0;
    if (!main)
      return pluginApi?.tr("bar.tooltip-unknown") ?? "";
    if (!main.loaderAvailable)
      return pluginApi?.tr("bar.tooltip-unavailable") ?? "";
    if (!main.schedulerRunning)
      return pluginApi?.tr("bar.tooltip-stopped") ?? "";
    const mode = main.currentMode;
    return mode !== "" ? pluginApi?.tr("bar.tooltip-running-mode", {
      "scheduler": main.currentScheduler,
      "mode": mode
    }) : pluginApi?.tr("bar.tooltip-running", {
      "scheduler": main.currentScheduler
    });
  }

  readonly property real contentWidth: {
    if (isVertical)
      return capsuleHeight;
    let w = iconSize + Style.marginM * 2;
    if (showLabel)
      w += Style.marginS + labelText.implicitWidth;
    return w;
  }
  readonly property real contentHeight: isVertical && showLabel ? capsuleHeight * 2 : capsuleHeight

  implicitWidth: contentWidth
  implicitHeight: contentHeight

  Rectangle {
    id: capsule
    x: Style.pixelAlignCenter(parent.width, width)
    y: Style.pixelAlignCenter(parent.height, height)
    width: root.contentWidth
    height: root.contentHeight
    radius: Style.radiusL
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    Behavior on color {
      ColorAnimation {
        duration: Style.animationFast
      }
    }

    // Horizontal bars: icon + label side by side.
    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.marginM
      anchors.rightMargin: Style.marginM
      spacing: Style.marginS
      visible: !root.isVertical

      NIcon {
        icon: "cpu"
        pointSize: root.iconSize
        color: Color.resolveColorKey(root.running ? root.activeColor : root.iconColor)
        Layout.alignment: Qt.AlignVCenter
      }

      NText {
        id: labelText
        text: root.label
        pointSize: root.barFontSize
        applyUiScale: false
        visible: root.showLabel
        color: Color.resolveColorKey(root.running ? root.activeColor : root.textColor)
        Layout.alignment: Qt.AlignVCenter
      }
    }

    // Vertical bars: icon over label; the label is dropped if it would not
    // fit the capsule width.
    ColumnLayout {
      anchors.fill: parent
      anchors.topMargin: Style.marginXS
      anchors.bottomMargin: Style.marginXS
      spacing: 0
      visible: root.isVertical

      NIcon {
        icon: "cpu"
        pointSize: root.iconSize
        color: Color.resolveColorKey(root.running ? root.activeColor : root.iconColor)
        Layout.alignment: Qt.AlignHCenter
      }

      NText {
        text: root.label
        pointSize: root.barFontSize * 0.8
        applyUiScale: false
        visible: root.showLabel
        elide: Text.ElideRight
        Layout.maximumWidth: root.capsuleHeight
        Layout.alignment: Qt.AlignHCenter
        color: Color.resolveColorKey(root.running ? root.activeColor : root.textColor)
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
        "label": pluginApi?.tr("context.stop"),
        "action": "stop",
        "icon": "player-stop"
      },
      {
        "label": pluginApi?.tr("context.restore"),
        "action": "restore",
        "icon": "restore"
      },
      {
        "label": pluginApi?.tr("context.settings"),
        "action": "settings",
        "icon": "settings"
      }
    ]

    onTriggered: action => {
      contextMenu.close();
      PanelService.closeContextMenu(root.screen);
      if (action === "stop")
        root.main?.stopScheduler();
      else if (action === "restore")
        root.main?.restoreDefault();
      else if (action === "settings" && root.pluginApi?.manifest)
        BarService.openPluginSettings(root.screen, root.pluginApi.manifest);
    }
  }
}
