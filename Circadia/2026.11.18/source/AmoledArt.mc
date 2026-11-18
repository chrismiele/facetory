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

    // ── Accents ───────────────────────────────────────────────────────────────
    const SUNSET_ACCENT = 0xFF8000;   // tinges the hour text near sunrise/sunset

    // ── Sun ───────────────────────────────────────────────────────────────────
    // Corona: rings between the core's edge and the sun's outer edge, listed
    // from the outside in. FRAC is the position across the corona (1 = outer
    // edge, 0 = edge of the core); BRIGHTNESS scales the sun's colour.
    // Twelve evenly spaced rings, brightness 0.20 + 0.65 * t, where t runs
    // from 0 at the outer edge to 1 at the innermost ring.
    const CORONA_FRAC       = [1.000, 0.915, 0.829, 0.744, 0.658, 0.573,
                               0.487, 0.402, 0.316, 0.231, 0.145, 0.060];
    const CORONA_BRIGHTNESS = [0.200, 0.259, 0.318, 0.377, 0.436, 0.495,
                               0.555, 0.614, 0.673, 0.732, 0.791, 0.850];

    // Core: the sun's colour at its edge, grading to white at the edge of the
    // white disc; everything inside that is pure white. POS is the position
    // across the rim (1 = edge of the core, 0 = edge of the white disc); WHITE
    // is how far toward white each step has gone.
    const CORE_STEP_POS   = [1.00, 0.75, 0.50, 0.25, 0.00];
    const CORE_STEP_WHITE = [0.00, 0.18, 0.42, 0.70, 1.00];

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

        // With the horizon glow on, every layer below spreads along the
        // horizon after +6; otherwise each is a plain circle around the sun.
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

    // whiteHot = 1: a pure white disc, giving way to the sun's colour at the
    // edge of the core. whiteHot = 0: one flat disc in the sun's colour.
    function drawSunCore(dc, col, whiteHot) {
        if (whiteHot <= 0.0) {
            SunArt.drawLayer(dc, SunArt.CORE_DEG, col);
            return;
        }

        var centre = MathUtil.blendColor(col, WHITE, whiteHot);
        for (var i = 0; i < CORE_STEP_POS.size(); i += 1) {
            var rDeg = SunArt.WHITE_DISC_DEG + CORE_STEP_POS[i] * (SunArt.CORE_DEG - SunArt.WHITE_DISC_DEG);
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
