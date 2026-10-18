import QtQuick
import QtTest
import "../../components/games" as Games
import "../../components/games/DinoPhysics.js" as Physics

TestCase {
    name: "Dino"
    when: windowShown
    visible: true
    width: 440
    height: 300

    Games.DinoGame { id: game; width: 400; height: 250 }

    function init() {
        game.available = true;
        game.running = false;
        game.started = false;
        game.gameOver = false;
        game.game = Physics.create();
    }

    function fixedRandom() { return 0.5; }
    function test_jumpAndLanding() {
        const s = Physics.create();
        verify(Physics.jump(s));
        Physics.step(s, 0.02, fixedRandom);
        verify(s.y > 0);
        verify(!Physics.jump(s));
        for (let i = 0; i < 90; i++) Physics.step(s, 0.01, fixedRandom);
        compare(s.y, 0);
        verify(Physics.jump(s));
    }
    function test_collisionAndRestart() {
        const s = Physics.create();
        s.obstacles = [{ x: 60, width: 25, height: 35 }];
        Physics.step(s, 0.01, fixedRandom);
        verify(s.over);
        verify(!Physics.jump(s));
        const distance = s.distance;
        Physics.step(s, 0.05, fixedRandom);
        compare(s.distance, distance);
        game.game = s;
        game.started = true;
        game.gameOver = true;
        mouseClick(game, 120, 100);
        verify(!game.gameOver);
        compare(game.score, 0);
        verify(game.running);
    }
    function test_clearObstacle() {
        const s = Physics.create();
        s.y = 65;
        s.obstacles = [{ x: 60, width: 25, height: 35 }];
        Physics.step(s, 0.01, fixedRandom);
        verify(!s.over);
    }
    function test_spawnScoreAndSpeedCap() {
        const s = Physics.create();
        s.y = 1000;
        s.spawnIn = 0;
        s.distance = 100000;
        Physics.step(s, 0.01, fixedRandom);
        compare(s.obstacles.length, 1);
        compare(s.speed, 330);
        verify(s.score >= 5000);
    }
    function test_resumeGapIsCapped() {
        const s = Physics.create();
        Physics.step(s, 60, fixedRandom);
        verify(s.distance < 10);
    }
    function test_mouseKeyboardAndVisibility() {
        mouseClick(game, 120, 100);
        verify(game.started);
        verify(game.running);
        verify(game.activeFocus);
        keyClick(Qt.Key_P);
        verify(!game.running);
        const distance = game.game.distance;
        wait(50);
        compare(game.game.distance, distance);
        keyClick(Qt.Key_Space);
        verify(game.running);
        game.available = false;
        verify(!game.running);
        game.available = true;
        verify(!game.running);
        mouseClick(game, 120, 100);
        verify(game.running);
        keyClick(Qt.Key_Escape);
        verify(!game.running);
    }
}
