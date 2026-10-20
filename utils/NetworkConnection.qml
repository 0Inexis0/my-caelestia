pragma Singleton

import QtQuick
import qs.services

QtObject {
    id: root

    function requestCredentials(network, session, onPasswordNeeded): void {
        if (session && session.network) {
            session.network.pendingNetwork = network;
            session.network.showPasswordDialog = true;
        } else if (onPasswordNeeded) {
            onPasswordNeeded(network);
        }
    }

    function handleConnect(network, session, onPasswordNeeded): void {
        // Keep the current connection while the user is entering credentials.
        // NetworkManager switches devices when activation starts.
        if (!network)
            return;
        connectToNetwork({
            ssid: network.ssid,
            bssid: network.bssid || "",
            security: network.security || "",
            isSecure: network.isSecure
        }, session, onPasswordNeeded);
    }

    function connectToNetwork(network, session, onPasswordNeeded): void {
        if (!network)
            return;
        if (Nmcli.isEnterprise(network)) {
            const uuid = Nmcli.savedConnectionUuids[network.ssid];
            if (uuid) {
                Nmcli.executeCommand(["--wait", "90", "connection", "up", "uuid", uuid], result => {
                    if (!result.success)
                        root.requestCredentials(network, session, onPasswordNeeded);
                });
            } else {
                requestCredentials(network, session, onPasswordNeeded);
            }
        } else if (network.isSecure && !Nmcli.hasSavedProfile(network.ssid)) {
            requestCredentials(network, session, onPasswordNeeded);
        } else {
            Nmcli.connectToNetwork(network.ssid, "", network.bssid, result => {
                if (!result.success && result.needsPassword)
                    root.requestCredentials(network, session, onPasswordNeeded);
            });
        }
    }

    function connectWithPassword(network, password, onResult): void {
        if (network)
            Nmcli.connectToNetwork(network.ssid, password || "", network.bssid || "", onResult || null);
    }
}
