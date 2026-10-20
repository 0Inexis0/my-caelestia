import QtQuick
import Quickshell
import Quickshell.Bluetooth

QtObject {
    property ShellScreen screen
    property bool isWindow
    property bool animatingContainer
    property int currentPageIdx
    property list<int> subPageIdxStack
    property bool searchOpen

    property string selectedWallpaperCategory
    property BluetoothDevice selectedBtDevice
    property DesktopEntry selectedApp
    property int editingVpnIndex: -1
    property string selectedNetworkSsid
    property string selectedEthernetInterface
    property bool networkDetailsFromSaved
    property var pendingWifiNetwork: null

    signal close
    signal subPageOpened(idx: int)
    signal subPageClosed

    function openWifiLogin(network: var): void {
        // Own the selected values: scan updates may destroy an AccessPoint.
        pendingWifiNetwork = {
            ssid: network.ssid,
            bssid: network.bssid || "",
            security: network.security || "",
            isSecure: network.isSecure
        };
        if (subPageIdxStack[subPageIdxStack.length - 1] !== 7)
            openSubPage(7);
    }

    function openSubPage(idx: int): void {
        subPageIdxStack.push(idx);
        subPageOpened(idx);
    }

    function closeSubPage(): void {
        subPageClosed();
        subPageIdxStack.pop();
    }

    onCurrentPageIdxChanged: subPageIdxStack.length = 0
}
