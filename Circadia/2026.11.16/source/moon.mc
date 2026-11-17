using Toybox.Graphics;
using Toybox.Math;

// MoonArt — everything that draws the moon, for both display types.
//
// Shapes are unchanged from the original drawing:
//   new       : an unlit disc, the same size as every other phase
//   crescent  : lit disc with a larger shifted disc cut out of it
//   quarter   : lit disc with a half-plane cut out of it
//   gibbous   : half disc plus an ellipse (nothing cut out)
//   full      : lit disc with a glow
//
// Dark side (the "Show the moon's dark side" setting, off by default). Where
// the device supports it, new, crescent, quarter and gibbous moons also show
// their unlit part as a dim disc. With the setting off, the same drawing is
// used with black as the unlit colour, so the dark side is black, as it
// always was.
//
// Quarter and crescent moons are built off screen, in two steps, and only
// when the phase, the snapped tilt or the colours change:
//   1. A square "picture" of the moon, fully opaque: unlit colour everywhere,
//      the lit disc, then the cut-out painted in the unlit colour. The
//      cut-out may spill past the disc here; it does not matter.
//   2. A transparent square "layer", with one native filled circle whose fill
//      is the picture (a BitmapTexture). Only the disc is painted, so the
//      spill never reaches the layer.
// On screen, a normal frame then costs one bitmap.
//
// Nothing here paints "transparent" with a shape. Connect IQ only honours
// BLEND_MODE_NO_BLEND when drawing bitmaps, so a transparent fill would leave
// the pixels unchanged rather than punching a hole.
//
// Which drawing path is used depends only on the device, never on settings:
//   layered   As above. Used on devices with bitmap-texture fills (Connect IQ
//             4 devices with a GPU). Nothing is ever drawn outside the disc.
//   classic   Fallback for devices without them (e.g. Forerunner 245), or if
//             the layer cannot be built. Lit disc, then black cut-outs
//             painted straight onto the screen. The cut-outs are larger than
//             the moon, so they are clipped to the moon's own square to keep
//             them off whatever is next to it. No dark side on these devices.
//
// Gibbous moons need no cut-out, so they are drawn directly on every device,
// over a dark or black disc.
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

        // The unlit disc that goes under every phase: dim grey with the dark
        // side on, black with it off.
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

        // Gibbous: the lit shape is built only from pieces inside the disc, so
        // it can go straight onto the screen over the dark circle.
        if (isGibbous(bin)) {
            Lunar.resetHalfAndCrescentBins();
            var gibbousBin = Lunar.gibbousOrientationBin(angle);
            var nearHalf   = (bin == Lunar.PHASE_WAXING_NEAR_HALF_GIBBOUS || bin == Lunar.PHASE_WANING_NEAR_HALF_GIBBOUS);

            dc.setColor(shade, BLACK);
            dc.fillCircle(xi, yi, ri);
            dc.setColor(litColor, Graphics.COLOR_TRANSPARENT);
            drawGibbousComposite(dc, xi, yi, r, gibbousBin,
                nearHalf ? Lunar.GIBBOUS_TERM_FRAC_NEAR_HALF : Lunar.GIBBOUS_TERM_FRAC_NEAR_FULL);
            return;
        }

        // Quarter and crescent: a lit disc with a piece cut out of it.
        var tiltBin;
        if (isQuarter(bin)) {
            Lunar.resetGibbousAndCrescentBins();
            tiltBin = Lunar.halfOrientationBin(angle);
        } else {
            Lunar.resetGibbousAndHalfBins();
            tiltBin = Lunar.crescentOrientationBin(angle);
        }

        if (layered && ensureLayer(r, bin, tiltBin, litColor, shade)) {
            dc.drawBitmap(xi - _layerHalf, yi - _layerHalf, _layer);
            return;
        }

        // Classic drawing (older devices only): the cut-out is painted in
        // black, straight on screen.
        // The cut-out shapes are larger than the moon, so they are clipped to
        // the moon's own square to keep them off whatever is next to it.
        dc.setColor(litColor, BLACK);
        dc.fillCircle(xi, yi, ri);
        dc.setColor(BLACK, BLACK);
        if (Drawing.setInnerClip(dc, xi - ri - 1, yi - ri - 1, 2 * ri + 3, 2 * ri + 3)) {
            drawCutout(dc, xi, yi, r, bin, tiltBin);
        }
        Drawing.restoreClip(dc);
    }

    // Paint the unlit part of a quarter or crescent moon centred on (xi, yi),
    // in whatever colour the caller has set: black on screen, the unlit
    // colour inside the off-screen picture.
    function drawCutout(dc, xi, yi, r, bin, tiltBin) {
        if (isQuarter(bin)) {
            var halfDir = Lunar.binDirection(tiltBin, Lunar.HALF_BIN_COUNT);
            fillHalfPlane(dc, xi, yi, r, halfDir[0], halfDir[1]);
            return;
        }

        var crescentDir = Lunar.binDirection(tiltBin, Lunar.CRESCENT_BIN_COUNT);
        var shiftFrac   = Lunar.CRESCENT_SHIFT_FRAC_THICK;
        var cutFrac     = Lunar.CRESCENT_BLACK_FRAC_THICK;
        if (isThinCrescent(bin)) {
            shiftFrac = Lunar.CRESCENT_SHIFT_FRAC_THIN;
            cutFrac   = Lunar.CRESCENT_BLACK_FRAC_THIN;
        }
        fillShiftedCircle(dc, xi, yi, r, crescentDir[0], crescentDir[1], shiftFrac, cutFrac * r);
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

    // ── Off-screen layer for quarter and crescent moons ─────────────────────

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

    // Build the finished quarter or crescent moon on a transparent square.
    //
    // Both bitmaps are exactly the moon's bounding square, with the moon's
    // centre at (ri, ri). The disc's bounding box then starts at the bitmap's
    // corner, so a texture offset of 0 lines the picture up with the disc
    // whichever corner the texture is anchored to.
    function renderLayer(r, bin, tiltBin, litColor, shade) {
        var ri   = MathUtil.roundNearest(r);
        var size = 2 * ri + 1;

        // 1. The picture: opaque, unlit colour everywhere, then the lit disc,
        //    then the cut-out in the unlit colour.
        var pic = makeBitmap(size);
        if (pic == null) { return null; }
        var pdc = pic.getDc();
        pdc.setColor(shade, shade);
        pdc.clear();
        pdc.setColor(litColor, shade);
        pdc.fillCircle(ri, ri, ri);
        pdc.setColor(shade, shade);
        drawCutout(pdc, ri, ri, r, bin, tiltBin);

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
