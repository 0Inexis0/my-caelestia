.pragma library

// Fixed logical coordinates keep jumps and reaction time identical at every panel size.
var worldWidth = 400;
var ground = 150;
var dinoX = 42;
var dinoWidth = 32;
var dinoHeight = 38;

function create() {
    return { y: 0, velocity: 0, distance: 0, score: 0, speed: 180,
        spawnIn: 1.5, obstacles: [], over: false };
}

function jump(state) {
    if (!state.over && state.y === 0) {
        state.velocity = 440;
        return true;
    }
    return false;
}

function step(state, dt, random) {
    if (state.over || dt <= 0)
        return;
    // Ignore suspend/resume gaps; substeps avoid tunnelling through obstacles.
    var remaining = Math.min(dt, 0.05);
    while (remaining > 0) {
        var tick = Math.min(remaining, 1 / 120);
        remaining -= tick;
        state.speed = Math.min(330, 180 + state.distance / 250);
        state.distance += state.speed * tick;
        state.score = Math.floor(state.distance / 20);
        state.y = Math.max(0, state.y + state.velocity * tick);
        state.velocity = state.y > 0 ? state.velocity - 1250 * tick : 0;
        state.spawnIn -= tick;
        if (state.spawnIn <= 0) {
            state.obstacles.push({ x: worldWidth + 20, width: 18 + Math.floor(random() * 12), height: 27 + Math.floor(random() * 13) });
            state.spawnIn = 1.25 + random() * 0.7;
        }
        for (var i = state.obstacles.length - 1; i >= 0; i--) {
            var obstacle = state.obstacles[i];
            obstacle.x -= state.speed * tick;
            // Insets make the pixel-art silhouette a little more forgiving.
            if (dinoX + dinoWidth - 5 > obstacle.x + 3 && dinoX + 5 < obstacle.x + obstacle.width - 3
                    && state.y + 4 < obstacle.height && state.y + dinoHeight - 4 > 0) {
                state.over = true;
                return;
            }
            if (obstacle.x + obstacle.width < 0)
                state.obstacles.splice(i, 1);
        }
    }
}
