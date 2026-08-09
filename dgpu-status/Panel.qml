import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

// Panel. While the GPU is suspended this shows the power state and nothing
// else — deliberately. The only way to get numbers out of a sleeping GPU is to
// wake it, so that is behind an explicitly labelled button rather than being a
// side effect of opening a panel.
Item {
  id: root

  property var pluginApi: null

  readonly property var geometryPlaceholder: mainContainer
  readonly property bool allowAttach: true
  property color panelBackgroundColor: Color.mSurface
  property real contentPreferredWidth: 360 * Style.uiScaleRatio

  property var contentPreferredHeight: {
    const _rev = root.main?.revision ?? 0;
    const scale = Style.uiScaleRatio;
    if (!(root.main?.isActive ?? false))
      return Math.round(230 * scale);
    const procs = Math.min((root.main?.processes ?? []).length, 6);
    return Math.round((300 + procs * 30) * scale);
  }

  readonly property var main: pluginApi?.mainInstance ?? null

  readonly property string stateLabel: {
    const _rev = root.main?.revision ?? 0;
    if (!root.main)
      return "";
    if (!root.main.deviceFound)
      return pluginApi?.tr("panel.state-no-device") ?? "";
    switch (root.main.runtimeStatus) {
    case "active":
      return pluginApi?.tr("panel.state-active") ?? "";
    case "suspended":
      return pluginApi?.tr("panel.state-suspended") ?? "";
    case "suspending":
      return pluginApi?.tr("panel.state-suspending") ?? "";
    case "resuming":
      return pluginApi?.tr("panel.state-resuming") ?? "";
    case "":
      return pluginApi?.tr("panel.state-reading") ?? "";
    default:
      return root.main.runtimeStatus;
    }
  }

  Item {
    id: mainContainer
    anchors.fill: parent

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // --- Header -----------------------------------------------------------
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
              icon: (root.main?.isActive ?? false) ? "device-desktop-analytics" : "moon"
              pointSize: Style.fontSizeXL
              color: (root.main?.isActive ?? false) ? Color.mPrimary : Color.mOnSurfaceVariant
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0

              NText {
                text: {
                  const _rev = root.main?.revision ?? 0;
                  const n = root.main?.gpuName ?? "";
                  return n !== "" ? n : (pluginApi?.tr("panel.title") ?? "");
                }
                pointSize: Style.fontSizeL
                font.weight: Style.fontWeightBold
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              NText {
                text: root.stateLabel
                pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
              }
            }
          }

          NText {
            Layout.fillWidth: true
            visible: (root.main?.pciAddress ?? "") !== ""
            text: root.main?.pciAddress ?? ""
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }
        }
      }

      // --- Suspended state --------------------------------------------------
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.marginM
        visible: !(root.main?.isActive ?? false)

        NText {
          Layout.fillWidth: true
          text: pluginApi?.tr("panel.suspended-explainer")
          pointSize: Style.fontSizeS
          wrapMode: Text.WordWrap
          color: Color.mOnSurfaceVariant
        }

        Item {
          Layout.fillHeight: true
        }

        // The only path in this plugin that reaches the device on purpose.
        NButton {
          Layout.fillWidth: true
          text: pluginApi?.tr("panel.wake-and-read")
          icon: "player-play"
          outlined: true
          enabled: (root.main?.deviceFound ?? false) && (root.main?.smiAvailable ?? false)
          onClicked: root.main?.sampleNow()
        }

        NText {
          Layout.fillWidth: true
          text: pluginApi?.tr("panel.wake-warning")
          pointSize: Style.fontSizeXS
          wrapMode: Text.WordWrap
          color: Color.mOnSurfaceVariant
        }
      }

      // --- Active state -----------------------------------------------------
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.marginM
        visible: (root.main?.isActive ?? false)

        GridLayout {
          Layout.fillWidth: true
          columns: 2
          rowSpacing: Style.marginS
          columnSpacing: Style.marginM

          Repeater {
            model: {
              const _rev = root.main?.revision ?? 0;
              const m = root.main;
              if (!m)
                return [];
              return [
                {
                  "icon": "thermometer",
                  "label": pluginApi?.tr("panel.temperature"),
                  "value": m.temperatureC >= 0 ? (m.temperatureC + " °C") : "—"
                },
                {
                  "icon": "chart-bar",
                  "label": pluginApi?.tr("panel.utilization"),
                  "value": m.utilizationPct >= 0 ? (m.utilizationPct + " %") : "—"
                },
                {
                  "icon": "bolt",
                  "label": pluginApi?.tr("panel.power"),
                  "value": m.powerDrawW >= 0 ? (m.powerDrawW.toFixed(1) + " W") : "—"
                },
                {
                  "icon": "components",
                  "label": pluginApi?.tr("panel.memory"),
                  "value": (m.memUsedMiB >= 0 && m.memTotalMiB >= 0) ? (m.memUsedMiB + " / " + m.memTotalMiB + " MiB") : "—"
                }
              ];
            }

            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: Style.marginS

              NIcon {
                icon: modelData.icon
                pointSize: Style.fontSizeL
                color: Color.mPrimary
              }

              ColumnLayout {
                spacing: 0
                Layout.fillWidth: true

                NText {
                  text: modelData.label
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: modelData.value
                  pointSize: Style.fontSizeM
                  font.weight: Style.fontWeightBold
                }
              }
            }
          }
        }

        NDivider {
          Layout.fillWidth: true
        }

        NText {
          text: pluginApi?.tr("panel.processes")
          pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
        }

        NScrollView {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true

          ColumnLayout {
            width: parent.width
            spacing: Style.marginXS

            NText {
              visible: ((root.main?.processes ?? []).length === 0)
              text: pluginApi?.tr("panel.no-processes")
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            Repeater {
              model: {
                const _rev = root.main?.revision ?? 0;
                return root.main?.processes ?? [];
              }

              delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Style.marginS

                NText {
                  // "G" = graphics client, "C" = compute client.
                  text: modelData.type
                  pointSize: Style.fontSizeXS
                  color: Color.mPrimary
                  Layout.preferredWidth: Style.marginL
                }

                NText {
                  text: modelData.name
                  pointSize: Style.fontSizeXS
                  elide: Text.ElideMiddle
                  Layout.fillWidth: true
                }

                NText {
                  text: modelData.memory
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                }
              }
            }
          }
        }

        NText {
          Layout.fillWidth: true
          visible: (root.main?.backedOff ?? false)
          text: pluginApi?.tr("panel.backed-off")
          pointSize: Style.fontSizeXS
          wrapMode: Text.WordWrap
          color: Color.mOnSurfaceVariant
        }
      }
    }
  }
}
