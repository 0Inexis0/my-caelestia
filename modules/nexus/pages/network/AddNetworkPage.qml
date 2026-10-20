pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var network: nState.pendingWifiNetwork
    readonly property bool enterprise: network ? Nmcli.isEnterprise(network) : securitySelect.active === enterpriseItem
    readonly property bool secured: network ? network.isSecure : securitySelect.active !== noneItem
    property bool connecting: false
    property string errorMessage: ""

    function submit(): void {
        const ssid = ssidField.text;
        if (root.connecting || !ssid || (root.secured && !credentials.valid))
            return;
        root.errorMessage = "";
        root.connecting = true;
        const done = result => {
            if (!root)
                return;
            root.connecting = false;
            credentials.clearSecret();
            if (result && result.success && !result.error) {
                root.nState.closeSubPage();
            } else {
                root.errorMessage = result?.error || Tr.tr("Connection failed. Please check your password and try again.");
            }
        };
        if (root.enterprise)
            Nmcli.connectEnterprise(ssid, credentials.credentials, hiddenToggle.checked, done);
        else if (root.network)
            NetworkConnection.connectWithPassword(root.network, credentials.password, done);
        else
            Nmcli.addHiddenNetwork(ssid, root.secured ? credentials.password : "", root.secured ? "wpa" : "none", hiddenToggle.checked, done);
    }

    title: network ? Tr.tr("Connect to network") : Tr.tr("Add network")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        StyledTextField {
            id: ssidField

            Layout.fillWidth: true
            text: root.network?.ssid ?? ""
            readOnly: !!root.network || root.connecting
            placeholderText: Tr.tr("Network name (SSID)")
            leadingIcon: "wifi"
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            onAccepted: root.secured ? credentials.focusInput() : root.submit()
        }

        ToggleRow {
            id: hiddenToggle

            visible: !root.network
            text: Tr.tr("Hidden network")
            checked: !root.network
            enabled: !root.connecting
        }

        SelectRow {
            id: securitySelect

            visible: !root.network
            enabled: !root.connecting
            label: Tr.tr("Security")
            fallbackText: Tr.tr("WPA/WPA2/WPA3 Personal")
            menuItems: [
                MenuItem {
                    text: Tr.tr("WPA/WPA2/WPA3 Personal")
                    icon: "lock"
                },
                MenuItem {
                    id: enterpriseItem

                    text: Tr.tr("WPA/WPA2 Enterprise")
                    icon: "school"
                },
                MenuItem {
                    id: noneItem

                    text: Tr.trCtx("None (open)", "wifi security type")
                    icon: "lock_open"
                }
            ]
        }

        WifiCredentials {
            id: credentials

            Layout.fillWidth: true
            visible: root.secured
            enabled: !root.connecting
            enterprise: root.enterprise
            onAccepted: root.submit()
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
                onClicked: {
                    credentials.clearSecret();
                    root.nState.closeSubPage();
                }
            }

            TextButton {
                text: Tr.tr("Connect")
                enabled: !root.connecting && ssidField.text.length > 0 && (!root.secured || credentials.valid)
                onClicked: root.submit()
            }
        }
    }
}
