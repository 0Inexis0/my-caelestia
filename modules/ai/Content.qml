pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property DrawerVisibilities visibilities
    required property real maxHeight
    // FileDialog instantiated in Wrapper (survives the chat closing)
    property var picker

    readonly property int padding: Tokens.padding.large
    // "" | "model" | "settings" | "history"
    property string overlay: ""

    // Common context-length presets (tokens)
    readonly property var ctxPresets: [2048, 4096, 8192, 16384, 32768, 65536, 131072]

    implicitWidth: 660
    implicitHeight: Math.min(root.maxHeight, header.implicitHeight + listWrapper.implicitHeight + inputWrapper.implicitHeight + padding * 2 + Tokens.spacing.small * 2)

    Component.onCompleted: Ollama.reloadModels()

    function fmtCtx(n: int): string {
        return n >= 1024 ? `${Math.round(n / 1024)}K` : `${n}`;
    }

    Connections {
        function onAiChanged(): void {
            if (!root.visibilities.ai)
                root.overlay = "";
        }

        target: root.visibilities
    }

    // Header
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
            Layout.maximumWidth: 200
            implicitWidth: modelRow.implicitWidth + Tokens.padding.medium * 2

            radius: Tokens.rounding.full
            color: modelMouse.containsMouse || root.overlay === "model" ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3surfaceContainerHigh

            RowLayout {
                id: modelRow

                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.small
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    Layout.fillWidth: true
                    text: Ollama.currentModel || qsTr("No models")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                }

                MaterialIcon {
                    text: root.overlay === "model" ? "expand_less" : "expand_more"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }
            }

            MouseArea {
                id: modelMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.overlay = root.overlay === "model" ? "" : "model"
            }
        }

        IconButton {
            icon: "history"
            type: IconButton.Text
            onClicked: root.overlay = root.overlay === "history" ? "" : "history"
        }

        IconButton {
            icon: "tune"
            type: IconButton.Text
            onClicked: root.overlay = root.overlay === "settings" ? "" : "settings"
        }

        IconButton {
            icon: "add_comment"
            type: IconButton.Tonal
            onClicked: {
                Ollama.newChat();
                root.overlay = "";
            }
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
            anchors.margins: Tokens.padding.medium
            clip: true
            spacing: Tokens.spacing.small

            model: Ollama.messages
            cacheBuffer: 100000

            delegate: MessageItem {
                required property var model
                width: ListView.view.width
                role: model.role
                content: model.content
                images: model.images ?? []
            }

            footer: Column {
                width: list.width
                spacing: Tokens.spacing.small
                topPadding: list.count > 0 ? Tokens.spacing.small : 0

                StyledRect {
                    width: parent.width
                    visible: Ollama.responding && Ollama.streamContent.length === 0
                    implicitHeight: thinkCol.implicitHeight + Tokens.padding.medium * 2
                    radius: Tokens.rounding.large
                    color: Colours.palette.m3surfaceContainer

                    Column {
                        id: thinkCol

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.padding.medium
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

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: list
            }

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

    // Input area (pending attachments + text row)
    Column {
        id: inputWrapper

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.padding

        spacing: Tokens.spacing.small

        Row {
            id: attachRow

            visible: Ollama.pendingImages.length > 0
            spacing: Tokens.spacing.small

            Repeater {
                model: Ollama.pendingImages

                StyledClippingRect {
                    id: thumb

                    required property string modelData
                    required property int index

                    implicitWidth: 48
                    implicitHeight: 48
                    radius: Tokens.rounding.small

                    Image {
                        anchors.fill: parent
                        source: "data:image/png;base64," + thumb.modelData
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    StyledRect {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        implicitWidth: 18
                        implicitHeight: 18
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHighest

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "close"
                            fontStyle: Tokens.font.icon.small
                            color: Colours.palette.m3onSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Ollama.removePendingImage(thumb.index)
                        }
                    }
                }
            }
        }

        StyledRect {
            id: inputBar

            anchors.left: parent.left
            anchors.right: parent.right

            radius: Tokens.rounding.full
            color: Colours.layer(Colours.palette.m3surfaceContainer, 2)

            implicitHeight: Math.max(input.implicitHeight, sendBtn.implicitHeight) + Tokens.padding.small * 2

            IconButton {
                id: attachBtn

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.small

                icon: "attach_file"
                type: IconButton.Text
                enabled: Ollama.available && !!root.picker
                onClicked: {
                    // Close the chat first so the dialog isn't occluded by the
                    // layer-shell drawer and doesn't trip the focus-grab.
                    root.picker.open();
                    root.visibilities.ai = false;
                }
            }

            StyledTextField {
                id: input

                anchors.left: attachBtn.right
                anchors.right: sendBtn.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.spacing.small
                anchors.rightMargin: Tokens.spacing.small

                topPadding: Tokens.padding.medium
                bottomPadding: Tokens.padding.medium

                placeholderText: qsTr("Message %1…").arg(Ollama.currentModel || "Ollama")
                enabled: Ollama.available

                onAccepted: {
                    if (!Ollama.responding && (text.trim() || Ollama.pendingImages.length)) {
                        Ollama.send(text);
                        text = "";
                    }
                }

                Keys.onEscapePressed: {
                    if (root.overlay)
                        root.overlay = "";
                    else
                        root.visibilities.ai = false;
                }

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
                disabled: !Ollama.responding && (!(input.text.trim() || Ollama.pendingImages.length) || !Ollama.available)

                onClicked: {
                    if (Ollama.responding) {
                        Ollama.stop();
                    } else if (input.text.trim() || Ollama.pendingImages.length) {
                        Ollama.send(input.text);
                        input.text = "";
                    }
                }
            }
        }
    }

    // ---- Overlays ----

    // Model picker
    StyledRect {
        visible: root.overlay === "model" && Ollama.models.length > 0
        z: 100

        anchors.top: header.bottom
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        anchors.topMargin: Tokens.spacing.small

        implicitWidth: 320
        implicitHeight: modelList.height + Tokens.padding.small * 2

        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainerHighest

        ListView {
            id: modelList

            x: Tokens.padding.small
            y: Tokens.padding.small
            width: parent.width - Tokens.padding.small * 2
            height: Math.min(280, contentHeight)
            clip: true
            model: Ollama.models

            delegate: StyledRect {
                id: pickerItem

                required property string modelData
                readonly property bool current: modelData === Ollama.currentModel

                width: modelList.width
                implicitHeight: pickerLabel.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.small
                color: pickerArea.containsMouse ? Colours.palette.m3surfaceContainerHigh : "transparent"

                StyledText {
                    id: pickerLabel

                    anchors.left: parent.left
                    anchors.right: checkIcon.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.small
                    anchors.rightMargin: Tokens.spacing.small

                    text: pickerItem.modelData
                    font: Tokens.font.label.medium
                    color: pickerItem.current ? Colours.palette.m3primary : Colours.palette.m3onSurface
                    elide: Text.ElideMiddle
                }

                MaterialIcon {
                    id: checkIcon

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
                        root.overlay = "";
                    }
                }
            }

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: modelList
            }
        }
    }

    // Settings
    StyledRect {
        visible: root.overlay === "settings"
        z: 100

        anchors.top: header.bottom
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        anchors.topMargin: Tokens.spacing.small

        implicitWidth: 300
        implicitHeight: settingsCol.implicitHeight + Tokens.padding.large * 2

        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainerHighest

        Column {
            id: settingsCol

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            StyledText {
                text: qsTr("Settings")
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
            }

            // Context length (snaps to presets)
            Column {
                width: parent.width
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: qsTr("Context length: %1 tokens").arg(root.fmtCtx(Ollama.numCtx))
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledSlider {
                    width: parent.width
                    value: Math.max(0, root.ctxPresets.indexOf(Ollama.numCtx)) / (root.ctxPresets.length - 1)
                    onInteraction: v => {
                        const idx = Math.round(v * (root.ctxPresets.length - 1));
                        Ollama.numCtx = root.ctxPresets[idx];
                        Ollama.persist();
                    }
                }

                Row {
                    width: parent.width

                    Repeater {
                        model: root.ctxPresets

                        StyledText {
                            required property int modelData
                            required property int index

                            width: parent.width / root.ctxPresets.length
                            horizontalAlignment: index === 0 ? Text.AlignLeft : index === root.ctxPresets.length - 1 ? Text.AlignRight : Text.AlignHCenter
                            text: root.fmtCtx(modelData)
                            font: Tokens.font.label.small
                            color: modelData === Ollama.numCtx ? Colours.palette.m3primary : Colours.palette.m3outline
                        }
                    }
                }
            }

            // Temperature
            Column {
                width: parent.width
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: qsTr("Temperature: %1").arg(Ollama.temperature.toFixed(2))
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledSlider {
                    width: parent.width
                    value: Ollama.temperature / 2
                    onInteraction: v => {
                        Ollama.temperature = v * 2;
                        Ollama.persist();
                    }
                }
            }
        }
    }

    // Chat history
    StyledRect {
        visible: root.overlay === "history"
        z: 100

        anchors.top: header.bottom
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        anchors.topMargin: Tokens.spacing.small

        implicitWidth: 360
        implicitHeight: Math.max(64, historyList.height + Tokens.padding.small * 2)

        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainerHighest

        StyledText {
            anchors.centerIn: parent
            visible: Ollama.chats.length === 0
            text: qsTr("No chats yet")
            color: Colours.palette.m3outline
            font: Tokens.font.body.small
        }

        ListView {
            id: historyList

            x: Tokens.padding.small
            y: Tokens.padding.small
            width: parent.width - Tokens.padding.small * 2
            height: Math.min(340, contentHeight)
            clip: true
            spacing: Tokens.spacing.extraSmall
            model: Ollama.chats

            delegate: StyledRect {
                id: histItem

                required property var modelData
                readonly property bool current: modelData.id === Ollama.currentChatId

                width: historyList.width
                implicitHeight: Math.max(histTitle.implicitHeight, histDel.implicitHeight) + Tokens.padding.small * 2
                radius: Tokens.rounding.small
                color: histItem.current ? Colours.palette.m3secondaryContainer : histArea.containsMouse ? Colours.palette.m3surfaceContainerHigh : "transparent"

                StyledText {
                    id: histTitle

                    anchors.left: parent.left
                    anchors.right: histDel.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.small
                    anchors.rightMargin: Tokens.spacing.small

                    text: histItem.modelData.title || qsTr("New chat")
                    font: Tokens.font.label.medium
                    color: histItem.current ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    elide: Text.ElideRight
                }

                IconButton {
                    id: histDel

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: Tokens.padding.extraSmall

                    icon: "delete"
                    type: IconButton.Text
                    onClicked: Ollama.deleteChat(histItem.modelData.id)
                }

                MouseArea {
                    id: histArea

                    anchors.fill: parent
                    anchors.rightMargin: histDel.width
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Ollama.loadChat(histItem.modelData.id);
                        root.overlay = "";
                    }
                }
            }

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: historyList
            }
        }
    }
}
