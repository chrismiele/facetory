using Toybox.Graphics;

// MiPArt — all MIP/simple-rendering art in one place.
//
// MIP devices only support a 64-colour palette: the 4×4×4 grid where each of
// R, G, B can be one of {0x00, 0x55, 0xAA, 0xFF}. Off-palette colours are
// rounded by the firmware, sometimes unpredictably, so every colour here is on
// the palette and any blended colour is snapped to it with snap().
//
// The sun's sizes and the way it spreads along the horizon live in sun.mc.
module MiPArt {

    const BLACK = 0x000000;
    const WHITE = 0xFFFFFF;

    // ── Sun ──────────────────────────────────────────────────────────────────
    //
    // Three layers at every stage: a ball the size of the white disc (10
    // degrees, the largest moon) and two thin rings around it, 2 degrees each,
    // so by day the MIP sun is 28 degrees across. (AMOLED's 36-degree corona
    // is too heavy in flat MIP colours.) Through twilight the outer ring
    // widens evenly, from 14 degrees at sunset to 18 at the end of
    // astronomical twilight, so like the AMOLED corona its last trace leaves
    // the sky exactly when full night begins. The inner ring sets at the end
    // of nautical twilight.
    //
    // One colour ramp, from white-hot through yellow, orange and red to the
    // purples and blues of twilight. At step s the ball is RAMP[s], the inner
    // ring RAMP[s+1] and the outer ring RAMP[s+2], so as the sun sets it slides
    // one step down the ramp at a time and the three layers always differ.
    // The ball and both rings spread along the horizon from +3, exactly as
    // the AMOLED sun does, with the same reach (see sun.mc).
    //
    //   step  sun altitude    ball     inner    outer
    //    0     3 and above    FFFFFF   FFFF55   FFFF00
    //    1     0 to   3       FFFF55   FFFF00   FFAA00
    //    2    -3 to   0       FFFF00   FFAA00   FF5500
    //    3    -6 to  -3       FFAA00   FF5500   FF0000
    //    4    -9 to  -6       FF5500   FF0000   FF00AA
    //    5   -12 to  -9       FF0000   FF00AA   AA00AA   (ball set at -10)
    //    6   -18 to -12       FF00AA   AA00AA   5500AA   (inner ring set at -12; outer ring sets at -18)
    //
    // Neighbouring ramp colours must look different on a MIP screen, since
    // any two of them can sit side by side, also once spread out. Red is
    // followed by pink (FF00AA), not crimson (FF0055), which is hard to tell
    // from red.
    //
    // The step follows sunStage(), except that the white ball stays until +3,
    // half way through the white-hot fade (+6 to sunset; MIP cannot fade it),
    // then gives way to pale yellow, and the rings move down with it.
    //
    // The minute text takes MINUTE_COLORS[sunStage()], which follows the same
    // timing as the AMOLED palette: orange around sunset, red by the end of
    // civil twilight, purple by the end of nautical twilight, blue at full
    // night.
    //
    //   stage  sun altitude    minute text
    //     0     6 and above    FFFF00
    //     1     0 to   6       FFAA00
    //     2    -3 to   0       FF5500
    //     3    -6 to  -3       FF0000
    //     4    -9 to  -6       FF0055
    //     5   -12 to  -9       FF55AA
    //     6   -18 to -12       AA55FF
    //     7   below -18        55AAFF
    const SUN_RAMP = [
        0xFFFFFF, 0xFFFF55, 0xFFFF00, 0xFFAA00, 0xFF5500, 0xFF0000,
        0xFF00AA, 0xAA00AA, 0x5500AA
    ];

    // Minute-text colour for each stage. All bright enough to read on black.
    const MINUTE_COLORS = [
        0xFFFF00, 0xFFAA00, 0xFF5500, 0xFF0000, 0xFF0055, 0xFF55AA, 0xAA55FF, 0x55AAFF
    ];

    const INNER_RING_DEG     = 12.0;   // outer edge of the inner ring: the AMOLED core's edge
    const OUTER_RING_DEG     = 14.0;   // outer edge of the whole MIP sun until sunset; see outerRingDeg()

    // ── Moon ─────────────────────────────────────────────────────────────────
    const MIP_MOON_BRIGHT   = 0xAAAAAA;   // lit face, every phase but full
    const MIP_MOON_MEDIUM   = 0xAAAAAA;   // outer ring of the full-moon halo
    const MIP_MOON_DARK     = 0x555555;   // inner halo, and the unlit side of the moon

    // ── Stars ────────────────────────────────────────────────────────────────
    // Indexed by Drawing.STAR_BIN_*: yellow, soft yellow, red, blue, white.
    // Single-pixel stars are drawn in light grey so the larger ones stand out.
    const STAR_COLORS = [0xFFFF55, 0xFFFFAA, 0xFFAA55, 0x55AAFF, 0xFFFFFF];
    const STAR_SMALL_COLOR = 0xAAAAAA;
    const CONSTELLATION_LINE = 0x0000AA;  // the palette's deep blue

    // ── Accents ──────────────────────────────────────────────────────────────
    const MIP_SUNSET_ACCENT = 0xFFAA00;   // tinges the hour text near sunrise/sunset

    // Ring geometry for the full-moon halo.
    const MIP_RING_THICKNESS_DEG = 3.0;

    // ── Colour functions ─────────────────────────────────────────────────────

    // Round each channel to the nearest of 00, 55, AA, FF.
    function snap(color) {
        var r = (((color >> 16) & 0xFF) + 42) / 85 * 85;
        var g = (((color >> 8)  & 0xFF) + 42) / 85 * 85;
        var b = (( color        & 0xFF) + 42) / 85 * 85;
        return (r << 16) | (g << 8) | b;
    }

    function sunStage(altDeg) {
        if (altDeg >= 6.0)   { return 0; }
        if (altDeg >= 0.0)   { return 1; }
        if (altDeg >= -3.0)  { return 2; }
        if (altDeg >= -6.0)  { return 3; }
        if (altDeg >= -9.0)  { return 4; }
        if (altDeg >= -12.0) { return 5; }
        if (altDeg >= -18.0) { return 6; }
        return 7;
    }

    // The stage's minute-text colour at full saturation.
    function minuteColorForAlt(altDeg) {
        return MINUTE_COLORS[sunStage(altDeg)];
    }

    // Minute-text colour after the saturation setting. The top two settings
    // give the pure stage colour; lower ones step toward white, staying on
    // the palette.
    function minuteColor(stageColor, saturation) {
        return snap(MathUtil.blendColor(WHITE, stageColor, MathUtil.clamp(saturation * 1.25, 0.0, 1.0)));
    }

    // Hour-text colour: white, tinted toward the accent near sunrise/sunset.
    function hourColor(accentScale) {
        return snap(MathUtil.blendColor(WHITE, MIP_SUNSET_ACCENT, accentScale));
    }

    function starColor(starSize, colorBin) {
        if (starSize == Drawing.STAR_SMALL) { return STAR_SMALL_COLOR; }
        return STAR_COLORS[colorBin];
    }

    // Moon lit-face colour: full moon uses WHITE for maximum contrast;
    // all other phases use MIP_MOON_BRIGHT.
    function moonLitColor(isFullMoon) {
        return isFullMoon ? WHITE : MIP_MOON_BRIGHT;
    }

    // ── Drawing functions ────────────────────────────────────────────────────

    // The ramp step for the sun's own colours (see the table above).
    function sunRampStep(altDeg) {
        var k = sunStage(altDeg);
        if (SunArt.whiteHot(altDeg) >= 0.5) { return 0; }
        return (k < 1) ? 1 : k;
    }

    // The outer ring's radius: OUTER_RING_DEG until sunset, then widening
    // evenly to SunArt.OUTER_DEG at the end of astronomical twilight. Its top
    // edge, (altitude + radius) above the horizon, then reaches the horizon
    // exactly at full night.
    function outerRingDeg(altDeg) {
        var t = MathUtil.clamp(-altDeg / SunArt.OUTER_DEG, 0.0, 1.0);
        return OUTER_RING_DEG + (SunArt.OUTER_DEG - OUTER_RING_DEG) * t;
    }

    // Outer ring, inner ring, ball: each brighter layer goes on top. All
    // three spread along the horizon (SunArt.drawLayer).
    function drawSun(dc, cx, cy, R, sx, sy, altDeg) {
        if (altDeg <= -SunArt.OUTER_DEG) { return; }    // full night: the whole MIP sun has set

        var s     = sunRampStep(altDeg);
        var outer = outerRingDeg(altDeg);
        SunArt.prepareSpread(cx, cy, R, sx, sy, altDeg, outer);
        SunArt.drawLayer(dc, outer,                 SUN_RAMP[s + 2]);
        SunArt.drawLayer(dc, INNER_RING_DEG,        SUN_RAMP[s + 1]);
        SunArt.drawLayer(dc, SunArt.WHITE_DISC_DEG, SUN_RAMP[s]);
    }

    // Glow rings only for the full moon (no body disc): outerColor ring → innerColor ring.
    // closeness=0 → outerR equals bodyR (zero thickness, nothing drawn); closeness=1 → full extent.
    function drawHaloGlow(dc, x, y, R, bodyR, glowDeg, closeness, innerColor, outerColor) {
        if (closeness <= 0.0) { return; }
        var xi    = x.toNumber();
        var yi    = y.toNumber();
        var glowR = bodyR + (R * (glowDeg / 90.0) - bodyR) * closeness;
        var innerR = glowR - R * (MIP_RING_THICKNESS_DEG / 90.0);
        if (innerR < bodyR) { innerR = bodyR; }
        dc.setColor(outerColor, 0x000000);
        dc.fillCircle(xi, yi, MathUtil.roundNearest(glowR));
        dc.setColor(innerColor, 0x000000);
        dc.fillCircle(xi, yi, MathUtil.roundNearest(innerR));
    }

}
