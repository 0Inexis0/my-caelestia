import QtQuick
import Quickshell
import qs.components.controls
import "../../utils/Display.js" as Display

PanelWindow {
    color: "transparent"
    mask: Region {}
    implicitWidth: 1
    implicitHeight: 1

    StyledSpinBox {
        id: scale
        opacity: 0
        from: 0.25
        to: 3
        stepSize: 0.25
        value: 1
    }

    Component.onCompleted: Qt.callLater(() => {
        try {
            for (const size of [[1366,768], [1920,1080], [2560,1600], [3840,2160]]) {
                for (const factor of Display.scales(size[0], size[1], 1)) {
                    if (Math.abs(size[0] / factor - Math.round(size[0] / factor)) > 0.0001 || Math.abs(size[1] / factor - Math.round(size[1] / factor)) > 0.0001)
                        throw new Error("Invalid logical dimensions");
                }
            }
            scale.increase();
            if (scale.value !== 1.25 || scale.decimals < 2) throw new Error("1.25 lost precision");
            scale.increase();
            scale.increase();
            if (scale.value !== 1.75) throw new Error("1.75 lost precision");
            scale.decrease();
            if (scale.value !== 1.5) throw new Error("decrease lost precision");
            console.info("Display interaction checks passed");
        } catch (error) {
            console.error("Display interaction checks FAILED: " + error);
        }
    })
}
