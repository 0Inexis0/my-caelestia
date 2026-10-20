pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils

ColumnLayout {
    id: root

    required property PopoutState popouts
    property var network: null
    property bool connecting: false
    property string errorMessage: ""
    readonly property bool shouldBeVisible: popouts.currentName === "wirelesspassword"

    function closeDialog(): void {
        credentials.clearSecret();
        root.popouts.currentName = "network";
    }

    function submit(): void {
        if (root.connecting || !root.network || !credentials.valid)
            return;
        root.connecting = true;
        root.errorMessage = "";
        const done = result => {
            if (!root)
                return;
            root.connecting = false;
            credentials.clearSecret();
            if (result?.success && !result.error) {
                if (root.shouldBeVisible)
                    root.closeDialog();
            } else {
                root.errorMessage = result?.error || Tr.tr("Connection failed. Please check your password and try again.");
            }
        };
        if (credentials.enterprise)
            Nmcli.connectEnterprise(root.network.ssid, credentials.credentials, false, done);
        else
            NetworkConnection.connectWithPassword(root.network, credentials.password, done);
    }

    spacing: Tokens.spacing.medium
    implicitWidth: 440
    onShouldBeVisibleChanged: {
        credentials.clearSecret();
        if (shouldBeVisible)
            Qt.callLater(() => credentials.focusInput());
    }
    Component.onCompleted: Qt.callLater(() => credentials.focusInput())
    Keys.onEscapePressed: closeDialog()

    StyledText {
        Layout.fillWidth: true
        text: root.network?.ssid ?? Tr.tr("Connect to network")
        font: Tokens.font.title.medium
        elide: Text.ElideRight
    }

    Flickable {
        id: fieldsViewport

        Layout.fillWidth: true
        implicitHeight: Math.min(credentials.implicitHeight, 480)
        contentWidth: width
        contentHeight: credentials.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        WifiCredentials {
            id: credentials

            width: fieldsViewport.width
            enabled: !root.connecting
            enterprise: Nmcli.isEnterprise(root.network)
            onAccepted: root.submit()
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: !!root.errorMessage || root.connecting
        text: root.connecting ? Tr.tr("Connecting...") : root.errorMessage
        color: root.errorMessage ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.alignment: Qt.AlignRight
        spacing: Tokens.spacing.small

        TextButton {
            type: TextButton.Tonal
            text: Tr.trCtx("Cancel", "button")
            onClicked: root.closeDialog()
        }

        TextButton {
            text: Tr.tr("Connect")
            enabled: !root.connecting && !!root.network && credentials.valid
            onClicked: root.submit()
        }
    }
}
