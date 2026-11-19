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
    // The MIP sun is flat rings of colour, and as it goes down the colours
    // flow: each new colour grows in at the outside and pushes the one inside
    // it down, while the brightest colours shrink toward the middle and are
    // lost below the horizon. No ring ever changes colour all at once.
    //
    // It follows the AMOLED sun stage for stage: the colour that fills what is
    // left above the horizon is the AMOLED sun's colour at that moment, with at
    // most a hint of the next one at the outer edge:
    //
    //   +6 and above   white ball in yellow rings
    //   +3             white shrinking, amber at the edge
    //   sunset         white gone: yellow in the middle, amber, orange edge
    //   -3             orange
    //   -6             red (end of civil twilight)
    //   -9             red into magenta
    //   -12            purple (end of nautical twilight)
    //   -15            indigo
    //   -18            blue, setting exactly as full night begins
    //
    // BAND_EDGES gives, at each BAND_ALT, the outer edge of each colour of
    // SUN_COLORS as a share of the sun's outer edge; a colour not yet in sits
    // at 1 (no width), one gone at 0. In between, edges move evenly. Sizes
    // scale with "Sun and moon size" (the ball matches the moon); the outer
    // edge is OUTER_RING_DEG by day and widens to 18 deg through twilight
    // (SunArt.glowOuterDeg()). Bands too thin to read (MIN_RING_DEG), or a
    // centre disc under a third of the ball, are left out, so a colour leaves
    // cleanly; the colour next to it covers the gap, and the outermost colour
    // drawn always reaches the outer edge, so the glow never pulses. All of
    // it spreads along the horizon from +3 like the AMOLED sun (see sun.mc).
    //
    // Neighbouring colours must look different on a MIP screen. Red is
    // followed by pink (FF00AA), not crimson (FF0055), which is hard to tell
    // from red.
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
    //
    //   white, pale yellow, yellow, amber, orange, red, pink, purple, indigo, blue
    const SUN_COLORS = [
        0xFFFFFF, 0xFFFF55, 0xFFFF00, 0xFFAA00, 0xFF5500,
        0xFF0000, 0xFF00AA, 0xAA00AA, 0x5500AA, 0x5555FF
    ];
    const BAND_ALT   = [6.0, 3.0, 0.0, -3.0, -6.0, -9.0, -12.0, -15.0, -18.0];
    const BAND_EDGES = [
        0.714, 0.857, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000,   // +6
        0.500, 0.660, 0.840, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000,   // +3
        0.000, 0.000, 0.350, 0.800, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000,   // +0
        0.000, 0.000, 0.000, 0.400, 0.800, 1.000, 1.000, 1.000, 1.000, 1.000,   // -3
        0.000, 0.000, 0.000, 0.000, 0.500, 0.920, 1.000, 1.000, 1.000, 1.000,   // -6
        0.000, 0.000, 0.000, 0.000, 0.000, 0.600, 0.860, 1.000, 1.000, 1.000,   // -9
        0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.620, 1.000, 1.000, 1.000,   // -12
        0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.800, 1.000, 1.000,   // -15
        0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.850, 1.000    // -18
    ];
    const BAND_COUNT   = 10;
    const MIN_RING_DEG = 0.8;

    // Minute-text colour for each stage. All bright enough to read on black.
    const MINUTE_COLORS = [
        0xFFFF00, 0xFFAA00, 0xFF5500, 0xFF0000, 0xFF0055, 0xFF55AA, 0xAA55FF, 0x55AAFF
    ];

    const OUTER_RING_DEG     = 14.0;   // the Large sun's outer edge by day (ball 10, rings to 12 and 14)

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

    // ── Planets (Planets.VENUS..SATURN) ──────────────────────────────────────
    const PLANET_COLORS = [0xFFFFFF, 0xFF5500, 0xFFFFAA, 0xFFFF55];       // white, orange, pale yellow, yellow
    const SATURN_RING   = 0xAAAA55;

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

    // Band radii for the frame being drawn, reused (null = not drawn).
    var _bandRadii = null;

    // scale: "Sun and moon size" (SunArt.sizeScale()).
    function drawSun(dc, cx, cy, R, sx, sy, altDeg, scale) {
        if (altDeg <= -SunArt.OUTER_DEG) { return; }    // full night: the whole MIP sun has set
        var ball  = SunArt.WHITE_DISC_DEG * scale;
        var outer = SunArt.glowOuterDeg(OUTER_RING_DEG * scale, altDeg);

        // The two timetable rows around this altitude, and how far between.
        var last = BAND_ALT.size() - 1;
        var row0 = 0;
        var row1 = 0;
        var t    = 0.0;
        if (altDeg <= BAND_ALT[last]) {
            row0 = last;
            row1 = last;
        } else if (altDeg < BAND_ALT[0]) {
            row1 = 1;
            while (altDeg < BAND_ALT[row1]) { row1 += 1; }
            row0 = row1 - 1;
            t    = (BAND_ALT[row0] - altDeg) / (BAND_ALT[row0] - BAND_ALT[row1]);
        }

        // From the middle out: each colour fills from the edge before it to
        // its own; keep the ones wide enough to read.
        if (_bandRadii == null) { _bandRadii = new [BAND_COUNT]; }
        var prev = 0.0;
        for (var k = 0; k < BAND_COUNT; k += 1) {
            var e0 = BAND_EDGES[row0 * BAND_COUNT + k];
            var e  = e0 + (BAND_EDGES[row1 * BAND_COUNT + k] - e0) * t;
            if (e < prev) { e = prev; }
            _bandRadii[k] = ((e - prev) * outer >= MIN_RING_DEG && !(prev <= 0.0 && e * outer < ball / 3.0))
                            ? e * outer : null;
            prev = e;
        }

        // The outer edge never moves with the bands: the outermost colour
        // drawn always reaches it. A new colour grows in at the edge from no
        // width, and while it is too thin to show, the colour inside it
        // stands in, so the glow's extent only ever changes smoothly.
        for (var k = BAND_COUNT - 1; k >= 0; k -= 1) {
            if (_bandRadii[k] != null) { _bandRadii[k] = outer; break; }
        }

        // Outermost first; each brighter colour goes on top.
        SunArt.prepareSpread(cx, cy, R, sx, sy, altDeg, outer);
        for (var k = BAND_COUNT - 1; k >= 0; k -= 1) {
            if (_bandRadii[k] != null) { SunArt.drawLayer(dc, _bandRadii[k], SUN_COLORS[k]); }
        }
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
