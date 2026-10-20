pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.I18n
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Connect to network")
    isSubPage: true

    WifiConnectionForm {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: Math.min(root.cappedWidth, 440)
        network: root.nState.pendingWifiNetwork
        onConnected: root.nState.closeSubPage()
        onCancelled: root.nState.closeSubPage()
    }
}
