pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property DrawerVisibilities visibilities
    required property real maxHeight

    readonly property int padding: Tokens.padding.large
    property bool modelPickerOpen: false

    implicitWidth: 660
    implicitHeight: Math.min(root.maxHeight, header.implicitHeight + listWrapper.implicitHeight + inputWrapper.implicitHeight + padding * 2 + Tokens.spacing.small * 2)

    Component.onCompleted: Ollama.reloadModels()

    Connections {
        function onAiChanged(): void {
            if (!root.visibilities.ai)
                root.modelPickerOpen = false;
        }

        target: root.visibilities
    }

    // Header: title, model picker, new chat, close
    RowLayout {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.padding

        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "neurology"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.large
        }

        StyledText {
            text: qsTr("Assistant")
            font: Tokens.font.title.small
            color: Colours.palette.m3onSurface
        }

        Item {
            Layout.fillWidth: true
        }

        StyledRect {
            id: modelChip

            Layout.preferredHeight: modelRow.implicitHeight + Tokens.padding.small * 2
            implicitWidth: modelRow.implicitWidth + Tokens.padding.normal * 2

            radius: Tokens.rounding.full
            color: modelMouse.containsMouse || root.modelPickerOpen ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3surfaceContainerHigh

            RowLayout {
                id: modelRow

                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: Ollama.currentModel || qsTr("No models")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                MaterialIcon {
                    text: root.modelPickerOpen ? "expand_less" : "expand_more"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }
            }

            MouseArea {
                id: modelMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.modelPickerOpen = !root.modelPickerOpen
            }
        }

        IconButton {
            icon: "add_comment"
            type: IconButton.Tonal
            onClicked: Ollama.clear()
        }

        IconButton {
            icon: "close"
            type: IconButton.Text
            onClicked: root.visibilities.ai = false
        }
    }

    // Message list
    StyledRect {
        id: listWrapper

        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Tokens.spacing.small
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainerLow

        implicitHeight: Math.max(120, root.maxHeight - header.implicitHeight - inputWrapper.implicitHeight - root.padding * 2 - Tokens.spacing.small * 2)

        StyledText {
            anchors.centerIn: parent
            visible: list.count === 0 && !Ollama.responding && !Ollama.errorMsg
            text: Ollama.available ? qsTr("Ask me anything") : qsTr("Waiting for Ollama…")
            color: Colours.palette.m3outline
            font: Tokens.font.body.medium
        }

        ListView {
            id: list

            anchors.fill: parent
            anchors.margins: Tokens.padding.normal
            clip: true
            spacing: Tokens.spacing.small

            model: Ollama.messages
            cacheBuffer: 100000

            delegate: MessageItem {
                required property var model
                width: ListView.view.width
                role: model.role
                content: model.content
            }

            footer: Column {
                width: list.width
                spacing: Tokens.spacing.small
                topPadding: list.count > 0 ? Tokens.spacing.small : 0

                // Live reasoning trace (dim) while the model thinks
                StyledRect {
                    width: parent.width
                    visible: Ollama.responding && Ollama.streamContent.length === 0
                    implicitHeight: thinkCol.implicitHeight + Tokens.padding.normal * 2
                    radius: Tokens.rounding.large
                    color: Colours.palette.m3surfaceContainer

                    Column {
                        id: thinkCol

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.padding.normal
                        spacing: Tokens.spacing.extraSmall

                        Row {
                            spacing: Tokens.spacing.extraSmall

                            MaterialIcon {
                                text: "neurology"
                                color: Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.small
                            }

                            StyledText {
                                text: qsTr("Reasoning…")
                                font: Tokens.font.label.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }

                        StyledText {
                            width: parent.width
                            visible: !!Ollama.streamThinking
                            text: Ollama.streamThinking
                            wrapMode: Text.Wrap
                            font: Tokens.font.body.small
                            color: Colours.palette.m3outline
                        }
                    }
                }

                // Streaming answer
                MessageItem {
                    width: parent.width
                    visible: Ollama.streamContent.length > 0
                    role: "assistant"
                    content: Ollama.streamContent
                    streaming: true
                }

                StyledText {
                    width: parent.width
                    visible: !!Ollama.errorMsg
                    text: "⚠ " + Ollama.errorMsg
                    color: Colours.palette.m3error
                    wrapMode: Text.Wrap
                    font: Tokens.font.body.small
                }
            }

            ScrollBar.vertical: StyledScrollBar {}

            onCountChanged: positionViewAtEnd()

            Connections {
                target: Ollama
                function onStreamContentChanged(): void {
                    list.positionViewAtEnd();
                }
                function onStreamThinkingChanged(): void {
                    list.positionViewAtEnd();
                }
            }
        }
    }

    // Input row
    StyledRect {
        id: inputWrapper

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.padding

        radius: Tokens.rounding.full
        color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

        implicitHeight: Math.max(input.implicitHeight, sendBtn.implicitHeight) + Tokens.padding.small * 2

        StyledTextField {
            id: input

            anchors.left: parent.left
            anchors.right: sendBtn.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: root.padding
            anchors.rightMargin: Tokens.spacing.small

            topPadding: Tokens.padding.medium
            bottomPadding: Tokens.padding.medium

            placeholderText: qsTr("Message %1…").arg(Ollama.currentModel || "Ollama")
            enabled: Ollama.available

            onAccepted: {
                if (!Ollama.responding && text.trim()) {
                    Ollama.send(text);
                    text = "";
                }
            }

            Keys.onEscapePressed: root.visibilities.ai = false

            Component.onCompleted: forceActiveFocus()

            Connections {
                function onAiChanged(): void {
                    if (root.visibilities.ai)
                        input.forceActiveFocus();
                }

                target: root.visibilities
            }
        }

        IconButton {
            id: sendBtn

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Tokens.padding.small

            icon: Ollama.responding ? "stop" : "arrow_upward"
            type: IconButton.Filled
            disabled: !Ollama.responding && (!input.text.trim() || !Ollama.available)

            onClicked: {
                if (Ollama.responding) {
                    Ollama.stop();
                } else if (input.text.trim()) {
                    Ollama.send(input.text);
                    input.text = "";
                }
            }
        }
    }

    // Inline model picker overlay (kept inside the layershell window, no popup surface)
    StyledRect {
        id: modelPicker

        visible: root.modelPickerOpen && Ollama.models.length > 0
        z: 100

        anchors.top: header.bottom
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        anchors.topMargin: Tokens.spacing.small

        implicitWidth: Math.max(180, pickerCol.implicitWidth + Tokens.padding.small * 2)
        implicitHeight: pickerCol.implicitHeight + Tokens.padding.small * 2

        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainerHighest

        Column {
            id: pickerCol

            anchors.centerIn: parent
            width: parent.width - Tokens.padding.small * 2

            Repeater {
                model: Ollama.models

                StyledRect {
                    id: pickerItem

                    required property string modelData
                    readonly property bool current: modelData === Ollama.currentModel

                    width: parent.width
                    implicitHeight: pickerLabel.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.small
                    color: pickerArea.containsMouse ? Colours.palette.m3surfaceContainerHigh : "transparent"

                    StyledText {
                        id: pickerLabel

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.padding.small

                        text: pickerItem.modelData
                        font: Tokens.font.label.medium
                        color: pickerItem.current ? Colours.palette.m3primary : Colours.palette.m3onSurface
                    }

                    MaterialIcon {
                        visible: pickerItem.current
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: Tokens.padding.small
                        text: "check"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                    }

                    MouseArea {
                        id: pickerArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Ollama.setModel(pickerItem.modelData);
                            root.modelPickerOpen = false;
                        }
                    }
                }
            }
        }
    }
}
