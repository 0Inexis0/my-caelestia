pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Caelestia
import Caelestia.I18n

Singleton {
    id: root

    property string devicePath: ""
    readonly property bool busy: pairing.running

    signal connected(string path)

    function start(device: BluetoothDevice): void {
        if (busy || !device)
            return;
        devicePath = device.dbusPath;
        pairing.running = true;
    }

    Process {
        id: pairing

        command: ["python3", decodeURIComponent(Qt.resolvedUrl("bluetooth_pair.py").toString().replace(/^file:\/\//, "")), root.devicePath]
        stderr: StdioCollector {
            id: errors
        }
        onExited: code => {
            if (code === 0)
                root.connected(root.devicePath);
            else
                Toaster.toast(Tr.tr("Bluetooth connection failed"), errors.text.trim(), "bluetooth_disabled");
            root.devicePath = "";
        }
    }
}
