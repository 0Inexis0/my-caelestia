pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.components.controls
import qs.modules.nexus.common
import "../../../../utils/Display.js" as Display

ColumnLayout {
    id: root

    // Plain object parsed from `hyprctl monitors all -j` (NOT a live HyprlandMonitor,
    // so that disabled outputs are included and remain controllable).
    required property var monitorData
    property var allMonitors: []

    readonly property string name: monitorData.name

    readonly property bool isDisabled: monitorData.disabled ?? false

    readonly property var availableModes: monitorData.availableModes ?? []

    readonly property bool isMirrored: !!monitorData.mirrorOf && monitorData.mirrorOf !== "none"

    readonly property real scaleVal: (monitorData.scale ?? 0) > 0 ? monitorData.scale : 1

    readonly property string currentMode: {
        const w = monitorData.width, h = monitorData.height, r = monitorData.refreshRate;
        return availableModes.find(m => {
            const match = m.match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
            return match && parseInt(match[1]) === w && parseInt(match[2]) === h && Math.abs(parseFloat(match[3]) - r) < 0.5;
        }) ?? (availableModes[0] ?? `${w}x${h}@${r}Hz`);
    }

    readonly property bool isInternal: name.startsWith("eDP") || name.startsWith("LVDS") || name.startsWith("DSI")

    readonly property bool hasExternal: allMonitors.some(m => /^(HDMI-|DP-|DVI-|VGA-|USB-)/.test(m.name) && !m.disabled)

    readonly property string home: Quickshell.env("HOME")

    readonly property string markerFile: `${home}/.config/hypr/.auto-disable-${name}`

    property bool autoDisableEnabled: false


    property var controller: null

    function applyMonitor(mode: string, scale: real, enabled: bool): void {
        root.controller.apply({name: root.name, mode: mode, scale: scale, enabled: enabled});
    }

    enabled: !controller || !controller.busy

    spacing: Tokens.spacing.extraSmall / 2

    Variants {
        id: modeVariants

        model: root.availableModes

        MenuItem {
            required property string modelData

            text: modelData
        }
    }

    // Reflect whether this monitor is opted into auto-disable
    Process {
        running: true
        command: ["sh", "-c", `test -f '${root.markerFile}' && echo 1 || echo 0`]
        stdout: StdioCollector {
            onStreamFinished: root.autoDisableEnabled = text.trim() === "1"
        }
    }

    SectionHeader {
        text: root.name + (root.monitorData.description ? ` — ${root.monitorData.description}` : "") + (root.isDisabled ? Tr.tr(" (disabled)") : "")
    }

    ToggleRow {
        Layout.fillWidth: true
        first: true
        text: Tr.tr("Enabled")
        subtext: Tr.tr("Output active")
        checked: !root.isDisabled
        onToggled: root.applyMonitor(root.currentMode, root.scaleVal, checked)
    }

    ToggleRow {
        Layout.fillWidth: true
        visible: root.isInternal
        text: Tr.tr("Auto-disable when external connected")
        subtext: Tr.tr("Turns this screen off while an external is plugged in, back on when unplugged")
        checked: root.autoDisableEnabled
        onToggled: {
            root.autoDisableEnabled = checked;
            if (checked) {
                Quickshell.execDetached(["sh", "-c", `touch '${root.markerFile}'`]);
                if (root.hasExternal)
                    root.applyMonitor(root.currentMode, root.scaleVal, false);
            } else {
                Quickshell.execDetached(["rm", "-f", root.markerFile]);
                // Symmetric with enabling: turning auto-disable off should bring
                // the screen back, otherwise the toggle appears to do nothing
                // (and the manual "Enabled" toggle is the only way back on).
                if (root.isDisabled)
                    root.applyMonitor(root.currentMode, root.scaleVal, true);
            }
        }
    }

    SelectRow {
        Layout.fillWidth: true
        enabled: !root.isDisabled
        opacity: root.isDisabled ? 0.5 : 1
        label: Tr.tr("Resolution & refresh rate")
        subtext: root.currentMode
        menuItems: modeVariants.instances
        active: modeVariants.instances.find(i => i.text === root.currentMode) ?? modeVariants.instances[0] ?? null
        onSelected: item => root.applyMonitor(item.text, root.scaleVal, true)
    }

    Variants {
        id: scaleVariants
        model: Display.scales(root.monitorData.width, root.monitorData.height, root.scaleVal)

        MenuItem {
            required property real modelData
            text: `${Math.round(modelData * 10000) / 100}%`
        }
    }

    SelectRow {
        Layout.fillWidth: true
        last: true
        enabled: !root.isDisabled && !root.isMirrored
        opacity: root.isDisabled || root.isMirrored ? 0.5 : 1
        label: Tr.tr("Scale")
        subtext: root.isMirrored ? Tr.tr("Change scaling on the source display while mirroring") : Tr.tr("Display scaling factor")
        menuItems: scaleVariants.instances
        active: scaleVariants.instances.find(i => Math.abs(i.modelData - root.scaleVal) < 0.001) ?? null
        onSelected: item => root.applyMonitor(root.currentMode, item.modelData, true)
    }
}
