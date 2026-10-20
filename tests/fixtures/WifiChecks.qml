pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.components.controls
import qs.services
import qs.modules.bar as Bar
import qs.modules.drawers as Drawers
import qs.modules.nexus
import qs.modules.bar.popouts as Popouts
import qs.modules.bar.popouts
import qs.modules.nexus.pages.network

PanelWindow {
    id: root

    property int phase: 0
    property int calls: 0
    property var reply
    property var pageStack
    property var submitted

    function check(ok, message): void {
        if (!ok)
            throw new Error(message);
    }

    function find(item, name): var {
        if (item.objectName === name)
            return item;
        for (const child of item.children || []) {
            const found = find(child, name);
            if (found)
                return found;
        }
        return null;
    }

    function fill(form): void {
        find(form, "wifiIdentity").text = "student";
        find(form, "wifiPassword").text = "x";
    }

    implicitWidth: 1
    implicitHeight: 1
    color: "transparent"
    mask: Region {}

    ScreenState {
        id: hoverState

        modelData: Quickshell.screens[0]
    }
    Popouts.Wrapper {
        id: hoverPopouts

        screen: Quickshell.screens[0]
        offsetScale: 1
        visible: false
    }
    Bar.BarWrapper {
        id: hoverBar

        screen: Quickshell.screens[0]
        screenState: hoverState
        popouts: hoverPopouts
        fullscreen: false
        visible: false
    }
    Bar.Bar {
        id: hoverBarContent

        screen: Quickshell.screens[0]
        screenState: hoverState
        popouts: hoverPopouts
        fullscreen: false
        visible: false
    }
    Drawers.Interactions {
        id: hoverInteractions

        screen: Quickshell.screens[0]
        popouts: hoverPopouts
        screenState: hoverState
        panels: null
        bar: hoverBar
        borderThickness: 0
        fullscreen: false
        visible: false
    }

    QtObject {
        id: testNetwork

        function isEnterprise(network: var): bool {
            return Nmcli.isEnterprise(network);
        }

        function connectEnterprise(ssid: string, credentials: var, hidden: bool, callback: var): void {
            root.calls++;
            root.submitted = credentials;
            root.reply = callback;
        }
    }

    NexusState {
        id: testNexusState
    }
    PopoutState {
        id: testPopouts

        currentName: "wirelesspassword"
    }
    WirelessPassword {
        id: quick

        networkService: testNetwork
        popouts: testPopouts
        network: ({
                ssid: "School test",
                security: "WPA2 802.1X",
                isSecure: true
            })
    }
    AddNetworkPage {
        id: manual

        nState: testNexusState
        width: 800
        height: 700
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            try {
                if (root.phase === 0) {
                    hoverPopouts.currentName = "wirelesspassword";
                    hoverPopouts.hasCurrent = true;
                    root.check(hoverPopouts.interactionActive, "password dialog holds interaction");
                    hoverInteractions.dismissPopoutOnLeave();
                    root.check(hoverPopouts.hasCurrent, "pointer exit keeps password dialog open");
                    hoverInteractions.updatePopoutHover(10000, 10000);
                    root.check(hoverPopouts.hasCurrent, "moving outside resized dialog keeps it open");
                    hoverInteractions.updatePopoutHover(-1, -100);
                    hoverBarContent.checkPopout(-100);
                    root.check(hoverPopouts.hasCurrent && hoverPopouts.currentName === "wirelesspassword", "bar hover cannot replace password dialog");
                    hoverPopouts.close();
                    root.check(!hoverPopouts.interactionActive, "explicit dismissal releases interaction");
                    hoverPopouts.currentName = "network";
                    hoverPopouts.hasCurrent = true;
                    hoverInteractions.dismissPopoutOnLeave();
                    root.check(!hoverPopouts.hasCurrent, "normal network popout still closes on pointer exit");
                    root.check(!quick.fields.advanced, "advanced settings initially collapsed");
                    root.check(!find(quick, "wifiConnect").disabled, "connect button accepts validation clicks");
                    find(quick, "wifiConnect").clicked();
                    root.check(root.calls === 0 && find(quick, "wifiIdentity").isError, "empty submission shows field error");
                    root.fill(quick);
                    root.check(quick.fields.valid, "username/password valid without a domain");
                    root.check(find(quick, "wifiPassword").echoMode === TextInput.Password, "masked password");
                    find(quick, "wifiConnect").clicked();
                    root.check(root.calls === 1 && quick.connecting, "quick connect starts request");
                    root.check(root.submitted.domain === "" && root.submitted.eap === "peap", "simple PEAP request");
                    root.check(find(quick, "wifiConnect").disabled, "duplicate requests disabled");
                    root.reply({
                        success: false,
                        error: "Test authentication error"
                    });
                    root.check(!quick.connecting && quick.errorMessage === "Test authentication error", "failure displayed and retry enabled");
                    root.check(quick.fields.password === "x", "failure keeps inputs for correction");
                    find(quick, "wifiAdvanced").clicked();
                    root.check(quick.fields.advanced, "advanced toggle opens");
                    find(quick, "wifiAdvanced").clicked();
                    root.check(!quick.fields.advanced, "advanced toggle closes");
                    find(quick, "wifiPassword").accepted();
                    root.check(root.calls === 2, "Enter submits retry");
                    quick.closeDialog();
                    root.reply({
                        success: false,
                        error: "late result"
                    });
                    root.check(quick.errorMessage === "" && quick.fields.password === "", "cancel clears secret and ignores late callback");
                    root.pageStack = PageCompRegistry.pageComps[2].createObject(root.contentItem, {
                        nState: testNexusState,
                        visible: false,
                        width: 800,
                        height: 700
                    });
                    const ap = {
                        ssid: "School test",
                        security: "WPA2 802.1X",
                        isSecure: true,
                        bssid: ""
                    };
                    testNexusState.openWifiLogin(ap);
                    ap.ssid = "changed by scan";
                    root.check(testNexusState.pendingWifiNetwork.ssid === "School test", "login owns network snapshot");
                    root.check(testNexusState.subPageIdxStack[0] === 7, "network selection opens dedicated login page");
                    root.check(root.pageStack.currentItem.title !== manual.title, "login is not Add network");
                } else if (root.phase === 1) {
                    const form = root.pageStack.currentItem.contentChild;
                    root.check(form.network.ssid === "School test", "settings preserves selected SSID");
                    form.networkService = testNetwork;
                    root.fill(form);
                    find(form, "wifiConnect").clicked();
                    root.check(root.calls === 3 && form.connecting, "settings connect starts request");
                    root.reply({
                        success: true
                    });
                    root.check(testNexusState.subPageIdxStack.length === 0, "successful settings connection returns to list");
                } else {
                    root.check(root.pageStack.depth === 1, "settings stack returns to network list");
                    testNexusState.openWifiLogin({
                        ssid: "Another school",
                        security: "802.1X",
                        isSecure: true
                    });
                    testNexusState.openWifiLogin({
                        ssid: "Another school",
                        security: "802.1X",
                        isSecure: true
                    });
                    root.check(testNexusState.subPageIdxStack.length === 1, "repeated selection does not stack login pages");
                    root.check(root.pageStack.currentItem.contentChild.fields.password === "", "new login has no stale password");
                    root.check(quick.width >= 380, "quick dialog retains readable width");
                    const preview = Quickshell.env("WIFI_UI_PREVIEW");
                    if (preview)
                        quick.grabToImage(image => image.saveToFile(preview));
                    console.info("Wi-Fi interaction checks passed");
                    stop();
                }
                root.phase++;
            } catch (error) {
                console.error("Wi-Fi interaction checks FAILED: " + error);
                stop();
            }
        }
    }
}
