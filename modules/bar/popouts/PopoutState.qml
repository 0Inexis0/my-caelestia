import QtQuick

QtObject {
    property string currentName
    property bool hasCurrent
    readonly property bool interactionActive: hasCurrent && currentName === "wirelesspassword"

    signal detachRequested(mode: string)
}
