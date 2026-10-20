pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.utils

ColumnLayout {
    id: root

    property var network: null
    property var networkService: Nmcli
    property bool connecting: false
    property string errorMessage: ""
    property int attempt: 0
    property int minimumWidth: 0
    readonly property alias fields: credentials

    signal connected
    signal cancelled

    function reset(): void {
        attempt++;
        connecting = false;
        errorMessage = "";
        credentials?.clearSecret();
    }

    function submit(): void {
        if (connecting || !network || !credentials.validate())
            return;
        connecting = true;
        errorMessage = "";
        const currentAttempt = ++attempt;
        const done = result => {
            if (!root || currentAttempt !== root.attempt)
                return;
            root.connecting = false;
            if (result?.success) {
                credentials.clearSecret();
                if (result.error)
                    root.errorMessage = result.error;
                else
                    root.connected();
            } else {
                root.errorMessage = result?.error || Tr.tr("Connection failed. Please check your password and try again.");
            }
        };
        if (credentials.enterprise)
            root.networkService.connectEnterprise(network.ssid, credentials.credentials, false, done);
        else
            NetworkConnection.connectWithPassword(network, credentials.password, done);
    }

    spacing: Tokens.spacing.medium
    onNetworkChanged: reset()
    Component.onCompleted: Qt.callLater(() => credentials.focusInput())

    StyledText {
        Layout.fillWidth: true
        Layout.minimumWidth: root.minimumWidth
        text: root.network?.ssid ?? ""
        font: Tokens.font.title.medium
        elide: Text.ElideRight
    }

    Flickable {
        id: fieldsViewport

        Layout.fillWidth: true
        implicitHeight: Math.min(credentials.implicitHeight + Tokens.padding.medium * 2, 480)
        contentWidth: width
        contentHeight: credentials.implicitHeight + Tokens.padding.medium * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        WifiCredentials {
            id: credentials

            width: fieldsViewport.width
            y: Tokens.padding.medium
            enabled: !root.connecting
            enterprise: root.networkService.isEnterprise(root.network)
            onAccepted: root.submit()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.connecting || !!root.errorMessage
        spacing: Tokens.spacing.small

        LoadingIndicator {
            visible: root.connecting
            implicitSize: Tokens.font.body.medium.pointSize
        }

        StyledText {
            Layout.fillWidth: true
            text: root.connecting ? Tr.tr("Connecting...") : root.errorMessage
            color: root.errorMessage ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WordWrap
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignRight
        spacing: Tokens.spacing.small

        TextButton {
            type: TextButton.Tonal
            text: Tr.trCtx("Cancel", "button")
            onClicked: {
                root.reset();
                root.cancelled();
            }
        }

        TextButton {
            objectName: "wifiConnect"
            text: Tr.tr("Connect")
            disabled: root.connecting || !root.network
            onClicked: root.submit()
        }
    }
}
