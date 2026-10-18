pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import "DinoPhysics.js" as Physics

FocusScope {
    id: root

    property bool available: true
    property color foreground: "#9ecfca"
    property color muted: "#526966"
    property color background: "#141d1c"
    property string fontFamily: "sans-serif"
    property bool started: false
    property bool running: false
    property var game: Physics.create()
    property int score: 0
    property bool gameOver: false
    property double lastFrame: 0
    readonly property int bestScore: records.bestScore
    signal dismiss()

    implicitWidth: 400
    implicitHeight: 250
    activeFocusOnTab: available
    Accessible.role: Accessible.Button
    Accessible.name: qsTr("Dino game. Click, Space or Up to jump. P to pause. Escape to close.")
    Accessible.onPressAction: act()

    function act(): void {
        if (!available)
            return;
        forceActiveFocus();
        if (!started || gameOver) {
            game = Physics.create();
            score = 0;
            gameOver = false;
            started = true;
            running = true;
        } else if (!running) {
            running = true;
        }
        Physics.jump(game);
        lastFrame = Date.now();
        scene.requestPaint();
    }

    function pause(): void {
        running = false;
    }

    onAvailableChanged: {
        if (!available) {
            pause();
            focus = false;
        }
    }
    onActiveFocusChanged: {
        if (!activeFocus)
            pause();
    }
    onForegroundChanged: scene.requestPaint()
    onMutedChanged: scene.requestPaint()
    onBackgroundChanged: scene.requestPaint()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Up) {
            if (!event.isAutoRepeat)
                act();
            event.accepted = true;
        } else if (event.key === Qt.Key_P && started && !gameOver) {
            if (!event.isAutoRepeat) {
                running = !running;
                lastFrame = Date.now();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            pause();
            dismiss();
            event.accepted = true;
        }
    }

    Settings {
        id: records
        location: StandardPaths.writableLocation(StandardPaths.GenericStateLocation) + "/caelestia-dino.ini"
        category: "Dino"
        property int bestScore: 0
    }

    Timer {
        interval: 16
        repeat: true
        running: root.running && root.available && root.visible
        onTriggered: {
            const now = Date.now();
            Physics.step(root.game, (now - root.lastFrame) / 1000, Math.random);
            root.lastFrame = now;
            root.score = root.game.score;
            root.gameOver = root.game.over;
            if (root.score > records.bestScore)
                records.bestScore = root.score;
            if (root.gameOver)
                root.running = false;
            scene.requestPaint();
        }
    }

    Text {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 12
        text: String(root.score).padStart(5, "0") + "   HI " + String(root.bestScore).padStart(5, "0")
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 13
    }

    Canvas {
        id: scene
        anchors.top: parent.top
        anchors.topMargin: 32
        width: parent.width
        height: Math.min(width * 0.45, parent.height - 98)
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.scale(width / 400, height / 180);
            ctx.fillStyle = root.muted;
            ctx.fillRect(0, Physics.ground, 400, 1);
            for (let i = 0; i < 12; i++)
                ctx.fillRect((i * 43 - root.game.distance % 43 + 400) % 400, 158 + (i % 3) * 4, 5, 1);
            // A little drifting cloud.
            const cloudX = 300 - (root.game.distance * 0.15) % 450;
            ctx.fillRect(cloudX, 30, 48, 2);
            ctx.fillRect(cloudX + 8, 24, 12, 2);
            ctx.fillRect(cloudX + 20, 18, 14, 2);
            ctx.fillRect(cloudX + 34, 24, 8, 2);
            ctx.fillStyle = root.foreground;
            for (const obstacle of root.game.obstacles) {
                const x = obstacle.x;
                const y = Physics.ground - obstacle.height;
                const w = obstacle.width;
                ctx.fillRect(x + w * 0.4, y, w * 0.25, obstacle.height);
                ctx.fillRect(x, y + 7, w * 0.18, obstacle.height * 0.45);
                ctx.fillRect(x, y + obstacle.height * 0.55, w * 0.5, 5);
                ctx.fillRect(x + w * 0.82, y + 3, w * 0.18, obstacle.height * 0.4);
                ctx.fillRect(x + w * 0.55, y + obstacle.height * 0.4, w * 0.45, 5);
            }
            const x = Physics.dinoX;
            const y = Physics.ground - Physics.dinoHeight - root.game.y;
            // Original pixel silhouette, drawn directly so it follows the shell palette.
            ctx.fillRect(x + 16, y, 20, 17);
            ctx.fillRect(x + 12, y + 13, 15, 16);
            ctx.fillRect(x + 5, y + 18, 19, 13);
            ctx.fillRect(x, y + 12, 5, 13);
            ctx.fillRect(x + 23, y + 21, 9, 3);
            ctx.fillRect(x + 29, y + 21, 3, 7);
            const stride = root.running && root.game.y === 0 ? Math.floor(root.game.distance / 18) % 2 * 4 : 0;
            ctx.fillRect(x + 8, y + 29, 4, 9 - stride);
            ctx.fillRect(x + 8, y + 35 - stride, 8, 3);
            ctx.fillRect(x + 20, y + 28, 4, 6 + stride);
            ctx.fillRect(x + 20, y + 31 + stride, 8, 3);
            ctx.fillStyle = root.background;
            ctx.fillRect(x + 27, y + 4, 3, 3);
            ctx.fillRect(x + 26, y + 12, 10, 2);
        }
    }

    Text {
        anchors.top: scene.bottom
        anchors.topMargin: 8
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.gameOver ? qsTr("Game over · click to retry") : !root.started ? qsTr("All up to date. Time for a jump?") : !root.running ? qsTr("Paused · click to continue") : qsTr("Jump!")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 16
        wrapMode: Text.WordWrap
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: qsTr("Click / Space / ↑   ·   P pause")
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 12
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.available
        cursorShape: Qt.PointingHandCursor
        onClicked: root.act()
    }
}
