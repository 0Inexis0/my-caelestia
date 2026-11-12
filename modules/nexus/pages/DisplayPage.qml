pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import qs.modules.nexus.pages.display

PageBase {
    id: root

    // Sourced from `hyprctl monitors all` so DISABLED monitors are listed too
    // (the normal monitor list / Hypr.monitors omits disabled outputs, which
    // would otherwise make a disabled screen impossible to re-enable here).
    property var monitorList: []

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
                if (busy) return;
                error = "";
                applyProc.command = ["python3", decodeURIComponent(Qt.resolvedUrl("../../../assets/displayctl.py").toString().replace(/^file:\/\//, "")), JSON.stringify(request)];
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
            function onRawEvent(event: HyprlandEvent): void {
                if (event.name.includes("monitor"))
                    root.refresh();
            }

            target: Hyprland
        }

        SelectRow {
            Layout.fillWidth: true
            visible: root.monitorList.some(m => /^(eDP|LVDS|DSI)/.test(m.name)) && root.monitorList.some(m => /^(HDMI-|DP-|DVI-|VGA-|USB-)/.test(m.name))
            enabled: !displayController.busy
            first: true
            last: true
            label: Tr.tr("Display mode")
            subtext: Tr.tr("Choose where to show your desktop")
            fallbackText: Tr.tr("Choose")
            menuItems: [internalMode, externalMode, extendMode, mirrorMode]
            active: {
                const panels = root.monitorList.filter(m => /^(eDP|LVDS|DSI)/.test(m.name));
                const outputs = root.monitorList.filter(m => /^(HDMI-|DP-|DVI-|VGA-|USB-)/.test(m.name));
                if (panels.every(m => m.disabled)) return externalMode;
                if (outputs.every(m => m.disabled)) return internalMode;
                if (outputs.length && outputs.every(m => !m.disabled && panels.some(p => p.name === m.mirrorOf))) return mirrorMode;
                return extendMode;
            }
            onSelected: item => displayController.apply({layout: item.layout})

            MenuItem { id: internalMode; property string layout: "internal"; text: Tr.tr("Laptop only") }
            MenuItem { id: externalMode; property string layout: "external"; text: Tr.tr("External only") }
            MenuItem { id: extendMode; property string layout: "extend"; text: Tr.tr("Extend") }
            MenuItem { id: mirrorMode; property string layout: "mirror"; text: Tr.tr("Mirror") }
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
