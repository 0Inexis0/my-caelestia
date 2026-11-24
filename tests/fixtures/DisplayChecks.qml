pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components.controls
import qs.modules.nexus.pages.display
import "../../utils/Display.js" as Display

FloatingWindow {
    id: root

    property string requestedMode
    property int requests

    function check(ok: bool, message: string): void {
        if (!ok)
            throw new Error(message);
    }

    function checkMode(mode: string, panelDisabled: bool, outputDisabled: bool, mirrorOf: string): void {
        displayMode.monitorList = [
            {
                name: "eDP-1",
                disabled: panelDisabled
            },
            {
                name: "DP-1",
                disabled: outputDisabled,
                mirrorOf: mirrorOf
            },
            {
                name: "HEADLESS-1",
                disabled: false
            }
        ];
        check(displayMode.visible, "Both physical outputs show the mode row");
        check(displayMode.active.value === mode, "Wrong active mode: expected " + mode);
    }

    color: "transparent"
    mask: Region {}
    implicitWidth: 1
    implicitHeight: 1

    Component.onCompleted: Qt.callLater(() => {
        try {
            for (const size of [[1366, 768], [1920, 1080], [2560, 1600], [3840, 2160]]) {
                for (const factor of Display.scales(size[0], size[1], 1)) {
                    root.check(Math.abs(size[0] / factor - Math.round(size[0] / factor)) <= 0.0001 && Math.abs(size[1] / factor - Math.round(size[1] / factor)) <= 0.0001, "Invalid logical dimensions");
                }
            }
            scale.increase();
            root.check(scale.value === 1.25 && scale.decimals >= 2, "1.25 lost precision");
            scale.increase();
            scale.increase();
            root.check(scale.value === 1.75, "1.75 lost precision");
            scale.decrease();
            root.check(scale.value === 1.5, "decrease lost precision");
            root.check(!displayMode.visible, "No physical outputs hide the mode row");
            root.checkMode("internal", false, true, "");
            root.checkMode("external", true, false, "");
            root.checkMode("extend", false, false, "");
            root.checkMode("mirror", false, false, "eDP-1");
            const modes = ["internal", "external", "extend", "mirror"];
            for (let i = 0; i < modes.length; i++) {
                displayMode.selected(displayMode.menuItems[i]);
                root.check(root.requestedMode === modes[i] && root.requests === i + 1, "Wrong request for " + modes[i]);
                root.check(displayMode.active.value === "mirror", "Selection changed the active mode before the output state changed");
            }
            displayMode.enabled = false;
            displayMode.selected(displayMode.menuItems[0]);
            root.check(root.requests === 4 && root.requestedMode === "mirror", "Disabled row sent another request");
            console.info("Display interaction checks passed");
        } catch (error) {
            console.error("Display interaction checks FAILED: " + error);
        }
    })

    StyledSpinBox {
        id: scale

        opacity: 0
        from: 0.25
        to: 3
        stepSize: 0.25
        value: 1
    }

    DisplayModeRow {
        id: displayMode

        monitorList: []
        onLayoutRequested: mode => {
            root.requests++;
            root.requestedMode = mode;
        }
    }
}
