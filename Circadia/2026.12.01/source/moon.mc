using Toybox.Graphics;
using Toybox.Math;

// MoonArt — everything that draws the moon, for both display types.
//
// Phases:
//   new       : nothing, or with the dark side on, a dim disc the same
//               size as every other phase
//   full      : lit disc with a glow
//   otherwise : on devices with the layered drawing (below), the true shape
//               for the exact phase: the dividing line moves half a pixel at
//               a time, looks the same at every tilt, and crescents and
//               gibbous moons are mirror images. On older devices, the
//               original 10 fixed shapes (classic).
//
// Dark side (the "Show the moon's dark side" setting, off by default). Where
// the device supports it, the unlit part of the moon shows as a dim disc.
// With the setting off, the layered drawing leaves the unlit part clear, so
// whatever is behind it shows through: black sky, or the sun's glow when a
// young or old crescent sits in twilight. Stars behind it are hidden all
// the same, by the moon's shadow (drawShadow()). The classic drawing paints
// the unlit part black, as it always has.
//
// Layered drawing (devices with bitmap-texture fills: Connect IQ 4 with a
// GPU). Every phase but new and full is built off screen, in two steps, and
// only when the phase moves the dividing line by half a pixel, the tilt
// moves to the next 5° step, or the colours change:
//   1. A square "picture" of the moon, fully opaque: a lit or unlit
//      background plus one circle in the other colour, painted row by row
//      from its exact geometry. See paintPhasePicture(). The circle may
//      spill past the disc here; it does not matter.
//   2. A transparent square "layer", with one native filled circle whose fill
//      is the picture (a BitmapTexture). Only the disc is painted.
// On screen, a normal frame then costs one bitmap. Because circles look the
// same from every direction, the lit side can face the sun at any angle.
//
// Nothing here paints "transparent" with a shape. Connect IQ only honours
// BLEND_MODE_NO_BLEND when drawing bitmaps, so a transparent fill would leave
// the pixels unchanged rather than punching a hole.
//
// Classic drawing (older devices, e.g. Forerunner 245, or if the layer cannot
// be built): the original drawing, unchanged. Twelve phase steps, coarse
// tilts (crescent 12, quarter 8, gibbous 4), crescents and quarters as a lit
// disc with a black cut-out painted straight onto the screen and clipped to
// the moon's own square, gibbous as a half disc plus an axis-aligned
// ellipse. No dark side on these devices.
module MoonArt {

    const BLACK = 0x000000;

    var _layer       = null;    // BufferedBitmap holding the finished moon disc
    var _layerKey    = null;    // [radiusPx, terminatorKey, tiltBin, litColor, shade] it was drawn for (shade null: clear)
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
            drawFull(dc, mx, my, moonRadius, phaseAngle, sunAlt, [cx, cy, R], mipMode);
        } else if (Drawing.intersectsSkyDisc(mx, my, moonRadius, cx, cy, R)) {
            drawPhase(dc, mx, my, moonDiameter, sx, sy, phaseBin, phaseAngle, mipMode);
        }
    }

    // The moon's whole disc in black, drawn over the stars before the sun
    // (Drawing.drawSky), so stars never show through the moon, lit or not.
    function drawShadow(dc, cache) {
        var mx = cache[6];
        var my = cache[7];
        var moonRadius = cache[9];
        if (Drawing.intersectsSkyDisc(mx, my, moonRadius, cache[0], cache[1], cache[2])) {
            dc.setColor(BLACK, BLACK);
            dc.fillCircle(MathUtil.roundNearest(mx), MathUtil.roundNearest(my), MathUtil.roundNearest(moonRadius));
        }
    }

    // ── Full moon ────────────────────────────────────────────────────────────

    function drawFull(dc, mx, my, moonRadius, phaseAngle, sunAlt, sky, mipMode) {
        var cx = sky[0];
        var cy = sky[1];
        var R  = sky[2];
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

    function drawPhase(dc, mx, my, diameterPx, sx, sy, bin, phaseAngle, mipMode) {
        var r  = diameterPx / 2.0;
        var xi = MathUtil.roundNearest(mx);
        var yi = MathUtil.roundNearest(my);
        var ri = MathUtil.roundNearest(r);

        var litColor  = mipMode ? MiPArt.MIP_MOON_BRIGHT : AmoledArt.MOON_AMOLED;
        var darkColor = mipMode ? MiPArt.MIP_MOON_DARK   : AmoledArt.MOON_DARK;
        var layered   = layerSupported(dc);
        var darkSide  = layered && config.moonDarkSide();

        // The unlit colour: dim grey with the dark side on, black with it off
        // (the layered drawing leaves it clear instead; see the header).
        var shade = darkSide ? darkColor : BLACK;

        // New moon: the whole disc is unlit, so without the dark side there
        // is nothing to draw. With it, a dim disc the same size as every
        // other phase.
        if (bin == Lunar.PHASE_NEW) {
            Lunar.resetOrientationBins();
            if (darkSide) {
                dc.setColor(shade, BLACK);
                dc.fillCircle(xi, yi, ri);
            }
            return;
        }

        var angle = Lunar.moonOrientationAngle(mx, my, sx, sy);

        // Layered drawing: every phase is built off screen, so the lit side
        // can face the sun in fine steps (Lunar.FINE_BIN_COUNT directions)
        // and the dividing line follows the actual phase, pixel by pixel.
        if (layered) {
            var fineBin = Lunar.fineOrientationBin(angle);
            var term    = terminatorKey(ri, phaseAngle);
            if (ensureLayer(r, term, fineBin, litColor, darkSide ? shade : null, !mipMode)) {
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

    // ── Continuous phase (layered drawing) ───────────────────────────────────
    //
    // The line between the lit and unlit parts (the terminator) crosses the
    // moon's axis at  x = r * cos(phaseAngle)  from the centre, measured
    // towards the sun: +r at new moon, 0 at the quarters, -r at full moon.
    // It is drawn as the circle through both horn tips (the poles, 0, +-r)
    // and that crossing point:
    //   crescent (x > 0): lit background, unlit circle centred on the dark side
    //   gibbous  (x < 0): unlit background, lit circle centred on the sun side
    // A crescent at phase p and a gibbous at 180 - p use mirror-image
    // circles, so the two are exact complements.
    //
    // The circle is painted row by row from its exact (unrounded) centre and
    // radius, so the moon looks the same at every tilt. Native circles need
    // whole-pixel centres, and that rounding changes with the tilt, which
    // made thin crescents swell and shrink as the moon turned. On AMOLED the
    // pixels the edge passes through get a blend of the two colours; on MIP
    // the edge is hard.
    //
    // PHASE_SHAPE_EXPONENT 1.0 is the true shape. Raising it (e.g. 2.0)
    // fattens crescents and the dark slivers of gibbous moons alike, for
    // readability, while keeping the two symmetric.
    const PHASE_SHAPE_EXPONENT = 1.0;

    // The terminator position in half-pixel steps: floor(2x). The picture
    // uses the middle of the step, (key + 0.5) / 2, which is never 0, so the
    // circle never becomes a straight line (at the quarters it is simply very
    // large). floor() keeps waxing and waning moons mirror images.
    function terminatorKey(ri, phaseAngle) {
        var c = MathUtil.cosDeg(phaseAngle);
        var m = MathUtil.abs(c);
        if (PHASE_SHAPE_EXPONENT != 1.0) {
            m = Math.pow(m, PHASE_SHAPE_EXPONENT);
        }
        var x = ((c < 0.0) ? -m : m) * ri;
        return Math.floor(2.0 * x).toNumber();
    }

    // Paint the whole size x size picture for a moon of radius ri centred on
    // pixel (ri, ri), with the sun in direction (ux, uy). Pixel (x, y) is
    // treated as the point at its centre. shade null leaves the unlit part
    // transparent: the picture starts clear and only lit pixels are painted
    // (a transparent colour cannot be painted over another), with the
    // blended edge pixels mixed towards black, as over the night sky.
    function paintPhasePicture(dc, size, ri, key, ux, uy, litColor, shade, smooth) {
        var r   = ri.toFloat();
        var t   = (key + 0.5) / 2.0;
        var cc  = (t * t - r * r) / (2.0 * t);     // circle centre, along (ux, uy)
        var rho = MathUtil.abs(t - cc);            // circle radius
        var bg  = (t > 0.0) ? litColor : shade;    // either may be null (clear)
        var fg  = (t > 0.0) ? shade : litColor;
        var cx  = ri + cc * ux;
        var cy  = ri + cc * uy;
        var last = size - 1;

        // A clear circle on a lit background is painted as the background
        // around it, row by row, below.
        var clearCircle = (fg == null);
        if (bg == null || clearCircle) {
            dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(bg, bg);
        }
        dc.clear();
        var bgMix = (bg == null) ? BLACK : bg;
        var fgMix = (fg == null) ? BLACK : fg;

        // Pixels closer to the centre than rIn are all foreground; pixels
        // further than rOut are all background; in between they are blended.
        var rOut = smooth ? rho + 0.5 : rho;
        var rIn  = smooth ? rho - 0.5 : rho;
        var rOut2 = rOut * rOut;
        var rIn2  = rIn * rIn;

        for (var y = 0; y < size; y++) {
            var dy  = y - cy;
            var dy2 = dy * dy;
            if (dy2 >= rOut2) {
                if (clearCircle) {
                    dc.setColor(bg, bg);
                    dc.fillRectangle(0, y, size, 1);
                }
                continue;
            }

            var ho = Math.sqrt(rOut2 - dy2);
            var x0 = Math.ceil(cx - ho).toNumber();
            var x1 = Math.floor(cx + ho).toNumber();
            if (x1 < 0 || x0 > last) {
                if (clearCircle) {
                    dc.setColor(bg, bg);
                    dc.fillRectangle(0, y, size, 1);
                }
                continue;
            }
            if (x0 < 0)    { x0 = 0; }
            if (x1 > last) { x1 = last; }

            // The background either side of the circle, when it was not
            // cleared to it.
            if (clearCircle) {
                dc.setColor(bg, bg);
                if (x0 > 0)    { dc.fillRectangle(0, y, x0, 1); }
                if (x1 < last) { dc.fillRectangle(x1 + 1, y, last - x1, 1); }
            }

            // The solid span.
            var s0 = x1 + 1;
            var s1 = x1;
            if (dy2 < rIn2) {
                var hi = Math.sqrt(rIn2 - dy2);
                s0 = Math.ceil(cx - hi).toNumber();
                s1 = Math.floor(cx + hi).toNumber();
                if (s0 < x0) { s0 = x0; }
                if (s1 > x1) { s1 = x1; }
                if (s0 <= s1) {
                    if (!clearCircle) {
                        dc.setColor(fg, fg);
                        dc.fillRectangle(s0, y, s1 - s0 + 1, 1);
                    }
                } else {
                    s0 = x1 + 1;
                    s1 = x1;
                }
            }

            // The blended edge pixels on either side of it.
            if (smooth) {
                var leftEnd = (s0 <= s1) ? s0 - 1 : x1;
                for (var xl = x0; xl <= leftEnd; xl++) {
                    paintEdgePixel(dc, xl, y, cx, dy2, rho, bgMix, fgMix, clearCircle);
                }
                if (s0 <= s1) {
                    for (var xr = s1 + 1; xr <= x1; xr++) {
                        paintEdgePixel(dc, xr, y, cx, dy2, rho, bgMix, fgMix, clearCircle);
                    }
                }
            }
        }
    }

    // How much of pixel (x, y) lies inside the circle, approximated from the
    // distance of its centre to the edge, and painted as a blend.
    // cov is the share of the pixel inside the circle. A pixel wholly
    // outside it is background: already there, or (paintBg, the background
    // was not cleared to) painted now.
    function paintEdgePixel(dc, x, y, cx, dy2, rho, bg, fg, paintBg) {
        var dx  = x - cx;
        var cov = 0.5 + rho - Math.sqrt(dx * dx + dy2);
        if (cov <= 0.0) {
            if (paintBg) {
                dc.setColor(bg, bg);
                dc.drawPoint(x, y);
            }
            return;
        }
        var col = (cov >= 1.0) ? fg : mixColor(bg, fg, cov);
        dc.setColor(col, col);
        dc.drawPoint(x, y);
    }

    // a blended towards b by f (0..1), channel by channel.
    function mixColor(a, b, f) {
        var ar = (a >> 16) & 0xFF;
        var ag = (a >> 8) & 0xFF;
        var ab = a & 0xFF;
        var r = (ar + (((b >> 16) & 0xFF) - ar) * f + 0.5).toNumber();
        var g = (ag + (((b >> 8) & 0xFF) - ag) * f + 0.5).toNumber();
        var bl = (ab + ((b & 0xFF) - ab) * f + 0.5).toNumber();
        return (r << 16) | (g << 8) | bl;
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
    function ensureLayer(r, term, tiltBin, litColor, shade, smooth) {
        if (_layer != null && _layerKey != null
            && _layerKey[0] == r && _layerKey[1] == term
            && _layerKey[2] == tiltBin && _layerKey[3] == litColor
            && _layerKey[4] == shade) {
            return true;
        }

        _layer    = null;
        _layerKey = null;

        try {
            var bmp = renderLayer(r, term, tiltBin, litColor, shade, smooth);
            if (bmp == null) {
                _layerFailed = true;
                return false;
            }
            _layer    = bmp;
            _layerKey = [r, term, tiltBin, litColor, shade];
            return true;
        } catch (e) {
            _layerFailed = true;
            return false;
        }
    }

    // Build the finished moon (any phase but new and full) on a transparent
    // square. term is terminatorKey(); tiltBin is a Lunar.FINE_BIN_COUNT
    // direction bin; smooth blends the edge pixels (AMOLED).
    //
    // Both bitmaps are exactly the moon's bounding square, with the moon's
    // centre at (ri, ri). The disc's bounding box then starts at the bitmap's
    // corner, so a texture offset of 0 lines the picture up with the disc
    // whichever corner the texture is anchored to.
    function renderLayer(r, term, tiltBin, litColor, shade, smooth) {
        var ri   = MathUtil.roundNearest(r);
        var size = 2 * ri + 1;

        // 1. The picture: background plus one circle, painted row by row,
        //    opaque, or with the unlit part clear. See paintPhasePicture().
        var pic = makeBitmap(size);
        if (pic == null) { return null; }
        var dir = Lunar.binDirection(tiltBin, Lunar.FINE_BIN_COUNT);
        paintPhasePicture(pic.getDc(), size, ri, term, dir[0], dir[1], litColor, shade, smooth);

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
