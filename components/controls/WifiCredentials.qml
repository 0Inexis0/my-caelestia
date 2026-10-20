pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.modules.nexus.common

ColumnLayout {
    id: root

    property bool enterprise: false
    property bool advanced: false
    readonly property string password: passwordField.text
    readonly property bool valid: password.length >= (enterprise ? 1 : 8) && (!enterprise || (identityField.text.trim().length > 0))
    readonly property var credentials: ({
            identity: identityField.text.trim(),
            password: password,
            eap: eapSelect.active?.value ?? "peap",
            phase2: eapSelect.active === ttlsItem ? (phaseSelect.active?.value ?? "mschapv2") : "mschapv2",
            anonymousIdentity: anonymousField.text.trim(),
            domain: domainField.text.trim(),
            caCert: caField.text.trim()
        })

    signal accepted

    function validate(): bool {
        identityField.isError = enterprise && !identityField.text.trim();
        passwordField.isError = password.length < (enterprise ? 1 : 8);
        if (identityField.isError)
            identityField.forceActiveFocus();
        else if (passwordField.isError)
            passwordField.forceActiveFocus();
        return valid;
    }

    function clearSecret(): void {
        passwordField.text = "";
    }

    function focusInput(): void {
        if (enterprise)
            identityField.forceActiveFocus();
        else
            passwordField.forceActiveFocus();
    }

    spacing: Tokens.spacing.medium

    StyledTextField {
        id: identityField

        objectName: "wifiIdentity"
        Layout.fillWidth: true
        visible: root.enterprise
        placeholderText: Tr.tr("Username")
        errorText: Tr.tr("Enter your username")
        leadingIcon: "person"
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
        onAccepted: passwordField.forceActiveFocus()
    }

    StyledTextField {
        id: passwordField

        objectName: "wifiPassword"
        Layout.fillWidth: true
        placeholderText: Tr.tr("Password")
        leadingIcon: "key"
        echoMode: TextInput.Password
        errorText: root.enterprise ? Tr.tr("Enter your password") : Tr.tr("Password must be at least 8 characters")
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
        onAccepted: root.accepted()
    }

    IconTextButton {
        objectName: "wifiAdvanced"
        visible: root.enterprise
        Layout.alignment: Qt.AlignLeft
        type: TextButton.Text
        text: Tr.tr("Advanced settings")
        icon: root.advanced ? "expand_less" : "expand_more"
        onClicked: root.advanced = !root.advanced
    }

    SelectRow {
        id: eapSelect

        visible: root.enterprise && root.advanced
        label: Tr.tr("Authentication")
        fallbackText: "PEAP"
        menuItems: [
            MenuItem {
                text: "PEAP"
                value: "peap"
            },
            MenuItem {
                id: ttlsItem

                text: "TTLS"
                value: "ttls"
            }
        ]
    }

    SelectRow {
        id: phaseSelect

        visible: root.enterprise && root.advanced && eapSelect.active === ttlsItem
        label: Tr.tr("Inner authentication")
        fallbackText: "MSCHAPv2"
        menuItems: [
            MenuItem {
                text: "MSCHAPv2"
                value: "mschapv2"
            },
            MenuItem {
                text: "PAP"
                value: "pap"
            }
        ]
    }

    StyledTextField {
        id: domainField

        objectName: "wifiDomain"
        Layout.fillWidth: true
        visible: root.enterprise && root.advanced
        placeholderText: Tr.tr("Server domain (optional)")
        supportingText: Tr.tr("Use this if your school specifies a server domain")
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
        onAccepted: root.accepted()
    }

    StyledTextField {
        id: caField

        Layout.fillWidth: true
        visible: root.enterprise && root.advanced
        placeholderText: Tr.tr("CA certificate path (optional)")
        supportingText: Tr.tr("Leave empty to use system certificates")
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
    }

    StyledTextField {
        id: anonymousField

        Layout.fillWidth: true
        visible: root.enterprise && root.advanced
        placeholderText: Tr.tr("Anonymous identity (optional)")
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
        onAccepted: root.accepted()
    }
}
