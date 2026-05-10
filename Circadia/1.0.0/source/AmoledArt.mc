using Toybox.Graphics;
using Toybox.Math;

// AmoledArt — all AMOLED-specific art in one place.
//
// Colour constants, sun/moon colour functions, and the AMOLED glow-drawing
// routines all live here so they can be tuned independently of the
// structural drawing code in drawing.mc and the MIP art in MiPArt.mc.
module AmoledArt {

    // ── Universal ────────────────────────────────────────────────────────────
    const BLACK = 0x000000;
    const WHITE = 0xFFFFFF;

    // ── AMOLED solar palette ─────────────────────────────────────────────────
    // Smoothly blended between altitude bands; matches the minute-text colour
    // after whitening.
    const SUN_YELLOW  = 0xFFFF00;
    const SUN_ORANGE  = 0xFFAA00;
    const SUN_RED     = 0xFF0000;
    const SUN_PURPLE  = 0xD060FF;
    const SUN_BLUE    = 0x5F6FFF;

    // ── Moon ─────────────────────────────────────────────────────────────────
    const MOON_AMOLED = 0xC8CDD3;   // soft silver disc on AMOLED

    // ── Stars (colour-bin lookup) ─────────────────────────────────────────────
    const STAR_YELLOW       = 0xFDEBD2;
    const STAR_SOFT_YELLOW  = 0xFFF6D8;
    const STAR_RED          = 0xFFB08A;
    const STAR_BLUE         = 0xC9D8FF;
    const STAR_WHITE        = 0xF4F4FF;

    // ── Accents ───────────────────────────────────────────────────────────────
    const SUNSET_ACCENT = 0xFF8000;   // tinges the hour text near sunrise/sunset

    // ── Sun drawing constants ─────────────────────────────────────────────────
    const SUN_GLOW_DEG       = 25.0;  // cosine rim — chosen so halo is visually ~18° from centre
    const SUN_OUTER_CORE_DEG =  8.0;  // outer core ring (WHITE → sunColor)
    const SUN_INNER_CORE_DEG =  4.0;  // inner core (always white)
    const SUN_GLOW_CUTOFF_DEG = 18.0;

    // ── Moon glow drawing constants ───────────────────────────────────────────
    const MOON_GLOW_DEG                 = 45.0;
    const MOON_RING_THICKNESS_DEG       = 15.0;
    const MAX_MOON_GLOW_BRIGHTNESS      = 0.5;
    const INNER_MOON_GLOW_BRIGHTNESS_SCALE = 0.5;

    // ── Glow bitmap cache ─────────────────────────────────────────────────────
    // One slot per stable sun colour. Slot 0 = YELLOW, Slot 1 = BLUE.
    // Transitional colours (orange/red/purple) appear briefly and are drawn
    // directly without a cache.
    const GLOW_SLOT_YELLOW = 0;
    const GLOW_SLOT_BLUE   = 1;

    var _glowBitmap   = [null, null];
    var _glowR        = [-1.0, -1.0];
    var _glowDeg      = [-1.0, -1.0];
    var _glowRadiusPx = [0, 0];

    var _transparent;

    // ── Colour functions ──────────────────────────────────────────────────────

    // Blended colour for the sun's body at altitude.
    function sunColorForAlt(altDeg) {
        if (altDeg >= 12.0)  { return SUN_YELLOW; }
        if (altDeg >= 6.0)   { return MathUtil.blendColor(SUN_YELLOW, SUN_ORANGE, (12.0 - altDeg) / 6.0); }
        if (altDeg >= 0.0)   { return MathUtil.blendColor(SUN_ORANGE, SUN_RED,    (6.0  - altDeg) / 6.0); }
        if (altDeg >= -6.0)  { return MathUtil.blendColor(SUN_RED,    SUN_PURPLE, (-altDeg)        / 6.0); }
        if (altDeg >= -12.0) { return MathUtil.blendColor(SUN_PURPLE, SUN_BLUE,   (-6.0 - altDeg)  / 6.0); }
        return SUN_BLUE;
    }

    // Whiten sunColor by (1 - saturation) for the AMOLED minute text.
    function brightSunColor(sunColor, saturation) {
        return MathUtil.blendColor(WHITE, sunColor, MathUtil.clamp(saturation, 0.0, 1.0));
    }

    function sunsetAccentScale(sunAltDeg) {
        return MathUtil.clamp(1.0 - MathUtil.abs(sunAltDeg) / Solar.SUNSET_ACCENT_ALT_DEG, 0.0, 1.0);
    }

    // ── Sun drawing ───────────────────────────────────────────────────────────

    // Map a sun colour to a glow-cache slot, or -1 if no cache exists for it.
    function glowCacheSlot(sunColor) {
        if (sunColor == SUN_YELLOW) { return GLOW_SLOT_YELLOW; }
        if (sunColor == SUN_BLUE)   { return GLOW_SLOT_BLUE; }
        return -1;
    }

    function ensureTransparent() {
        if (_transparent == null) {
            _transparent = Graphics.createColor(0, 0, 0, 0);
        }
    }

    function drawSunGlow(dc, x, y, cx, cy, R, sunColor, glowDeg) {
        if (Toybox.Graphics has :createBufferedBitmap) {
            var slot = glowCacheSlot(sunColor);
            if (slot >= 0) {
                var bmp = getGlowBitmap(slot, sunColor, R, glowDeg);
                if (bmp != null) {
                    dc.drawBitmap(x.toNumber() - _glowRadiusPx[slot], y.toNumber() - _glowRadiusPx[slot], bmp);
                    return;
                }
            }
        }
        drawSunGlowDirect(dc, x, y, cx, cy, R, sunColor, glowDeg);
    }

    // AMOLED sun — three concentric zones:
    //   Inner core  [0,          SUN_INNER_CORE_DEG] : pure WHITE
    //   Outer core  [INNER_CORE, SUN_OUTER_CORE_DEG] : WHITE → sunColor, cosine brightness
    //   Halo        [OUTER_CORE, SUN_GLOW_DEG]       : sunColor, cosine brightness continued
    //
    // A single cosine brightness curve B(t) = 0.5*(1+cos(π*t)) spans both outer
    // core and halo, where t=0 at the inner core edge and t=1 at SUN_GLOW_DEG.
    // The cosine reaches exactly 0 at the rim, so the halo fades to black at
    // precisely SUN_GLOW_DEG — no artificial inflation needed.
    function drawSunGlowDirect(dc, x, y, cx, cy, R, sunColor, glowDeg) {
        var drawDeg     = (glowDeg < SUN_GLOW_CUTOFF_DEG + 3.0) ? glowDeg : SUN_GLOW_CUTOFF_DEG + 3.0;
        var glowPx      = R * (glowDeg / 90.0);
        var drawPx      = R * (drawDeg / 90.0);
        var outerCorePx = R * (SUN_OUTER_CORE_DEG / 90.0);
        var innerCorePx = R * (SUN_INNER_CORE_DEG / 90.0);
        var bodySpan    = glowPx - innerCorePx;
        var haloSteps   = (drawDeg - SUN_OUTER_CORE_DEG).toNumber();
        var outerSteps  = (SUN_OUTER_CORE_DEG - SUN_INNER_CORE_DEG).toNumber();
        var xi = x.toNumber();
        var yi = y.toNumber();

        var dx = xi - cx.toNumber();
        var dy = yi - cy.toNumber();
        var d  = Math.sqrt(dx*dx + dy*dy);

        // Halo: 1°/step, sunColor with cosine brightness
        for (var i = haloSteps; i >= 1; i -= 1) {
            var ri = outerCorePx + (drawPx - outerCorePx) * i.toFloat() / haloSteps;
            if (d - ri >= R) { continue; }
            var t = (ri - innerCorePx) / bodySpan;
            var b = 0.5 * (1.0 + Math.cos(Math.PI * t));
            dc.setColor(Solar.scaleColor(sunColor, b), BLACK);
            dc.fillCircle(xi, yi, ri.toNumber());
        }

        // Outer core: WHITE → sunColor with same cosine brightness
        for (var j = outerSteps; j >= 1; j -= 1) {
            var rj = innerCorePx + (outerCorePx - innerCorePx) * j.toFloat() / outerSteps;
            if (d - rj >= R) { continue; }
            var t2 = (rj - innerCorePx) / bodySpan;
            var b2 = 0.5 * (1.0 + Math.cos(Math.PI * t2));
            var hue = MathUtil.blendColor(WHITE, sunColor, j.toFloat() / outerSteps);
            dc.setColor(Solar.scaleColor(hue, b2), BLACK);
            dc.fillCircle(xi, yi, rj.toNumber());
        }

        // Inner core: pure white
        dc.setColor(WHITE, BLACK);
        dc.fillCircle(xi, yi, innerCorePx.toNumber());
    }

    // Glow-bitmap cache: keyed on (slot, sunColor, R, glowDeg).
    function getGlowBitmap(slot, sunColor, R, glowDeg) {
        if (_glowBitmap[slot] != null
            && _glowR[slot]   == R
            && _glowDeg[slot] == glowDeg) {
            return _glowBitmap[slot];
        }

        var drawDeg  = (glowDeg < SUN_GLOW_CUTOFF_DEG + 3.0) ? glowDeg : SUN_GLOW_CUTOFF_DEG + 3.0;
        var glowPx   = R * (drawDeg / 90.0);
        var radiusPx = glowPx.toNumber() + 2;
        var size     = 2*radiusPx + 1;

        var ref = Graphics.createBufferedBitmap({
            :width         => size,
            :height        => size,
            :alphaBlending => Graphics.ALPHA_BLENDING_FULL
        });
        if (ref == null) { return null; }

        var bmp = ref.get();
        if (bmp == null) { return null; }

        ensureTransparent();

        var bdc = bmp.getDc();
        bdc.setColor(BLACK, _transparent);
        bdc.clear();

        drawSunGlowDirect(bdc, radiusPx, radiusPx, radiusPx, radiusPx, R, sunColor, glowDeg);

        _glowBitmap[slot]   = bmp;
        _glowR[slot]        = R;
        _glowDeg[slot]      = glowDeg;
        _glowRadiusPx[slot] = radiusPx;

        return bmp;
    }

    // ── Moon glow drawing ─────────────────────────────────────────────────────

    function drawMoonGlow(dc, xi, yi, moonRadiusPx, phaseAngle, sunAltDeg, litColor, skyRadiusPx) {
        var radiusScale = Drawing.closenessToFullMoon(phaseAngle) * Drawing.moonGlowNightScale(sunAltDeg);
        if (radiusScale <= 0.0) { return; }

        var outerR = skyRadiusPx * (MOON_GLOW_DEG / 90.0) * radiusScale;
        if (outerR <= 0.5) { return; }

        var glowSteps = MathUtil.roundNearest(1.0 * MOON_GLOW_DEG * radiusScale);
        if (glowSteps < 1) { glowSteps = 1; }

        drawOffsetMoonGlowCircle(dc, xi, yi, moonRadiusPx, outerR, litColor, MAX_MOON_GLOW_BRIGHTNESS, glowSteps);
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
