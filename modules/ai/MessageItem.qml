pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property string role
    required property string content
    property var images: []
    property bool streaming: false

    readonly property bool isUser: role === "user"
    readonly property real maxBubbleWidth: width * 0.85

    implicitWidth: parent?.width ?? 0
    implicitHeight: bubble.implicitHeight

    StyledRect {
        id: bubble

        anchors.right: root.isUser ? parent.right : undefined
        anchors.left: root.isUser ? undefined : parent.left

        radius: Tokens.rounding.large
        color: root.isUser ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHigh

        readonly property int padding: Tokens.padding.medium

        implicitWidth: Math.min(root.maxBubbleWidth, col.implicitWidth + padding * 2)
        implicitHeight: col.implicitHeight + padding * 2

        Column {
            id: col

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: bubble.padding
            spacing: Tokens.spacing.small

            Row {
                spacing: Tokens.spacing.small
                visible: root.images.length > 0

                Repeater {
                    model: root.images

                    StyledClippingRect {
                        required property string modelData

                        implicitWidth: 140
                        implicitHeight: 140
                        radius: Tokens.rounding.small

                        Image {
                            anchors.fill: parent
                            source: "data:image/png;base64," + modelData
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }
                }
            }

            StyledText {
                id: label

                visible: root.content.length > 0 || root.streaming
                width: Math.min(implicitWidth, root.maxBubbleWidth - bubble.padding * 2)

                text: root.content + (root.streaming ? " ▋" : "")
                textFormat: root.isUser ? Text.PlainText : Text.MarkdownText
                wrapMode: Text.Wrap
                color: root.isUser ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
        }
    }
}
