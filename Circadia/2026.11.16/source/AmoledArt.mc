using Toybox.Graphics;
using Toybox.Math;

// AmoledArt — all AMOLED-specific art in one place.
//
// Colour constants, sun/moon colour functions, and the AMOLED sun and moon-glow
// drawing all live here so they can be tuned independently of the structural
// drawing code in drawing.mc and the MIP art in MiPArt.mc. The sun's sizes and
// its edge flare are shared with MIP and live in sun.mc.
module AmoledArt {

    // ── Universal ────────────────────────────────────────────────────────────
    const BLACK = 0x000000;
    const WHITE = 0xFFFFFF;

    // ── AMOLED solar palette ─────────────────────────────────────────────────
    // One colour per twilight boundary, smoothly blended in between: yellow
    // down to +6, orange at sunset, red at the end of civil twilight, purple at
    // the end of nautical twilight, blue at full night. The sun, its edge flare
    // and the minute text all use this colour.
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
    const CORONA_FRAC       = [1.00, 0.85, 0.70, 0.55, 0.40, 0.25, 0.12];
    const CORONA_BRIGHTNESS = [0.05, 0.08, 0.12, 0.17, 0.23, 0.31, 0.42];

    // Core: the sun's colour at its edge, grading to white at the edge of the
    // white disc; everything inside that is pure white. POS is the position
    // across the rim (1 = edge of the core, 0 = edge of the white disc); WHITE
    // is how far toward white each step has gone.
    const CORE_STEP_POS   = [1.00, 0.75, 0.50, 0.25, 0.00];
    const CORE_STEP_WHITE = [0.00, 0.18, 0.42, 0.70, 1.00];

    // Edge flare: up to 8 bands, each at least 3px thick, brightest at the rim.
    const FLARE_MAX_BANDS       = 8;
    const FLARE_MIN_BAND_PX     = 3.0;
    const FLARE_PEAK_BRIGHTNESS = 0.55;
    const FLARE_FALLOFF         = 1.3;

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

    // Corona rings and flare bands are merged dimmest-first, so the brighter
    // of the two shows wherever they overlap. Both lists are already in order
    // of rising brightness: corona from the outside in, flare from its inner
    // edge out to the rim. The core goes on top.
    function drawSun(dc, cx, cy, R, sx, sy, altDeg) {
        var deg = R / 90.0;
        var col = sunColorForAlt(altDeg);
        var xi  = MathUtil.roundNearest(sx);
        var yi  = MathUtil.roundNearest(sy);

        var rings = SunArt.coronaVisible(altDeg) ? CORONA_FRAC.size() : 0;
        var bands = SunArt.prepareFlare(cx, cy, R, sx, sy, altDeg, FLARE_MIN_BAND_PX, FLARE_MAX_BANDS);

        var ring = 0;           // next corona ring; 0 is the outermost and dimmest
        var band = bands - 1;   // next flare band; the innermost is the dimmest

        while (ring < rings || band >= 0) {
            var ringB = (ring < rings) ? CORONA_BRIGHTNESS[ring] : 2.0;
            var bandB = (band >= 0)    ? flareBrightness(band, bands) : 2.0;

            if (bandB <= ringB) {
                SunArt.drawFlareBand(dc, cx, cy, R, band, bands, MathUtil.scaleColor(col, bandB));
                band -= 1;
            } else {
                var rDeg = SunArt.CORE_DEG + CORONA_FRAC[ring] * (SunArt.OUTER_DEG - SunArt.CORE_DEG);
                dc.setColor(MathUtil.scaleColor(col, ringB), BLACK);
                dc.fillCircle(xi, yi, MathUtil.roundNearest(rDeg * deg));
                ring += 1;
            }
        }

        if (SunArt.coreVisible(altDeg)) {
            drawSunCore(dc, xi, yi, SunArt.WHITE_DISC_DEG * deg, SunArt.CORE_DEG * deg, col, SunArt.whiteHot(altDeg));
        }
    }

    function flareBrightness(band, bands) {
        var u = (band + 0.5) / bands;
        return FLARE_PEAK_BRIGHTNESS * Math.pow(1.0 - u, FLARE_FALLOFF);
    }

    // whiteHot = 1: a pure white disc of radius whitePx, giving way to the
    // sun's colour at the edge of the core. whiteHot = 0: one flat disc in the
    // sun's colour.
    function drawSunCore(dc, xi, yi, whitePx, corePx, col, whiteHot) {
        if (whiteHot <= 0.0) {
            dc.setColor(col, BLACK);
            dc.fillCircle(xi, yi, MathUtil.roundNearest(corePx));
            return;
        }

        var centre = MathUtil.blendColor(col, WHITE, whiteHot);
        for (var i = 0; i < CORE_STEP_POS.size(); i += 1) {
            dc.setColor(MathUtil.blendColor(col, centre, CORE_STEP_WHITE[i]), BLACK);
            dc.fillCircle(xi, yi, MathUtil.roundNearest(whitePx + CORE_STEP_POS[i] * (corePx - whitePx)));
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
