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
    readonly property string password: passwordField.text
    readonly property bool valid: password.length >= (enterprise ? 1 : 8) && (!enterprise || (identityField.text.trim().length > 0 && domainField.text.trim().length > 0))
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
        placeholderText: Tr.tr("Username / identity")
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
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
        onAccepted: root.accepted()
    }

    SelectRow {
        id: eapSelect

        visible: root.enterprise
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

        visible: root.enterprise && eapSelect.active === ttlsItem
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
        visible: root.enterprise
        placeholderText: Tr.tr("Authentication server domain")
        supportingText: Tr.tr("Use the domain supplied by your school or organisation")
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
        onAccepted: root.accepted()
    }

    StyledTextField {
        id: caField

        Layout.fillWidth: true
        visible: root.enterprise
        placeholderText: Tr.tr("CA certificate path (optional)")
        supportingText: Tr.tr("Leave empty to use system certificates")
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
    }

    StyledTextField {
        id: anonymousField

        Layout.fillWidth: true
        visible: root.enterprise
        placeholderText: Tr.tr("Anonymous identity (optional)")
        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
        onAccepted: root.accepted()
    }
}
