using Toybox.Graphics;
using Toybox.Math;

// MoonArt — everything that draws the moon, for both display types.
//
// Shapes:
//   new       : an unlit disc, the same size as every other phase
//   crescent  : lit disc with a larger shifted disc cut out of it
//   quarter   : lit disc with a half-plane cut out of it
//   gibbous   : lit circle through both horn tips, cut to the disc
//               (classic drawing: half disc plus an ellipse)
//   full      : lit disc with a glow
//
// Dark side (the "Show the moon's dark side" setting, off by default). Where
// the device supports it, the unlit part of the moon shows as a dim disc.
// With the setting off, the same drawing is used with black as the unlit
// colour, so the dark side is black, as it always was.
//
// Layered drawing (devices with bitmap-texture fills: Connect IQ 4 with a
// GPU). Every phase but new and full is built off screen, in two steps, and
// only when the phase, the tilt step or the colours change:
//   1. A square "picture" of the moon, fully opaque, in the unlit colour:
//        quarter, crescent : the lit disc, then the cut-out in unlit colour
//        gibbous           : one lit circle through both horn tips
//      Shapes may spill past the disc here; it does not matter.
//   2. A transparent square "layer", with one native filled circle whose fill
//      is the picture (a BitmapTexture). Only the disc is painted.
// On screen, a normal frame then costs one bitmap. Because circles look the
// same from every direction, the lit side can face the sun in fine steps
// (every 5°) for every phase, gibbous included.
//
// Nothing here paints "transparent" with a shape. Connect IQ only honours
// BLEND_MODE_NO_BLEND when drawing bitmaps, so a transparent fill would leave
// the pixels unchanged rather than punching a hole.
//
// Classic drawing (older devices, e.g. Forerunner 245, or if the layer cannot
// be built): the original drawing, unchanged. Coarse steps (crescent 12,
// quarter 8, gibbous 4), black cut-outs painted straight onto the screen and
// clipped to the moon's own square, gibbous as a half disc plus an
// axis-aligned ellipse. No dark side on these devices.
module MoonArt {

    const BLACK = 0x000000;

    var _layer       = null;    // BufferedBitmap holding the finished moon disc
    var _layerKey    = null;    // [radiusPx, phaseBin, tiltBin, litColor, shade] it was drawn for
    var _layerHalf   = 0;       // distance from the bitmap's corner to the moon's centre
    var _layerFailed = false;   // set once if the layer cannot be built on this device

    // ── Entry point ──────────────────────────────────────────────────────────

    // cache = the sky cache built by CircadiaView.updateSkyCache().
    function draw(dc, cache, mipMode) {
        var cx = cache[0];
        var cy = cache[1];
        var R  = cache[2];
        var sunAlt = cache[3];
        var sx = cache[4];
        var sy = cache[5];
        var mx = cache[6];
        var my = cache[7];
        var moonDiameter = cache[8];
        var moonRadius   = cache[9];
        var phaseAngle   = cache[10];
        var phaseBin     = cache[11];

        if (phaseBin == Lunar.PHASE_FULL) {
            drawFull(dc, mx, my, moonRadius, phaseAngle, sunAlt, cx, cy, R, mipMode);
        } else if (Drawing.intersectsSkyDisc(mx, my, moonRadius, cx, cy, R)) {
            drawPhase(dc, mx, my, moonDiameter, sx, sy, phaseBin, mipMode);
        }
    }

    // ── Full moon ────────────────────────────────────────────────────────────

    function drawFull(dc, mx, my, moonRadius, phaseAngle, sunAlt, cx, cy, R, mipMode) {
        var closeness  = closenessToFull(phaseAngle);
        var fullGlowR  = R * (AmoledArt.MOON_GLOW_DEG / 90.0);
        var glowOuterR = moonRadius + closeness * (fullGlowR - moonRadius);
        var litColor   = mipMode ? MiPArt.moonLitColor(true) : AmoledArt.MOON_AMOLED;
        var xi = MathUtil.roundNearest(mx);
        var yi = MathUtil.roundNearest(my);

        Lunar.resetOrientationBins();

        if (closeness > 0.0 && Drawing.intersectsSkyDisc(mx, my, glowOuterR, cx, cy, R)) {
            if (mipMode) {
                MiPArt.drawHaloGlow(dc, xi, yi, R, moonRadius, AmoledArt.MOON_GLOW_DEG, closeness, MiPArt.MIP_MOON_DARK, MiPArt.MIP_MOON_MEDIUM);
            } else {
                AmoledArt.drawMoonGlow(dc, xi, yi, moonRadius, closeness, sunAlt, litColor, R);
            }
        }
        if (Drawing.intersectsSkyDisc(mx, my, moonRadius, cx, cy, R)) {
            dc.setColor(litColor, BLACK);
            dc.fillCircle(xi, yi, MathUtil.roundNearest(moonRadius));
        }
    }

    // 1 at the exact full moon, falling to 0 at the edge of the glow window.
    function closenessToFull(phaseAngle) {
        return MathUtil.clamp(1.0 - MathUtil.abs(MathUtil.wrap180(phaseAngle - 180.0)) / Lunar.FULL_MOON_WINDOW_DEG, 0.0, 1.0);
    }

    // 0 while the sun is up, rising to 1 once it is 6 degrees below the horizon.
    function glowNightScale(sunAltDeg) {
        return MathUtil.clamp((-sunAltDeg) / 6.0, 0.0, 1.0);
    }

    // ── New, crescent, quarter and gibbous ───────────────────────────────────

    function isGibbous(bin) {
        return bin == Lunar.PHASE_WAXING_NEAR_HALF_GIBBOUS || bin == Lunar.PHASE_WAXING_NEAR_FULL_GIBBOUS
            || bin == Lunar.PHASE_WANING_NEAR_FULL_GIBBOUS || bin == Lunar.PHASE_WANING_NEAR_HALF_GIBBOUS;
    }

    function isQuarter(bin) {
        return bin == Lunar.PHASE_FIRST_QUARTER || bin == Lunar.PHASE_LAST_QUARTER;
    }

    function isThinCrescent(bin) {
        return bin == Lunar.PHASE_WAXING_THIN_CRESCENT || bin == Lunar.PHASE_WANING_THIN_CRESCENT;
    }

    function drawPhase(dc, mx, my, diameterPx, sx, sy, bin, mipMode) {
        var r  = diameterPx / 2.0;
        var xi = MathUtil.roundNearest(mx);
        var yi = MathUtil.roundNearest(my);
        var ri = MathUtil.roundNearest(r);

        var litColor  = mipMode ? MiPArt.MIP_MOON_BRIGHT : AmoledArt.MOON_AMOLED;
        var darkColor = mipMode ? MiPArt.MIP_MOON_DARK   : AmoledArt.MOON_DARK;
        var layered   = layerSupported(dc);
        var darkSide  = layered && config.moonDarkSide();

        // The unlit colour: dim grey with the dark side on, black with it off.
        var shade = darkSide ? darkColor : BLACK;

        // New moon: the whole disc is unlit. It is the same size as every
        // other phase; without the dark side it is a black disc, which only
        // shows where it passes in front of the sun's glow.
        if (bin == Lunar.PHASE_NEW) {
            Lunar.resetOrientationBins();
            dc.setColor(shade, BLACK);
            dc.fillCircle(xi, yi, ri);
            return;
        }

        var angle = Lunar.moonOrientationAngle(mx, my, sx, sy);

        // Layered drawing: every phase is built off screen, so the lit side
        // can face the sun in fine steps (Lunar.FINE_BIN_COUNT directions).
        if (layered) {
            var fineBin = Lunar.fineOrientationBin(angle);
            if (ensureLayer(r, bin, fineBin, litColor, shade)) {
                dc.drawBitmap(xi - _layerHalf, yi - _layerHalf, _layer);
                return;
            }
            // The layer could not be built: fall through to the classic moon.
        }

        // ── Classic drawing (devices without bitmap-texture fills) ──────────
        // Unchanged from the original: coarse steps, black cut-outs.

        // Gibbous: a half disc plus an ellipse, both lined up with the screen,
        // so only four directions.
        if (isGibbous(bin)) {
            Lunar.resetHalfAndCrescentBins();
            var gibbousBin = Lunar.gibbousOrientationBin(angle);

            dc.setColor(shade, BLACK);
            dc.fillCircle(xi, yi, ri);
            dc.setColor(litColor, Graphics.COLOR_TRANSPARENT);
            drawGibbousComposite(dc, xi, yi, r, gibbousBin, gibbousTermFrac(bin));
            return;
        }

        // Quarter and crescent: lit disc, then the cut-out painted in black
        // straight on screen. The cut-out shapes are larger than the moon, so
        // they are clipped to the moon's own square to keep them off whatever
        // is next to it.
        var dir;
        if (isQuarter(bin)) {
            Lunar.resetGibbousAndCrescentBins();
            dir = Lunar.binDirection(Lunar.halfOrientationBin(angle), Lunar.HALF_BIN_COUNT);
        } else {
            Lunar.resetGibbousAndHalfBins();
            dir = Lunar.binDirection(Lunar.crescentOrientationBin(angle), Lunar.CRESCENT_BIN_COUNT);
        }

        dc.setColor(litColor, BLACK);
        dc.fillCircle(xi, yi, ri);
        dc.setColor(BLACK, BLACK);
        if (Drawing.setInnerClip(dc, xi - ri - 1, yi - ri - 1, 2 * ri + 3, 2 * ri + 3)) {
            drawCutout(dc, xi, yi, r, bin, dir[0], dir[1]);
        }
        Drawing.restoreClip(dc);
    }

    function gibbousTermFrac(bin) {
        return (bin == Lunar.PHASE_WAXING_NEAR_HALF_GIBBOUS || bin == Lunar.PHASE_WANING_NEAR_HALF_GIBBOUS)
            ? Lunar.GIBBOUS_TERM_FRAC_NEAR_HALF
            : Lunar.GIBBOUS_TERM_FRAC_NEAR_FULL;
    }

    // Paint the unlit part of a quarter or crescent moon centred on (xi, yi),
    // in whatever colour the caller has set: black on screen, the unlit
    // colour inside the off-screen picture. (ux, uy) points at the sun.
    function drawCutout(dc, xi, yi, r, bin, ux, uy) {
        if (isQuarter(bin)) {
            fillHalfPlane(dc, xi, yi, r, ux, uy);
            return;
        }

        var shiftFrac = Lunar.CRESCENT_SHIFT_FRAC_THICK;
        var cutFrac   = Lunar.CRESCENT_BLACK_FRAC_THICK;
        if (isThinCrescent(bin)) {
            shiftFrac = Lunar.CRESCENT_SHIFT_FRAC_THIN;
            cutFrac   = Lunar.CRESCENT_BLACK_FRAC_THIN;
        }
        fillShiftedCircle(dc, xi, yi, r, ux, uy, shiftFrac, cutFrac * r);
    }

    // The lit part of a gibbous moon, for the off-screen picture: one circle,
    // shifted towards the sun (ux, uy), that passes through both horn tips
    // and crosses the axis termFrac * r beyond the centre on the dark side,
    // the same depth as the classic ellipse. The picture is later cut to the
    // moon's disc, so the circle may spill past it.
    //
    // Circle through (0, +-r) and (-a, 0) in the moon's frame, sun along +x:
    //   centre c = (r*r - a*a) / (2a) towards the sun, radius c + a.
    function fillGibbousLit(dc, xi, yi, r, ux, uy, termFrac) {
        var a  = termFrac * r;
        var c  = (r * r - a * a) / (2.0 * a);
        dc.fillCircle(
            xi + MathUtil.roundNearest(c * ux),
            yi + MathUtil.roundNearest(c * uy),
            MathUtil.roundNearest(c + a));
    }

    // A circle of radius rc, shifted away from the sun direction (ux, uy).
    function fillShiftedCircle(dc, xi, yi, r, ux, uy, shiftFrac, rc) {
        var shift = 2.0 * r * shiftFrac;
        var dx = MathUtil.roundNearest(shift * ux);
        var dy = MathUtil.roundNearest(shift * uy);

        dc.fillCircle(xi - dx, yi - dy, MathUtil.roundNearest(rc));
    }

    // The half-plane behind the moon's centre, seen from the sun direction
    // (ux, uy): a rectangle 4.4r wide that starts on the line through the
    // centre and extends 2.2r away from the sun.
    function fillHalfPlane(dc, xi, yi, r, ux, uy) {
        var vx = -uy;
        var vy =  ux;

        var t = -2.2 * r;
        var s =  2.2 * r;

        dc.fillPolygon([
            [MathUtil.roundNearest(xi + t*ux - s*vx), MathUtil.roundNearest(yi + t*uy - s*vy)],
            [MathUtil.roundNearest(xi + t*ux + s*vx), MathUtil.roundNearest(yi + t*uy + s*vy)],
            [MathUtil.roundNearest(xi + s*vx),        MathUtil.roundNearest(yi + s*vy)],
            [MathUtil.roundNearest(xi - s*vx),        MathUtil.roundNearest(yi - s*vy)]
        ]);
    }

    // ── Gibbous ──────────────────────────────────────────────────────────────

    function drawGibbousComposite(dc, xi, yi, r, orient, termFrac) {
        if (orient == Lunar.ORIENT_RIGHT) {
            drawGibbousHorizontal(dc, xi, yi, r, true, termFrac);
            return;
        }
        if (orient == Lunar.ORIENT_DOWN) {
            drawGibbousVertical(dc, xi, yi, r, true, termFrac);
            return;
        }
        if (orient == Lunar.ORIENT_LEFT) {
            drawGibbousHorizontal(dc, xi, yi, r, false, termFrac);
            return;
        }
        drawGibbousVertical(dc, xi, yi, r, false, termFrac);
    }

    function drawGibbousHorizontal(dc, xi, yi, r, rightSide, termFrac) {
        var ri = MathUtil.roundNearest(r);
        var rx = MathUtil.roundNearest(r * termFrac);
        var d  = MathUtil.roundNearest(2.0 * r);

        if (Drawing.setInnerClip(dc,
                rightSide ? xi : MathUtil.roundNearest(xi - r),
                MathUtil.roundNearest(yi - r),
                ri + 1,
                d + 1)) {
            dc.fillCircle(xi, yi, ri);
        }
        Drawing.restoreClip(dc);

        dc.fillEllipse(xi, yi, rx, ri);
    }

    function drawGibbousVertical(dc, xi, yi, r, downSide, termFrac) {
        var ri = MathUtil.roundNearest(r);
        var ry = MathUtil.roundNearest(r * termFrac);
        var d  = MathUtil.roundNearest(2.0 * r);

        if (Drawing.setInnerClip(dc,
                MathUtil.roundNearest(xi - r),
                downSide ? yi : MathUtil.roundNearest(yi - r),
                d + 1,
                ri + 1)) {
            dc.fillCircle(xi, yi, ri);
        }
        Drawing.restoreClip(dc);

        dc.fillEllipse(xi, yi, ri, ry);
    }

    // ── Off-screen layer ─────────────────────────────────────────────────────

    // Needs off-screen bitmaps, bitmap textures and the fill tool. setFill()
    // only exists on devices with a GPU, so it is checked on the live dc.
    function layerSupported(dc) {
        return !_layerFailed
            && (Toybox.Graphics has :createBufferedBitmap)
            && (Toybox.Graphics has :BitmapTexture)
            && (dc has :setFill);
    }

    // Make sure _layer holds this moon. Returns false if the layer cannot be
    // built, in which case the caller draws the classic moon.
    function ensureLayer(r, bin, tiltBin, litColor, shade) {
        if (_layer != null && _layerKey != null
            && _layerKey[0] == r && _layerKey[1] == bin
            && _layerKey[2] == tiltBin && _layerKey[3] == litColor
            && _layerKey[4] == shade) {
            return true;
        }

        _layer    = null;
        _layerKey = null;

        try {
            var bmp = renderLayer(r, bin, tiltBin, litColor, shade);
            if (bmp == null) {
                _layerFailed = true;
                return false;
            }
            _layer    = bmp;
            _layerKey = [r, bin, tiltBin, litColor, shade];
            return true;
        } catch (e) {
            _layerFailed = true;
            return false;
        }
    }

    // Build the finished moon (any phase but new and full) on a transparent
    // square. tiltBin is a Lunar.FINE_BIN_COUNT direction bin.
    //
    // Both bitmaps are exactly the moon's bounding square, with the moon's
    // centre at (ri, ri). The disc's bounding box then starts at the bitmap's
    // corner, so a texture offset of 0 lines the picture up with the disc
    // whichever corner the texture is anchored to.
    function renderLayer(r, bin, tiltBin, litColor, shade) {
        var ri   = MathUtil.roundNearest(r);
        var size = 2 * ri + 1;

        // 1. The picture, opaque. Quarter and crescent: unlit colour
        //    everywhere, the lit disc, then the cut-out in the unlit colour.
        //    Gibbous: unlit colour everywhere, then one lit circle.
        var pic = makeBitmap(size);
        if (pic == null) { return null; }
        var pdc = pic.getDc();
        var dir = Lunar.binDirection(tiltBin, Lunar.FINE_BIN_COUNT);
        pdc.setColor(shade, shade);
        pdc.clear();
        pdc.setColor(litColor, shade);
        if (isGibbous(bin)) {
            fillGibbousLit(pdc, ri, ri, r, dir[0], dir[1], gibbousTermFrac(bin));
        } else {
            pdc.fillCircle(ri, ri, ri);
            pdc.setColor(shade, shade);
            drawCutout(pdc, ri, ri, r, bin, dir[0], dir[1]);
        }

        // 2. The layer: transparent, with one circle filled from the picture.
        //    clear() with a transparent background really does write
        //    transparent pixels into a BufferedBitmap.
        var layer = makeBitmap(size);
        if (layer == null) { return null; }
        var ldc = layer.getDc();
        if (!(ldc has :setFill)) { return null; }
        ldc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_TRANSPARENT);
        ldc.clear();
        ldc.setFill(new Graphics.BitmapTexture({
            :bitmap  => pic,
            :offsetX => 0,
            :offsetY => 0
        }));
        ldc.fillCircle(ri, ri, ri);

        // Let go of the texture so the picture's memory can be reclaimed.
        // (0xFF000000 is opaque black.)
        ldc.setFill(0xFF000000);

        _layerHalf = ri;
        return layer;
    }

    function makeBitmap(size) {
        var ref = Graphics.createBufferedBitmap({
            :width         => size,
            :height        => size,
            :alphaBlending => Graphics.ALPHA_BLENDING_FULL
        });
        if (ref == null) { return null; }
        return ref.get();
    }

}
