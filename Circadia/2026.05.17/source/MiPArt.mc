using Toybox.Graphics;

// MiPArt — all MIP/simple-rendering art in one place.
//
// MIP devices (Forerunner 2xx/3xx/9xx, Fenix MIP variants, Tactix, Enduro)
// only support a 64-colour palette: the 4×4×4 grid where each of R, G, B
// can be one of {0x00, 0x55, 0xAA, 0xFF}. Off-palette colours are silently
// rounded by the firmware, sometimes unpredictably.
//
// Isolating everything MIP-related here means you can tune colours and
// drawing techniques for MIP beta-testing without touching any code that
// is known to work on AMOLED devices.
module MiPArt {

    // ── MIP colour palette ───────────────────────────────────────────────────
    //
    // Solar palette is structured as three rings per altitude band.
    // Daytime is a pure yellow dark→medium→bright ramp; transition bands
    // carry the previous band's bright hue as the new core.
    //
    //   Sun (≥ 6°)    : SUN_MEDIUM     SUN_BRIGHT     WHITE
    //   Orange (≥ 0°) : ORANGE_MEDIUM  ORANGE_BRIGHT  SUN_BRIGHT
    //   Red    (≥-6°) : RED_MEDIUM     RED_BRIGHT     ORANGE_BRIGHT
    //   Purple (≥-12°): PURPLE_MEDIUM  PURPLE_BRIGHT  RED_BRIGHT
    //   Blue   (else) : BLUE_MEDIUM    BLUE_BRIGHT    BLUE_BRIGHT
    //
    // Minute text matches the band's BRIGHT, whitened by the saturation
    // slider. All values are on the 64-colour MIP palette.

    const MIP_SUN_BRIGHT    = 0xFFFF00;   // pure yellow
    const MIP_SUN_MEDIUM    = 0xAAAA00;   // ochre

    const MIP_ORANGE_BRIGHT = 0xFFAA00;   // pure on-palette orange
    const MIP_ORANGE_MEDIUM = 0xAA5500;   // burnt amber

    const MIP_RED_BRIGHT    = 0xFF0000;   // pure red
    const MIP_RED_MEDIUM    = 0xAA0000;   // dark red

    const MIP_PURPLE_BRIGHT = 0xFF55FF;   // magenta-pink
    const MIP_PURPLE_MEDIUM = 0xAA00AA;   // saturated purple

    const MIP_BLUE_BRIGHT   = 0x55AAFF;   // pale blue (echoes AMOLED 0x5F6FFF)
    const MIP_BLUE_MEDIUM   = 0x0055AA;   // medium blue

    const MIP_MOON_BRIGHT   = 0xAAAAAA;
    const MIP_MOON_MEDIUM   = 0x808080;
    const MIP_MOON_DARK     = 0x555555;

    // Nearest on-palette equivalent to the AMOLED sunset accent (0xFF8000).
    // 0xFFAA00 = MIP_ORANGE_BRIGHT, which is already the dominant hue at
    // the horizon — change this independently if beta testing suggests otherwise.
    const MIP_SUNSET_ACCENT = 0xFFAA00;

    // Ring geometry shared by sun and moon halo drawing.
    const MIP_RING_THICKNESS_DEG = 3.0;

    // ── Colour functions ─────────────────────────────────────────────────────

    // Three MIP shades for the sun's halo at altitude, returned as
    // [OUTER, MIDDLE, CORE] in paint order (outer drawn first, core last).
    //
    // Each band's outer/middle ring is its own MEDIUM/BRIGHT, and the core
    // is the BRIGHT shade of the *next-warmer* band. The daytime band's
    // core is WHITE since there's no warmer band. The deepest-night band
    // reuses BLUE_BRIGHT for the core.
    function sunColorsForAlt(altDeg) {
        if (altDeg >= 6.0)   { return [MIP_SUN_MEDIUM,    MIP_SUN_BRIGHT,    0xFFFFFF];          }
        if (altDeg >= 0.0)   { return [MIP_ORANGE_MEDIUM, MIP_ORANGE_BRIGHT, MIP_SUN_BRIGHT];    }
        if (altDeg >= -6.0)  { return [MIP_RED_MEDIUM,    MIP_RED_BRIGHT,    MIP_ORANGE_BRIGHT]; }
        if (altDeg >= -12.0) { return [MIP_PURPLE_MEDIUM, MIP_PURPLE_BRIGHT, MIP_RED_BRIGHT];    }
        return [MIP_BLUE_MEDIUM, MIP_BLUE_BRIGHT, MIP_BLUE_BRIGHT];
    }

    // The band's BRIGHT shade — used as the MIP minute-text colour.
    function brightSunColorForAlt(altDeg) {
        if (altDeg >= 6.0)   { return MIP_SUN_BRIGHT;    }
        if (altDeg >= 0.0)   { return MIP_ORANGE_BRIGHT; }
        if (altDeg >= -6.0)  { return MIP_RED_BRIGHT;    }
        if (altDeg >= -12.0) { return MIP_PURPLE_BRIGHT; }
        return MIP_BLUE_BRIGHT;
    }

    // Moon lit-face colour: full moon uses WHITE for maximum contrast;
    // all other phases use MIP_MOON_BRIGHT.
    function moonLitColor(isFullMoon) {
        return isFullMoon ? 0xFFFFFF : MIP_MOON_BRIGHT;
    }

    // ── Drawing functions ────────────────────────────────────────────────────

    // Sun: three concentric rings at 6°, 12°, 18° of sky-disc angle
    // (core, middle, outer). Painted outermost first so the white/ember
    // core lands on top.
    function drawSun(dc, x, y, R, altDeg) {
        var colors = sunColorsForAlt(altDeg);

        var outerR  = R * (18.0 / 90.0);
        var middleR = R * (12.0 / 90.0);
        var coreR   = R * ( 6.0 / 90.0);

        var xi = x.toNumber();
        var yi = y.toNumber();

        dc.setColor(colors[0], 0x000000);
        dc.fillCircle(xi, yi, MathUtil.roundNearest(outerR));

        dc.setColor(colors[1], 0x000000);
        dc.fillCircle(xi, yi, MathUtil.roundNearest(middleR));

        dc.setColor(colors[2], 0x000000);
        dc.fillCircle(xi, yi, MathUtil.roundNearest(coreR));
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

    // Halo body used for the full moon: outerColor ring → innerColor ring → brightColor disc.
    // scale controls how large the glow extends (0 = body only); grows from bodyR outward.
    function drawHaloBody(dc, x, y, R, bodyR, glowDeg, scale, brightColor, innerColor, outerColor) {
        var xi = x.toNumber();
        var yi = y.toNumber();
        var bodyRi = MathUtil.roundNearest(bodyR);

        if (scale <= 0.0) {
            dc.setColor(brightColor, 0x000000);
            dc.fillCircle(xi, yi, bodyRi);
            return;
        }

        var glowR  = bodyR + (R * (glowDeg / 90.0) - bodyR) * scale;
        var innerR = glowR - R * (MIP_RING_THICKNESS_DEG / 90.0);

        if (innerR < bodyR) { innerR = bodyR; }

        dc.setColor(outerColor, 0x000000);
        dc.fillCircle(xi, yi, MathUtil.roundNearest(glowR));

        dc.setColor(innerColor, 0x000000);
        dc.fillCircle(xi, yi, MathUtil.roundNearest(innerR));

        dc.setColor(brightColor, 0x000000);
        dc.fillCircle(xi, yi, bodyRi);
    }

}
