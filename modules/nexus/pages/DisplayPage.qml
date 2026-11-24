pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.modules.nexus.common
import qs.modules.nexus.pages.display

PageBase {
    id: root

    // Sourced from `hyprctl monitors all` so DISABLED monitors are listed too
    // (the normal monitor list / Hypr.monitors omits disabled outputs, which
    // would otherwise make a disabled screen impossible to re-enable here).
    property var monitorList: []

    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("../../../assets/displayctl.py").toString().replace(/^file:\/\//, ""))

    function refresh(): void {
        refreshTimer.restart();
    }

    title: Tr.tr("Display")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        QtObject {
            id: displayController

            readonly property bool busy: applyProc.running
            property string error: ""

            function apply(request: var): void {
                if (busy)
                    return;
                error = "";
                applyProc.command = ["python3", root.helper, JSON.stringify(request)];
                applyProc.running = true;
            }
        }

        Process {
            id: applyProc

            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const result = JSON.parse(text);
                        displayController.error = result.ok ? "" : result.error;
                    } catch (e) {
                        displayController.error = Tr.tr("Could not apply display settings");
                    }
                }
            }
            onExited: root.refresh()
        }

        Process {
            id: monProc

            command: ["python3", root.helper, JSON.stringify({
                    list: true
                })]
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
            function onRawEvent(event: HyprlandEvent): void {
                if (event.name.includes("monitor"))
                    root.refresh();
            }

            target: Hyprland
        }

        DisplayModeRow {
            monitorList: root.monitorList
            enabled: !displayController.busy
            onLayoutRequested: mode => displayController.apply({
                    layout: mode
                })
        }

        StyledText {
            Layout.fillWidth: true
            visible: displayController.busy || displayController.error !== ""
            text: displayController.busy ? Tr.tr("Applying display settings…") : displayController.error
            color: displayController.error ? Colours.palette.m3error : Colours.palette.m3outline
            wrapMode: Text.Wrap
        }

        Repeater {
            model: root.monitorList

            delegate: MonitorSection {
                required property var modelData

                Layout.fillWidth: true
                monitorData: modelData
                allMonitors: root.monitorList
                controller: displayController
            }
        }
    }
}
