pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property string role
    required property string content
    property bool streaming: false

    readonly property bool isUser: role === "user"

    implicitWidth: parent?.width ?? 0
    implicitHeight: bubble.implicitHeight

    StyledRect {
        id: bubble

        anchors.right: root.isUser ? parent.right : undefined
        anchors.left: root.isUser ? undefined : parent.left

        radius: Tokens.rounding.large
        color: root.isUser ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHigh

        implicitWidth: Math.min(root.width * 0.85, label.implicitWidth + padding * 2)
        implicitHeight: label.implicitHeight + padding * 2

        readonly property int padding: Tokens.padding.normal

        StyledText {
            id: label

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: bubble.padding

            width: Math.min(root.width * 0.85, implicitWidth) - bubble.padding * 2

            text: root.content + (root.streaming ? " ▋" : "")
            textFormat: root.isUser ? Text.PlainText : Text.MarkdownText
            wrapMode: Text.Wrap
            color: root.isUser ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }
}
