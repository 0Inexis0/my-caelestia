pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.components.controls
import qs.modules.nexus.common

ColumnLayout {
    id: root

    // Plain object parsed from `hyprctl monitors all -j` (NOT a live HyprlandMonitor,
    // so that disabled outputs are included and remain controllable).
    required property var monitorData
    property var allMonitors: []

    signal applied

    readonly property string name: monitorData.name
    readonly property bool isDisabled: monitorData.disabled ?? false
    readonly property var availableModes: monitorData.availableModes ?? []
    readonly property real scaleVal: (monitorData.scale ?? 0) > 0 ? monitorData.scale : 1
    readonly property string currentMode: {
        const w = monitorData.width, h = monitorData.height, r = monitorData.refreshRate;
        return availableModes.find(m => {
            const match = m.match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
            return match && parseInt(match[1]) === w && parseInt(match[2]) === h && Math.abs(parseFloat(match[3]) - r) < 0.5;
        }) ?? (availableModes[0] ?? `${w}x${h}@${r}Hz`);
    }
    readonly property bool isInternal: name.startsWith("eDP") || name.startsWith("LVDS")
    readonly property bool hasExternal: allMonitors.some(m => !m.name.startsWith("eDP") && !m.name.startsWith("LVDS"))
    readonly property string home: Quickshell.env("HOME")
    readonly property string markerFile: `${home}/.config/hypr/.auto-disable-${name}`

    property bool autoDisableEnabled: false

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

    // Apply a change at runtime (via the Lua API — `hyprctl keyword monitor`
    // does not work with the Lua parser) AND persist it to monitors.d so it
    // survives reboot. Manual disable is runtime-only (not persisted) to avoid
    // booting into a black screen.
    function applyMonitor(mode: string, scale: real, enabled: bool): void {
        let lua;
        let persist = "";
        if (!enabled) {
            lua = `hl.monitor({ output='${root.name}', disabled=true })`;
        } else {
            let modeStr;
            // Always auto-position: changing resolution/refresh/scale should
            // never move the monitor, and persisting an absolute coordinate can
            // pin it to a stale offset from a previous layout.
            const pos = "auto";
            modeStr = root.isDisabled ? "preferred" : mode.replace(/Hz$/, "");
            const scaleStr = (scale > 0 ? scale : 1).toFixed(2);
            // `disabled=false` is required to actually re-enable a disabled output;
            // setting mode/scale alone does not clear the disabled flag.
            lua = `hl.monitor({ output='${root.name}', disabled=false, mode='${modeStr}', position='${pos}', scale=${scaleStr} })`;
            persist = `${modeStr},${pos},${scaleStr}`;
        }

        Quickshell.execDetached(["hyprctl", "eval", lua]);
        if (persist) {
            const dir = `${root.home}/.config/hypr/monitors.d`;
            Quickshell.execDetached(["sh", "-c", `mkdir -p '${dir}' && printf '%s' '${persist}' > '${dir}/${root.name}.conf'`]);
        }
        root.applied();
    }

    SectionHeader {
        text: root.name + (root.monitorData.description ? ` — ${root.monitorData.description}` : "") + (root.isDisabled ? qsTr(" (disabled)") : "")
    }

    ToggleRow {
        Layout.fillWidth: true
        first: true
        text: qsTr("Enabled")
        subtext: qsTr("Output active")
        checked: !root.isDisabled
        onToggled: root.applyMonitor(root.currentMode, root.scaleVal, checked)
    }

    ToggleRow {
        Layout.fillWidth: true
        visible: root.isInternal
        text: qsTr("Auto-disable when external connected")
        subtext: qsTr("Turns this screen off while an external is plugged in, back on when unplugged")
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
        label: qsTr("Resolution & refresh rate")
        subtext: root.currentMode
        menuItems: modeVariants.instances
        active: modeVariants.instances.find(i => i.text === root.currentMode) ?? modeVariants.instances[0] ?? null
        onSelected: item => root.applyMonitor(item.text, root.scaleVal, true)
    }

    StepperRow {
        Layout.fillWidth: true
        last: true
        enabled: !root.isDisabled
        opacity: root.isDisabled ? 0.5 : 1
        label: qsTr("Scale")
        subtext: qsTr("Display scaling factor")
        value: root.scaleVal
        from: 0.25
        to: 3.0
        stepSize: 0.25
        onMoved: v => root.applyMonitor(root.currentMode, v, true)
    }
}
