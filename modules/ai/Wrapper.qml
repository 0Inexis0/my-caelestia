pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.services
import qs.utils

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState

    // Lives here (not in Content) so it survives the chat closing while picking
    readonly property FileDialog imagePicker: FileDialog {
        title: qsTr("Attach an image")
        filterLabel: qsTr("Image files")
        filters: Images.validImageExtensions
        onAccepted: path => {
            Ollama.encodeAndAttach(path);
            root.screenState.ai = true;
        }
        onRejected: root.screenState.ai = true
    }

    readonly property bool shouldBeActive: screenState.ai

    readonly property real maxHeight: Math.min(740, screen.height - Config.border.thickness * 2 - Tokens.padding.extraLarge * 2)

    property real offsetScale: shouldBeActive ? 0 : 1

    onShouldBeActiveChanged: {
        if (shouldBeActive)
            implicitHeight = Qt.binding(() => content.implicitHeight);
        else
            implicitHeight = implicitHeight; // Break binding during close anim
    }

    visible: offsetScale < 1
    anchors.bottomMargin: (-implicitHeight - 5) * offsetScale
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 660
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    Loader {
        id: content

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            screenState: root.screenState
            maxHeight: root.maxHeight
            picker: root.imagePicker
        }
    }
}
