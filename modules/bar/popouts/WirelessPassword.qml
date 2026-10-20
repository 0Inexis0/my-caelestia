pragma ComponentBehavior: Bound

import QtQuick
import qs.components.controls

WifiConnectionForm {
    id: root

    required property PopoutState popouts
    readonly property bool shouldBeVisible: popouts.currentName === "wirelesspassword"

    function closeDialog(): void {
        reset();
        root.popouts.currentName = "network";
    }

    minimumWidth: 380
    onShouldBeVisibleChanged: {
        reset();
        if (shouldBeVisible)
            Qt.callLater(() => fields.focusInput());
    }
    onConnected: {
        if (shouldBeVisible)
            closeDialog();
    }
    onCancelled: closeDialog()
    Keys.onEscapePressed: closeDialog()
}
