pragma ComponentBehavior: Bound

import Caelestia.I18n
import qs.components.controls as Controls
import qs.modules.nexus.common

SelectRow {
    id: root

    required property var monitorList
    readonly property var panels: monitorList.filter(m => /^(eDP|LVDS|DSI)/.test(m.name))
    readonly property var outputs: monitorList.filter(m => /^(HDMI-|DP-|DVI-|VGA-|USB-)/.test(m.name))

    signal layoutRequested(mode: string)

    visible: panels.length > 0 && outputs.length > 0
    first: true
    last: true
    label: Tr.tr("Display mode")
    subtext: Tr.tr("Choose where to show your desktop")
    fallbackText: Tr.tr("Choose")
    menuItems: [internalMode, externalMode, extendMode, mirrorMode]
    // Read back from the typed menu list so active and selected use the same item type.
    active: {
        if (panels.every(m => m.disabled))
            return menuItems[1];
        if (outputs.every(m => m.disabled))
            return menuItems[0];
        if (outputs.length > 0 && outputs.every(m => !m.disabled && panels.some(p => p.name === m.mirrorOf)))
            return menuItems[3];
        return menuItems[2];
    }
    onSelected: item => {
        if (root.enabled)
            root.layoutRequested(item.value);
    }

    Controls.MenuItem {
        id: internalMode

        text: Tr.tr("Laptop only")
        value: "internal"
    }

    Controls.MenuItem {
        id: externalMode

        text: Tr.tr("External only")
        value: "external"
    }

    Controls.MenuItem {
        id: extendMode

        text: Tr.tr("Extend")
        value: "extend"
    }

    Controls.MenuItem {
        id: mirrorMode

        text: Tr.tr("Mirror")
        value: "mirror"
    }
}
