pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Io
import qs.components
import qs.modules.nexus.common
import qs.modules.nexus.pages.display

PageBase {
    id: root

    title: qsTr("Display")

    // Sourced from `hyprctl monitors all` so DISABLED monitors are listed too
    // (the normal monitor list / Hypr.monitors omits disabled outputs, which
    // would otherwise make a disabled screen impossible to re-enable here).
    property var monitorList: []

    function refresh(): void {
        refreshTimer.restart();
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            id: monProc

            command: ["hyprctl", "monitors", "all", "-j"]
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        root.monitorList = JSON.parse(text);
                    } catch (e) {
                        root.monitorList = [];
                    }
                }
            }
        }

        // Re-poll shortly after a change so the UI reflects the new state
        Timer {
            id: refreshTimer

            interval: 300
            onTriggered: monProc.running = true
        }

        Connections {
            target: Hyprland

            function onRawEvent(event: HyprlandEvent): void {
                if (event.name.includes("monitor"))
                    root.refresh();
            }
        }

        Repeater {
            model: root.monitorList

            delegate: MonitorSection {
                required property var modelData

                Layout.fillWidth: true
                monitorData: modelData
                allMonitors: root.monitorList
                onApplied: root.refresh()
            }
        }
    }
}
