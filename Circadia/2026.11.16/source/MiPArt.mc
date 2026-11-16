using Toybox.Graphics;

// MiPArt — all MIP/simple-rendering art in one place.
//
// MIP devices only support a 64-colour palette: the 4×4×4 grid where each of
// R, G, B can be one of {0x00, 0x55, 0xAA, 0xFF}. Off-palette colours are
// rounded by the firmware, sometimes unpredictably, so every colour here is on
// the palette and any blended colour is snapped to it with snap().
//
// The sun's sizes and its edge flare are shared with AMOLED and live in sun.mc.
module MiPArt {

    const BLACK = 0x000000;
    const WHITE = 0xFFFFFF;

    // ── Sun ──────────────────────────────────────────────────────────────────
    //
    // One colour ramp, from white-hot through yellow, orange and red to the
    // purples and blues of twilight. At stage k the sun's core is RAMP[k], its
    // inner corona RAMP[k+1] and its outer corona RAMP[k+2], so as the sun sets
    // it slides one step down the ramp at a time. The minute text takes
    // MINUTE_COLORS[k], which follows the same timing as the AMOLED palette:
    // orange around sunset, red by the end of civil twilight, purple by the end
    // of nautical twilight, blue at full night.
    //
    //   stage  sun altitude    core     inner    outer    minute text
    //     0     6 and above    FFFFFF*  FFFF55   FFFF00   FFFF00
    //     1     0 to   6       FFFF55   FFFF00   FFAA00   FFAA00
    //     2    -3 to   0       FFFF00   FFAA00   FF5500   FF5500
    //     3    -6 to  -3       FFAA00   FF5500   FF0000   FF0000
    //     4    -9 to  -6       FF5500   FF0000   FF0055   FF0055
    //     5   -12 to  -9       FF0000   FF0055   AA00AA   FF55AA
    //     6   -18 to -12       FF0055   AA00AA   5500AA   AA55FF
    //     7   below -18        (no sun)                   55AAFF
    //
    //   * The white-hot core. MIP cannot fade it, so it is white down to +9
    //     and pale yellow (FFFF55) from there to +6.
    //
    // The edge flare uses RAMP[k+1] at the rim, stepping to RAMP[k+3] at its
    // inner edge, so the ramp carries a few entries beyond the sun's own.
    const SUN_RAMP = [
        0xFFFFFF, 0xFFFF55, 0xFFFF00, 0xFFAA00, 0xFF5500, 0xFF0000,
        0xFF0055, 0xAA00AA, 0x5500AA, 0x0000AA, 0x000055
    ];

    // Minute-text colour for each stage. All bright enough to read on black.
    const MINUTE_COLORS = [
        0xFFFF00, 0xFFAA00, 0xFF5500, 0xFF0000, 0xFF0055, 0xFF55AA, 0xAA55FF, 0x55AAFF
    ];

    const INNER_CORONA_DEG   = 12.0;   // boundary between the two corona rings
    const FLARE_MAX_BANDS    = 3;
    const FLARE_MIN_BAND_PX  = 2.0;

    // ── Moon ─────────────────────────────────────────────────────────────────
    const MIP_MOON_BRIGHT   = 0xAAAAAA;   // lit face, every phase but full
    const MIP_MOON_MEDIUM   = 0xAAAAAA;   // outer ring of the full-moon halo
    const MIP_MOON_DARK     = 0x555555;   // inner halo, and the unlit side of the moon

    // ── Stars ────────────────────────────────────────────────────────────────
    // Indexed by Drawing.STAR_BIN_*: yellow, soft yellow, red, blue, white.
    // Single-pixel stars are drawn in light grey so the larger ones stand out.
    const STAR_COLORS = [0xFFFF55, 0xFFFFAA, 0xFFAA55, 0x55AAFF, 0xFFFFFF];
    const STAR_SMALL_COLOR = 0xAAAAAA;

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

    // Corona rings and flare bands are merged dimmest-first (highest ramp
    // index first), so the brighter of the two shows wherever they overlap.
    // The core goes on top.
    function drawSun(dc, cx, cy, R, sx, sy, altDeg) {
        var deg = R / 90.0;
        var k   = sunStage(altDeg);
        var xi  = MathUtil.roundNearest(sx);
        var yi  = MathUtil.roundNearest(sy);

        var rings = SunArt.coronaVisible(altDeg) ? 2 : 0;
        var bands = SunArt.prepareFlare(cx, cy, R, sx, sy, altDeg, FLARE_MIN_BAND_PX, FLARE_MAX_BANDS);

        var ring = 0;           // 0 = outer corona (ramp k+2), 1 = inner corona (ramp k+1)
        var band = bands - 1;   // band j uses ramp k+1+j; the innermost is the dimmest

        while (ring < rings || band >= 0) {
            var ringIdx = (ring < rings) ? (k + 2 - ring) : -1;
            var bandIdx = (band >= 0)    ? (k + 1 + band)  : -1;

            if (band >= 0 && bandIdx >= ringIdx) {
                SunArt.drawFlareBand(dc, cx, cy, R, band, bands, SUN_RAMP[bandIdx]);
                band -= 1;
            } else {
                var rDeg = (ring == 0) ? SunArt.OUTER_DEG : INNER_CORONA_DEG;
                dc.setColor(SUN_RAMP[ringIdx], BLACK);
                dc.fillCircle(xi, yi, MathUtil.roundNearest(rDeg * deg));
                ring += 1;
            }
        }

        if (SunArt.coreVisible(altDeg)) {
            // Stage 0's core is the white-hot one. MIP cannot fade it, so it
            // switches to the next ramp colour once the fade is past half way.
            var coreColor = SUN_RAMP[k];
            if (k == 0 && SunArt.whiteHot(altDeg) < 0.5) {
                coreColor = SUN_RAMP[1];
            }
            // The MIP core is the white disc itself: the same width as the
            // largest moon. The inner corona ring is its coloured rim.
            dc.setColor(coreColor, BLACK);
            dc.fillCircle(xi, yi, MathUtil.roundNearest(SunArt.WHITE_DISC_DEG * deg));
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
