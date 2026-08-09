import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Panel: pick a sched-ext scheduler and the mode it runs in.
//
// Clicking a row starts it (or switches to it if one is already loaded) in
// the mode selected at the top. The first action of a session pops a polkit
// prompt; if it is cancelled the error line at the bottom explains why
// nothing changed.
Item {
  id: root

  property var pluginApi: null

  // --- SmartPanel contract -------------------------------------------------
  readonly property var geometryPlaceholder: mainContainer
  readonly property bool allowAttach: true
  property color panelBackgroundColor: Color.mSurface
  property real contentPreferredWidth: 380 * Style.uiScaleRatio

  property var contentPreferredHeight: {
    const _rev = root.main?.revision ?? 0;
    const scale = Style.uiScaleRatio;
    const count = (root.main?.supportedSchedulers ?? []).length;
    const overhead = Math.round(230 * scale);       // header + mode row + footer
    const rows = Math.min(count, 8) * Math.round(52 * scale);
    const errorRow = (root.main?.lastError ?? "") !== "" ? Math.round(34 * scale) : 0;
    return overhead + rows + errorRow;
  }

  readonly property var main: pluginApi?.mainInstance ?? null

  // Mode the next start/switch will use. Seeded from the running mode when
  // the panel opens, falling back to the configured default.
  property string selectedMode: (pluginApi?.pluginSettings?.defaultMode) ?? "auto"

  readonly property var modeOptions: [
    {
      "key": "auto",
      "name": pluginApi?.tr("modes.auto"),
      "icon": "adjustments"
    },
    {
      "key": "gaming",
      "name": pluginApi?.tr("modes.gaming"),
      "icon": "device-gamepad-2"
    },
    {
      "key": "lowlatency",
      "name": pluginApi?.tr("modes.lowlatency"),
      "icon": "bolt"
    },
    {
      "key": "powersave",
      "name": pluginApi?.tr("modes.powersave"),
      "icon": "leaf"
    },
    {
      "key": "server",
      "name": pluginApi?.tr("modes.server"),
      "icon": "server"
    }
  ]

  // Short blurbs for the schedulers whose purpose is well established
  // upstream. Anything not listed here simply renders without a subtitle —
  // an empty line is better than an invented description.
  readonly property var descriptions: ({
      "scx_lavd": pluginApi?.tr("schedulers.lavd"),
      "scx_bpfland": pluginApi?.tr("schedulers.bpfland"),
      "scx_rusty": pluginApi?.tr("schedulers.rusty"),
      "scx_flash": pluginApi?.tr("schedulers.flash"),
      "scx_rustland": pluginApi?.tr("schedulers.rustland"),
      "scx_tickless": pluginApi?.tr("schedulers.tickless")
    })

  onVisibleChanged: {
    if (visible) {
      root.main?.refresh();
      const runningMode = root.main?.currentMode ?? "";
      if (runningMode !== "")
        root.selectedMode = runningMode.toLowerCase();
    }
  }

  Item {
    id: mainContainer
    anchors.fill: parent

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // --- Header ----------------------------------------------------------
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: headerCol.implicitHeight + Style.marginM * 2

        ColumnLayout {
          id: headerCol
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginXS

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NIcon {
              icon: "cpu"
              pointSize: Style.fontSizeXL
              color: Color.mPrimary
            }

            NText {
              text: pluginApi?.tr("panel.title")
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              Layout.fillWidth: true
            }

            NIconButton {
              icon: "refresh"
              baseSize: Style.baseWidgetSize * 0.7
              tooltipText: pluginApi?.tr("panel.refresh")
              onClicked: root.main?.refresh()
            }
          }

          NText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            text: {
              const _rev = root.main?.revision ?? 0;
              if (!root.main)
                return "";
              if (!root.main.loaderAvailable)
                return pluginApi?.tr("panel.loader-unavailable");
              if (!root.main.schedulerRunning)
                return pluginApi?.tr("panel.status-stopped");
              const mode = root.main.currentMode;
              return mode !== "" ? pluginApi?.tr("panel.status-running-mode", {
                "scheduler": root.main.currentScheduler,
                "mode": mode
              }) : pluginApi?.tr("panel.status-running", {
                "scheduler": root.main.currentScheduler
              });
            }
          }
        }
      }

      // --- Mode selector ----------------------------------------------------
      NComboBox {
        Layout.fillWidth: true
        label: pluginApi?.tr("panel.mode")
        description: pluginApi?.tr("panel.mode-description")
        model: root.modeOptions
        currentKey: root.selectedMode
        enabled: (root.main?.loaderAvailable ?? false) && !(root.main?.busy ?? false)
        onSelected: key => {
          root.selectedMode = key;
          // If something is already running, apply the mode straight away —
          // that is what picking a mode obviously means here.
          if (root.main?.schedulerRunning)
            root.main.applyMode(key);
        }
      }

      // --- Scheduler list ---------------------------------------------------
      NScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        ColumnLayout {
          width: parent.width
          spacing: Style.marginXS

          Repeater {
            model: {
              const _rev = root.main?.revision ?? 0;
              return root.main?.supportedSchedulers ?? [];
            }

            delegate: Rectangle {
              id: row
              required property string modelData

              readonly property bool isCurrent: {
                const _rev = root.main?.revision ?? 0;
                return (root.main?.currentScheduler ?? "") === row.modelData;
              }
              readonly property string blurb: root.descriptions[row.modelData] ?? ""

              Layout.fillWidth: true
              implicitHeight: rowCol.implicitHeight + Style.marginS * 2
              radius: Style.radiusS
              color: rowArea.containsMouse ? Color.mHover : (row.isCurrent ? Color.mSurfaceVariant : "transparent")
              border.width: row.isCurrent ? Style.capsuleBorderWidth : 0
              border.color: Color.mPrimary

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.marginM
                anchors.rightMargin: Style.marginM
                spacing: Style.marginS

                ColumnLayout {
                  id: rowCol
                  Layout.fillWidth: true
                  spacing: 0

                  NText {
                    text: root.main?.shortName(row.modelData) ?? row.modelData
                    pointSize: Style.fontSizeM
                    font.weight: row.isCurrent ? Style.fontWeightBold : Style.fontWeightRegular
                    color: rowArea.containsMouse ? Color.mOnHover : Color.mOnSurface
                  }

                  NText {
                    visible: row.blurb !== ""
                    text: row.blurb
                    pointSize: Style.fontSizeXS
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    color: rowArea.containsMouse ? Color.mOnHover : Color.mOnSurfaceVariant
                  }
                }

                NIcon {
                  visible: row.isCurrent
                  icon: "circle-check"
                  pointSize: Style.fontSizeL
                  color: Color.mPrimary
                }
              }

              MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !(root.main?.busy ?? false)
                onClicked: root.main?.applyScheduler(row.modelData, root.selectedMode)
              }
            }
          }
        }
      }

      // --- Error line -------------------------------------------------------
      NText {
        Layout.fillWidth: true
        visible: (root.main?.lastError ?? "") !== ""
        text: root.main?.lastError ?? ""
        pointSize: Style.fontSizeXS
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        color: Color.mError
      }

      // --- Footer -----------------------------------------------------------
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NButton {
          Layout.fillWidth: true
          text: pluginApi?.tr("panel.stop")
          icon: "player-stop"
          outlined: true
          enabled: (root.main?.schedulerRunning ?? false) && !(root.main?.busy ?? false)
          onClicked: root.main?.stopScheduler()
        }

        // Disabled when no default is configured: scx_loader reads it from
        // /etc/scx_loader.toml, which doesn't exist on a stock install, and a
        // button that silently does nothing is worse than a greyed-out one.
        NButton {
          Layout.fillWidth: true
          text: pluginApi?.tr("panel.restore")
          icon: "restore"
          outlined: true
          enabled: (root.main?.defaultScheduler ?? "") !== "" && !(root.main?.busy ?? false)
          tooltipText: (root.main?.defaultScheduler ?? "") === "" ? pluginApi?.tr("panel.restore-unconfigured") : pluginApi?.tr("panel.restore-tooltip", {
            "scheduler": root.main.defaultScheduler
          })
          onClicked: root.main?.restoreDefault()
        }
      }
    }

    // Dim the whole panel while an action (and its polkit prompt) is pending.
    NBusyIndicator {
      anchors.centerIn: parent
      running: root.main?.busy ?? false
      visible: running
    }
  }
}
