pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.modules.launcher as Launcher
import qs.modules.launcher.services

PanelWindow {
    id: root

    implicitWidth: 700
    implicitHeight: 500
    color: "transparent"
    mask: Region {}
    property int phase: 0
    property var commands: []

    function check(ok, message): void {
        if (!ok)
            throw new Error(message);
    }

    function find(item, name): var {
        if (item.objectName === name)
            return item;
        for (const child of item.children || []) {
            const result = find(child, name);
            if (result)
                return result;
        }
        return null;
    }

    ScreenState {
        id: testState
        modelData: Quickshell.screens[0]
    }

    Launcher.Content {
        id: content
        anchors.fill: parent
        screenState: testState
        panels: null
        maxHeight: 500
    }

    Timer {
        interval: 600
        running: true
        repeat: true
        onTriggered: {
            try {
                const search = root.find(content, "launcherSearch");
                const list = root.find(content, "launcherAppList");
                if (root.phase === 0) {
                    GlobalConfig.launcher.actionPrefix = ".";
                    GlobalConfig.general.apps.terminal = ["foot", "--app-id=codex-test"];
                    Codex.execute = command => root.commands.push([...command]);
                    testState.launcher = true;
                    search.text = ".codex";
                } else if (root.phase === 1) {
                    root.check(list.currentItem?.modelData.name === "Codex", "Codex is discoverable in actions: " + JSON.stringify({state: list.state, count: list.count, text: search.text, display: list.displayText, item: list.currentItem?.modelData.name, matches: Actions.query(".codex").map(a => a.name)}));
                    search.accepted();
                    root.check(search.text === ".codex ", "action autocompletes count input");
                    search.text = ".codex 3";
                } else if (root.phase === 2) {
                    root.check(list.state === "codex", "count input selects Codex state");
                    root.check(list.count === 1 && list.currentItem.modelData.name.includes("3"), "count preview updates");
                    search.accepted();
                    root.check(root.commands.length === 3, "Enter launches exactly three terminals");
                    root.check(!testState.launcher, "valid launch closes launcher");
                    root.check(JSON.stringify(root.commands[0]) === JSON.stringify(["foot", "--app-id=codex-test", "codex"]), "configured terminal arguments are preserved");
                    testState.launcher = true;
                    search.text = ".codex 0";
                } else if (root.phase === 3) {
                    search.accepted();
                    root.check(root.commands.length === 3 && testState.launcher, "invalid count keeps launcher open without spawning");
                    for (const input of ["-1", "21", "1.5", "1e1", "3; touch /tmp/no", "2 3", "Infinity", "999999999999999999999"]) {
                        root.check(Codex.countForText(".codex " + input) === 0, "reject invalid count: " + input);
                    }
                    root.check(Codex.countForText(".codex 20") === 20, "upper bound accepted");
                    root.check(Codex.countForText(".codex  2  ") === 2, "surrounding spaces accepted");
                    search.text = ".codex ";
                } else if (root.phase === 4) {
                    list.currentItem.modelData.onClicked(list);
                    root.check(root.commands.length === 4, "click starts one terminal by default");
                    GlobalConfig.launcher.actionPrefix = ">";
                    testState.launcher = true;
                    search.text = ">codex 2";
                } else if (root.phase === 5) {
                    search.accepted();
                    root.check(root.commands.length === 6, "custom action prefix supported");
                    console.log("Codex launcher interaction checks passed");
                    console.log("Fork feature probe loaded");
                    stop();
                }
                root.phase++;
            } catch (error) {
                console.error("Codex launcher interaction checks FAILED: " + error);
                stop();
            }
        }
    }
}
