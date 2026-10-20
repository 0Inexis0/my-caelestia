pragma Singleton

import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.utils

Singleton {
    id: root

    // Keep process execution replaceable for interaction tests.
    property var execute: command => Quickshell.execDetached({
        command: command,
        workingDirectory: Paths.home
    })

    function countForText(text: string): int {
        const prefix = `${GlobalConfig.launcher.actionPrefix}codex `;
        if (!text.startsWith(prefix))
            return 0;
        const value = text.slice(prefix.length).trim();
        if (!value)
            return 1;
        if (!/^[0-9]+$/.test(value))
            return 0;
        const count = Number(value);
        return count >= 1 && count <= 20 ? count : 0;
    }

    function launch(text: string, list: var): void {
        const count = countForText(text);
        if (!count)
            return;
        const command = ["hyprctl", "eval", `require("hyprland.codex").launch(${count})`];
        list.screenState.launcher = false;
        root.execute(command);
    }

    function query(text: string): var {
        const count = countForText(text);
        return [{
            name: count ? (count === 1 ? Tr.tr("Open 1 Codex terminal") : Tr.tr("Open %1 Codex terminals").arg(count)) : Tr.tr("Enter a number from 1 to 20"),
            desc: count ? Tr.tr("Open Codex windows in their own floating grid") : Tr.tr("Example: %1codex 3").arg(GlobalConfig.launcher.actionPrefix),
            icon: count ? "terminal" : "info",
            onClicked: list => root.launch(list.search.text, list)
        }];
    }
}
