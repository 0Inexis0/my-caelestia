// Hyprland requires integer logical dimensions. Keep the exact ratios rather
// than rounding them to two decimal places before passing them to the compositor.
function scales(width, height, current) {
    let a = Math.round(width), b = Math.round(height);
    if (a <= 0 || b <= 0) return [1];
    while (b) {
        const remainder = a % b;
        a = b;
        b = remainder;
    }
    const values = [current > 0 ? current : 1];
    for (const target of [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3]) {
        const denominator = Math.max(1, Math.round(a / target));
        const value = a / denominator;
        if (value >= 0.25 && value <= 3 && !values.some(v => Math.abs(v - value) < 0.001))
            values.push(value);
    }
    return values.sort((x, y) => x - y);
}
