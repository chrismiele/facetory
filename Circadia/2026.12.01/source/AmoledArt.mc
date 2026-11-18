using Toybox.Graphics;
using Toybox.Math;

// AmoledArt — all AMOLED-specific art in one place.
//
// Colour constants, sun/moon colour functions, and the AMOLED sun and moon-glow
// drawing all live here so they can be tuned independently of the structural
// drawing code in drawing.mc and the MIP art in MiPArt.mc. The sun's sizes and
// the way it spreads along the horizon live in sun.mc.
module AmoledArt {

    // ── Universal ────────────────────────────────────────────────────────────
    const BLACK = 0x000000;
    const WHITE = 0xFFFFFF;

    // ── AMOLED solar palette ─────────────────────────────────────────────────
    // One colour per twilight boundary, smoothly blended in between: yellow
    // down to +6, orange at sunset, red at the end of civil twilight, purple at
    // the end of nautical twilight, blue at full night. The sun (spread along
    // the horizon or not) and the minute text use this colour.
    const SUN_YELLOW  = 0xFFFF00;
    const SUN_ORANGE  = 0xFFAA00;
    const SUN_RED     = 0xFF0000;
    const SUN_PURPLE  = 0xD060FF;
    const SUN_BLUE    = 0x5F6FFF;

    // ── Moon ─────────────────────────────────────────────────────────────────
    const MOON_AMOLED = 0xC8CDD3;   // soft silver disc on AMOLED
    const MOON_DARK   = 0x24262A;   // unlit side: just visible against the black sky

    // ── Stars (colour-bin lookup) ─────────────────────────────────────────────
    const STAR_YELLOW       = 0xFFD080;   // warmer, more amber
    const STAR_SOFT_YELLOW  = 0xFFE8B0;   // pale cream (was nearly white)
    const STAR_RED          = 0xFF6B4A;   // genuinely red-orange
    const STAR_BLUE         = 0x80A8FF;   // clearly blue, not tinted white
    const STAR_WHITE        = 0xF4F4FF;
    const STAR_BRIGHTNESS   = 0.8;
    const CONSTELLATION_LINE = 0x1F3366;  // deep blue, faint against black

    // ── Accents ───────────────────────────────────────────────────────────────
    const SUNSET_ACCENT = 0xFF8000;   // tinges the hour text near sunrise/sunset

    // ── Sun ───────────────────────────────────────────────────────────────────
    // The sun from the centre out, by day:
    //    0 -  9 deg   pure white
    //    9 - 11 deg   an S-curve from white to the sun's colour (half white at
    //                 the 10 deg edge of the white disc)
    //   11 - 12 deg   a ring of the sun's colour at full brightness
    //   12 - 18 deg   the corona: it leaves the core's colour smoothly, bends
    //                 onto a straight fade by 14 deg, and reaches 20% at its
    //                 hard outer edge
    // After sunset the white is gone, so the core is the sun's colour all the
    // way out to 12 deg.

    // Corona: rings between the core's edge and the sun's outer edge, listed
    // from the outside in. FRAC is each ring's outer radius as a position
    // across the corona (1 = outer edge, 0 = edge of the core); BRIGHTNESS
    // scales the sun's colour, taken at the middle of the ring. Sixteen evenly
    // spaced rings. The straight fade, 0.20 + 0.65 * (1 - t) / 0.94 for t
    // across the corona, is bent up to full brightness at the core's edge
    // over the first third (12 to 14 deg) along a half cosine.
    const CORONA_FRAC       = [1.0000, 0.9375, 0.8750, 0.8125, 0.7500, 0.6875, 0.6250, 0.5625,
                               0.5000, 0.4375, 0.3750, 0.3125, 0.2500, 0.1875, 0.1250, 0.0625];
    const CORONA_BRIGHTNESS = [0.222, 0.265, 0.308, 0.351, 0.394, 0.438, 0.481, 0.524,
                               0.567, 0.611, 0.654, 0.715, 0.809, 0.902, 0.968, 0.997];

    // The white disc's soft edge: steps from WHITE_EDGE_DEG outside the white
    // disc's edge to WHITE_EDGE_DEG inside it, listed from the outside in. POS
    // is each step's radius as WHITE_DISC_DEG + POS * WHITE_EDGE_DEG; WHITE is
    // how far toward white it has gone, along a half cosine taken at the
    // middle of the step. The last step is the pure white disc.
    const WHITE_EDGE_DEG  = 1.0;
    const CORE_STEP_POS   = [1.00, 0.75, 0.50, 0.25, 0.00, -0.25, -0.50, -0.75, -1.00];
    const CORE_STEP_WHITE = [0.010, 0.084, 0.222, 0.402, 0.598, 0.778, 0.916, 0.990, 1.000];

    // ── Moon glow drawing constants ───────────────────────────────────────────
    const MOON_GLOW_DEG                 = 45.0;
    const MOON_RING_THICKNESS_DEG       = 15.0;
    const MAX_MOON_GLOW_BRIGHTNESS      = 0.5;
    const INNER_MOON_GLOW_BRIGHTNESS_SCALE = 0.5;

    var _starColors = null;

    // ── Colour functions ──────────────────────────────────────────────────────

    // Blended colour for the sun at altitude.
    function sunColorForAlt(altDeg) {
        if (altDeg >= 6.0)   { return SUN_YELLOW; }
        if (altDeg >= 0.0)   { return MathUtil.blendColor(SUN_YELLOW, SUN_ORANGE, (6.0   - altDeg) / 6.0); }
        if (altDeg >= -6.0)  { return MathUtil.blendColor(SUN_ORANGE, SUN_RED,    (-altDeg)        / 6.0); }
        if (altDeg >= -12.0) { return MathUtil.blendColor(SUN_RED,    SUN_PURPLE, (-6.0  - altDeg) / 6.0); }
        if (altDeg >= -18.0) { return MathUtil.blendColor(SUN_PURPLE, SUN_BLUE,   (-12.0 - altDeg) / 6.0); }
        return SUN_BLUE;
    }

    // Whiten sunColor by (1 - saturation) for the AMOLED minute text.
    function brightSunColor(sunColor, saturation) {
        return MathUtil.blendColor(WHITE, sunColor, MathUtil.clamp(saturation, 0.0, 1.0));
    }

    function sunsetAccentScale(sunAltDeg) {
        return MathUtil.clamp(1.0 - MathUtil.abs(sunAltDeg) / Solar.SUNSET_ACCENT_ALT_DEG, 0.0, 1.0);
    }

    // Star colours, indexed by Drawing.STAR_BIN_*. Built once.
    function starColors() {
        if (_starColors == null) {
            _starColors = [
                MathUtil.scaleColor(STAR_YELLOW,      STAR_BRIGHTNESS),
                MathUtil.scaleColor(STAR_SOFT_YELLOW, STAR_BRIGHTNESS),
                MathUtil.scaleColor(STAR_RED,         STAR_BRIGHTNESS),
                MathUtil.scaleColor(STAR_BLUE,        STAR_BRIGHTNESS),
                MathUtil.scaleColor(STAR_WHITE,       STAR_BRIGHTNESS)
            ];
        }
        return _starColors;
    }

    // ── Sun drawing ───────────────────────────────────────────────────────────

    // Layers are painted from the outside in, so each brighter layer goes on
    // top of the dimmer one around it. The core goes on top of the corona.
    function drawSun(dc, cx, cy, R, sx, sy, altDeg) {
        var col = sunColorForAlt(altDeg);

        // Every layer below spreads along the horizon after +6 (see sun.mc).
        SunArt.prepareSpread(cx, cy, R, sx, sy, altDeg, SunArt.OUTER_DEG);

        // Corona, from the outside in.
        if (SunArt.coronaVisible(altDeg)) {
            for (var i = 0; i < CORONA_FRAC.size(); i += 1) {
                var rDeg = SunArt.CORE_DEG + CORONA_FRAC[i] * (SunArt.OUTER_DEG - SunArt.CORE_DEG);
                SunArt.drawLayer(dc, rDeg, MathUtil.scaleColor(col, CORONA_BRIGHTNESS[i]));
            }
        }

        if (SunArt.coreVisible(altDeg)) {
            drawSunCore(dc, col, SunArt.whiteHot(altDeg));
        }
    }

    // A disc in the sun's colour out to the core's edge, then (while whiteHot
    // > 0) the white disc on top, with its soft edge. whiteHot = 1: pure white
    // at the centre; whiteHot = 0: no white at all.
    function drawSunCore(dc, col, whiteHot) {
        SunArt.drawLayer(dc, SunArt.CORE_DEG, col);
        if (whiteHot <= 0.0) { return; }

        var centre = MathUtil.blendColor(col, WHITE, whiteHot);
        for (var i = 0; i < CORE_STEP_POS.size(); i += 1) {
            var rDeg = SunArt.WHITE_DISC_DEG + CORE_STEP_POS[i] * WHITE_EDGE_DEG;
            SunArt.drawLayer(dc, rDeg, MathUtil.blendColor(col, centre, CORE_STEP_WHITE[i]));
        }
    }

    // ── Moon glow drawing ─────────────────────────────────────────────────────

    function drawMoonGlow(dc, xi, yi, moonRadiusPx, closeness, sunAltDeg, litColor, skyRadiusPx) {
        if (closeness <= 0.0) { return; }
        var nightScale = MoonArt.glowNightScale(sunAltDeg);
        if (nightScale <= 0.0) { return; }

        var outerR = moonRadiusPx + closeness * (skyRadiusPx * (MOON_GLOW_DEG / 90.0) - moonRadiusPx);

        var glowSteps = MathUtil.roundNearest(MOON_GLOW_DEG * closeness);
        if (glowSteps < 1) { glowSteps = 1; }

        drawOffsetMoonGlowCircle(dc, xi, yi, moonRadiusPx, outerR, litColor, MAX_MOON_GLOW_BRIGHTNESS * nightScale, glowSteps);
    }

    function drawOffsetMoonGlowCircle(dc, xg, yg, moonRadiusPx, outerR, litColor, brightnessScale, glowSteps) {
        var thicknessR = outerR * (MOON_RING_THICKNESS_DEG / MOON_GLOW_DEG);
        var innerR = outerR - thicknessR;
        if (innerR < 0.0) { innerR = 0.0; }

        var midR = 0.5 * (outerR + innerR);
        var outerEdgeBrightness = 0.1 * brightnessScale;
        var innerEdgeBrightness = INNER_MOON_GLOW_BRIGHTNESS_SCALE * brightnessScale;

        for (var i = glowSteps; i >= 1; i -= 1) {
            var f  = i.toFloat() / glowSteps.toFloat();
            var rr = outerR * f;
            var brightness;

            if (rr >= midR) {
                brightness = brightnessScale
                    + (outerEdgeBrightness - brightnessScale) * (rr - midR) / (outerR - midR);
            } else if (rr >= innerR) {
                brightness = innerEdgeBrightness
                    + (brightnessScale - innerEdgeBrightness) * (rr - innerR) / (midR - innerR);
            } else if (rr >= moonRadiusPx && innerR > moonRadiusPx) {
                brightness = brightnessScale
                    + (innerEdgeBrightness - brightnessScale) * (rr - moonRadiusPx) / (innerR - moonRadiusPx);
            } else {
                continue;
            }

            var c = MathUtil.blendColor(BLACK, litColor, brightness);

            dc.setColor(c, BLACK);
            dc.fillCircle(MathUtil.roundNearest(xg), MathUtil.roundNearest(yg), MathUtil.roundNearest(rr));
        }
    }

}
