using Toybox.Graphics;
using Toybox.Math;

module Drawing {

    const BLACK = 0x000000;
    const WHITE = 0xFFFFFF;

    const STAR_SMALL  = 0;
    const STAR_MEDIUM = 1;
    const STAR_LARGE  = 2;
    const STAR_XL     = 3;

    // Star-colour bin indices used by Stellar to address fadedStarColors().
    const STAR_BIN_YELLOW      = 0;
    const STAR_BIN_SOFT_YELLOW = 1;
    const STAR_BIN_RED         = 2;
    const STAR_BIN_BLUE        = 3;
    const STAR_BIN_WHITE       = 4;

    const SMALL_STAR_FRAC  = 0.7;
    const MEDIUM_STAR_FRAC = 0.25;
    const LARGE_STAR_FRAC  = 0.03;

    const STAR_YELLOW_FRAC      = 0.30;
    const STAR_SOFT_YELLOW_FRAC = 0.25;
    const STAR_RED_FRAC         = 0.10;
    const STAR_BLUE_FRAC        = 0.10;

    const CLOCK_RADIUS_FRAC  = 0.6179775281;
    const CLOCK_AZ_DEG       = 0.0;
    const COLON_GAP_FRAC     = 0.0842696629;
    const COLON_V_SHIFT_FRAC = 0.0561797753;

    const TOP_FIELD_RADIUS_FRAC    = 0.67;
    const BOTTOM_FIELD_RADIUS_FRAC = 0.5;
    const TOP_FIELD_AZ_DEG         = 0.0;
    const SIDE_FIELD_OFFSET_DEG     = 40.0;
    const BOTTOM_RIGHT_FIELD_AZ_DEG = 180.0 - SIDE_FIELD_OFFSET_DEG;
    const BOTTOM_LEFT_FIELD_AZ_DEG  = 180.0 + SIDE_FIELD_OFFSET_DEG;

    const SECOND_TICK_LENGTH_FRAC     = 0.0449438202;
    const SECOND_TICK_HALF_WIDTH_FRAC = 0.0084269663;

    // Used by AmoledArt moon glow and by drawSky for the sun glow cutoff radius.
    const SUN_GLOW_CUTOFF_DEG = 18.0;

    // Pre-computed sin/cos table for the 60 second-tick angles. Lazy-built.
    // Saves ~120 trig calls per onPartialUpdate when seconds are enabled.
    var _secSin = null;
    var _secCos = null;

    function ensureSecondTickTable() {
        if (_secSin != null) { return; }
        _secSin = new [60];
        _secCos = new [60];
        for (var i = 0; i < 60; i += 1) {
            var a = 2.0 * Math.PI * i / 60.0;
            _secSin[i] = Math.sin(a);
            _secCos[i] = Math.cos(a);
        }
    }

    // Layout cache: just the polar coordinate origin and watch radius.
    function layout(w, h) {
        var cx = w/2.0;
        var cy = h/2.0;
        var R  = ((w < h) ? w : h)/2.0 - 2.0;
        return [cx, cy, R];
    }

    function projectBody(altAz, cx, cy, R) {
        return Solar.projectAltAz(altAz[0], altAz[1], cx, cy, R);
    }

    function moonRadiusPx(moonDiameterDeg, R) {
        return R*(moonDiameterDeg/90.0)/2.0 + 1.0;
    }

    function moonDiameterPx(moonDiameterDeg, R) {
        return R*(moonDiameterDeg/90.0);
    }

    // Clear the whole screen to black. Used when AOD shows time-only.
    function clearScreen(dc) {
        dc.setColor(BLACK, BLACK);
        dc.clear();
    }

    function drawSky(dc, cache, sunColor, showSun, showMoon, showStars, mipMode) {
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

        dc.setColor(BLACK, BLACK);
        dc.clear();

        var glowRadius = R*(SUN_GLOW_CUTOFF_DEG/90.0);
        if (showSun && intersectsSkyDisc(sx, sy, glowRadius, cx, cy, R)) {
            if (mipMode) {
                MiPArt.drawSun(dc, sx, sy, R, sunAlt);
            } else {
                AmoledArt.drawSunGlow(dc, sx, sy, cx, cy, R, sunColor, AmoledArt.SUN_GLOW_DEG);
            }
        }

        if (showStars) {
            Stellar.drawProjectedStars(dc);
        }

        if (showMoon) {
            if (phaseBin == Lunar.PHASE_FULL) {
                var closeness  = closenessToFullMoon(phaseAngle);
                var fullGlowR  = R * (AmoledArt.MOON_GLOW_DEG / 90.0);
                var glowOuterR = moonRadius + closeness * (fullGlowR - moonRadius);
                var litColor   = mipMode ? MiPArt.moonLitColor(true) : AmoledArt.MOON_AMOLED;
                var mxi = MathUtil.roundNearest(mx);
                var myi = MathUtil.roundNearest(my);
                Lunar.resetOrientationBins();
                if (closeness > 0.0 && intersectsSkyDisc(mx, my, glowOuterR, cx, cy, R)) {
                    if (mipMode) {
                        MiPArt.drawHaloGlow(dc, mxi, myi, R, moonRadius, AmoledArt.MOON_GLOW_DEG, closeness, MiPArt.MIP_MOON_DARK, MiPArt.MIP_MOON_MEDIUM);
                    } else {
                        AmoledArt.drawMoonGlow(dc, mxi, myi, moonRadius, closeness, sunAlt, litColor, R);
                    }
                }
                if (intersectsSkyDisc(mx, my, moonRadius, cx, cy, R)) {
                    dc.setColor(litColor, BLACK);
                    dc.fillCircle(mxi, myi, MathUtil.roundNearest(moonRadius));
                }
            } else if (intersectsSkyDisc(mx, my, moonRadius, cx, cy, R)) {
                drawMoonPhaseCached(
                    dc,
                    [mx, my],
                    moonDiameter,
                    [sx, sy, sunAlt],
                    phaseAngle,
                    phaseBin,
                    mipMode ? MiPArt.MIP_MOON_BRIGHT : AmoledArt.MOON_AMOLED,
                    R,
                    mipMode
                );
            }
        }
    }

    // time = [hour, min, sec]; fields = [topText, leftText, rightText]
    function drawFace(dc, cache, time, showSeconds, sunsetAccent, sunColor, fields, mipMode) {
        var cx = cache[0];
        var cy = cache[1];
        var R  = cache[2];

        if (showSeconds) {
            drawSecondTicks(dc, cx, cy, R, time[2]);
        }

        drawTopField(dc, cx, cy, R, fields[0]);
        drawDigitalClock(dc, cx, cy, R, time, sunsetAccent, sunColor, [fields[1], fields[2]], mipMode);
    }

    function drawSecondTickClipped(dc, cache, sec) {
        drawOneSecondTickClipped(dc, cache[0], cache[1], cache[2], sec);
    }

    function drawTopFieldClipped(dc, cache, text) {
        drawOneFieldClipped(dc, cache[0], cache[1], cache[2], TOP_FIELD_RADIUS_FRAC, TOP_FIELD_AZ_DEG, text);
    }

    function drawLeftFieldClipped(dc, cache, text) {
        drawOneFieldClipped(dc, cache[0], cache[1], cache[2], BOTTOM_FIELD_RADIUS_FRAC, BOTTOM_LEFT_FIELD_AZ_DEG, text);
    }

    function drawRightFieldClipped(dc, cache, text) {
        drawOneFieldClipped(dc, cache[0], cache[1], cache[2], BOTTOM_FIELD_RADIUS_FRAC, BOTTOM_RIGHT_FIELD_AZ_DEG, text);
    }

    function drawOneFieldClipped(dc, cx, cy, R, rhoFrac, azDeg, text) {
        var p = polarPoint(cx, cy, R, rhoFrac, azDeg);
        var x = p[0].toNumber();
        var y = p[1].toNumber();

        var font = Graphics.FONT_SYSTEM_TINY;
        var w = dc.getTextWidthInPixels(text, font);
        var h = dc.getFontHeight(font);

        var padX = 3;
        var padY = 2;

        dc.setClip(x - w/2 - padX, y - h/2 - padY, w + 2*padX, h + 2*padY);
        dc.setColor(BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x - 1, y,     font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x + 1, y,     font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x,     y - 1, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x,     y + 1, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.clearClip();
    }

    function intersectsSkyDisc(x, y, rObj, cx, cy, R) {
        var dx = x - cx;
        var dy = y - cy;
        var d = Math.sqrt(dx*dx + dy*dy);
        return d < R + rObj;
    }

    function polarPoint(cx, cy, R, rhoFrac, azDeg) {
        var rho = R*rhoFrac;
        var a = azDeg * MathUtil.DEG_TO_RAD;
        return [
            cx + rho*Math.sin(a),
            cy - rho*Math.cos(a)
        ];
    }

    function secondTickPolygon(cx, cy, R, i) {
        ensureSecondTickTable();

        var rOuter = R;
        var rInner = R - R*SECOND_TICK_LENGTH_FRAC;
        var hw     = R*SECOND_TICK_HALF_WIDTH_FRAC;

        var ux =  _secSin[i];
        var uy = -_secCos[i];
        var px = -uy;
        var py =  ux;

        var x0 = cx + rInner*ux;
        var y0 = cy + rInner*uy;
        var x1 = cx + rOuter*ux;
        var y1 = cy + rOuter*uy;

        return [
            [ (x0 - hw*px).toNumber(), (y0 - hw*py).toNumber() ],
            [ (x0 + hw*px).toNumber(), (y0 + hw*py).toNumber() ],
            [ (x1 + hw*px).toNumber(), (y1 + hw*py).toNumber() ],
            [ (x1 - hw*px).toNumber(), (y1 - hw*py).toNumber() ]
        ];
    }

    function drawSecondTicks(dc, cx, cy, R, sec) {
        dc.setColor(WHITE, BLACK);
        for (var i = 0; i <= sec; i += 1) {
            dc.fillPolygon(secondTickPolygon(cx, cy, R, i));
        }
    }

    function drawOneSecondTickClipped(dc, cx, cy, R, i) {
        var p = secondTickPolygon(cx, cy, R, i);
        var minX = p[0][0];
        var maxX = p[0][0];
        var minY = p[0][1];
        var maxY = p[0][1];

        for (var j = 1; j < 4; j += 1) {
            if (p[j][0] < minX) { minX = p[j][0]; }
            if (p[j][0] > maxX) { maxX = p[j][0]; }
            if (p[j][1] < minY) { minY = p[j][1]; }
            if (p[j][1] > maxY) { maxY = p[j][1]; }
        }

        var pad = 1;
        dc.setClip(minX - pad, minY - pad, maxX - minX + 2*pad, maxY - minY + 2*pad);
        dc.setColor(WHITE, BLACK);
        dc.fillPolygon(p);
        dc.clearClip();
    }

    function drawTopField(dc, cx, cy, R, topText) {
        if (topText == null) { return; }
        var p = polarPoint(cx, cy, R, TOP_FIELD_RADIUS_FRAC, TOP_FIELD_AZ_DEG);
        drawFieldText(dc, p[0].toNumber(), p[1].toNumber(), topText);
    }

    // time = [hour, min, ...]; texts = [leftText, rightText]
    function drawDigitalClock(dc, cx, cy, R, time, sunsetAccent, sunColor, texts, mipMode) {
        var font  = Graphics.FONT_SYSTEM_NUMBER_THAI_HOT;
        var displayHour = MathUtil.displayHour(time[0], config.is12hMode());
        var hText = MathUtil.twoDigits(displayHour);
        var mText = MathUtil.twoDigits(time[1]);

        var clockCenter = polarPoint(cx, cy, R, CLOCK_RADIUS_FRAC, CLOCK_AZ_DEG);
        var clockCx = clockCenter[0];
        var clockCy = clockCenter[1];

        var ascent  = Graphics.getFontAscent(font).toFloat();
        var descent = Graphics.getFontDescent(font).toFloat();
        var baselineY = clockCy + (ascent - descent)/2.0;

        var colonGap   = R*COLON_GAP_FRAC;
        var colonShift = R*COLON_V_SHIFT_FRAC;

        var accentColor = mipMode ? MiPArt.MIP_SUNSET_ACCENT : AmoledArt.SUNSET_ACCENT;
        dc.setColor(MathUtil.blendColor(WHITE, accentColor, sunsetAccent), Graphics.COLOR_TRANSPARENT);
        dc.drawText((clockCx - colonGap).toNumber(), baselineY.toNumber(), font, hText, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(clockCx.toNumber(), (baselineY - colonShift).toNumber(), font, ":", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(AmoledArt.brightSunColor(sunColor, config.minuteSaturation()), Graphics.COLOR_TRANSPARENT);
        dc.drawText((clockCx + colonGap).toNumber(), baselineY.toNumber(), font, mText, Graphics.TEXT_JUSTIFY_LEFT);

        drawSubfields(dc, cx, cy, R, texts[0], texts[1]);
    }

    function drawSubfields(dc, cx, cy, R, leftText, rightText) {
        if (leftText == null && rightText == null) { return; }
        var pL = polarPoint(cx, cy, R, BOTTOM_FIELD_RADIUS_FRAC, BOTTOM_LEFT_FIELD_AZ_DEG);
        var pR = polarPoint(cx, cy, R, BOTTOM_FIELD_RADIUS_FRAC, BOTTOM_RIGHT_FIELD_AZ_DEG);

        if (leftText  != null) { drawFieldText(dc, pL[0].toNumber(), pL[1].toNumber(), leftText);  }
        if (rightText != null) { drawFieldText(dc, pR[0].toNumber(), pR[1].toNumber(), rightText); }
    }

    // Field text is always white, with a 1px black outline for legibility
    // against any sky background.
    function drawFieldText(dc, x, y, text) {
        var font = Graphics.FONT_SYSTEM_TINY;
        dc.setColor(BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x - 1, y,     font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x + 1, y,     font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x,     y - 1, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(x,     y + 1, font, text, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawNewMoon(dc, xi, yi, ri) {
        dc.setColor(BLACK, BLACK);
        dc.fillCircle(xi, yi, ri);
    }

    function drawFullMoon(dc, xi, yi, moonRadiusPx, phaseAngle, sunAltDeg, litColor, skyRadiusPx, mipMode) {
        var closeness = closenessToFullMoon(phaseAngle);
        if (mipMode) {
            MiPArt.drawHaloBody(dc, xi, yi, skyRadiusPx, moonRadiusPx, AmoledArt.MOON_GLOW_DEG, closeness, [WHITE, MiPArt.MIP_MOON_DARK, MiPArt.MIP_MOON_MEDIUM]);
            return;
        }

        AmoledArt.drawMoonGlow(dc, xi, yi, moonRadiusPx, closeness, sunAltDeg, litColor, skyRadiusPx);
        dc.setColor(litColor, BLACK);
        dc.fillCircle(xi, yi, MathUtil.roundNearest(moonRadiusPx));
    }

    // moonPos = [x, y]; sunInfo = [sunX, sunY, sunAltDeg]
    function drawMoonPhaseCached(dc, moonPos, diameterPx, sunInfo, phaseAngle, bin, litColor, skyRadiusPx, mipMode) {
        var r  = diameterPx/2.0;
        var xi = MathUtil.roundNearest(moonPos[0]);
        var yi = MathUtil.roundNearest(moonPos[1]);
        var ri = MathUtil.roundNearest(r);

        if (mipMode) {
            litColor = MiPArt.moonLitColor(bin == Lunar.PHASE_FULL);
        }

        if (bin == Lunar.PHASE_NEW) {
            Lunar.resetOrientationBins();
            drawNewMoon(dc, xi, yi, ri);
            return;
        }

        if (bin == Lunar.PHASE_FULL) {
            Lunar.resetOrientationBins();
            drawFullMoon(dc, xi, yi, r, phaseAngle, sunInfo[2], litColor, skyRadiusPx, mipMode);
            return;
        }

        var angle = Lunar.moonOrientationAngle(moonPos[0], moonPos[1], sunInfo[0], sunInfo[1]);

        if (bin == Lunar.PHASE_WAXING_NEAR_HALF_GIBBOUS || bin == Lunar.PHASE_WAXING_NEAR_FULL_GIBBOUS ||
            bin == Lunar.PHASE_WANING_NEAR_FULL_GIBBOUS || bin == Lunar.PHASE_WANING_NEAR_HALF_GIBBOUS) {

            Lunar.resetHalfAndCrescentBins();
            var gibbousBin = Lunar.gibbousOrientationBin(angle);

            dc.setColor(litColor, Graphics.COLOR_TRANSPARENT);

            if (bin == Lunar.PHASE_WAXING_NEAR_HALF_GIBBOUS || bin == Lunar.PHASE_WANING_NEAR_HALF_GIBBOUS) {
                drawGibbousComposite(dc, xi, yi, r, gibbousBin, Lunar.GIBBOUS_TERM_FRAC_NEAR_HALF);
            } else {
                drawGibbousComposite(dc, xi, yi, r, gibbousBin, Lunar.GIBBOUS_TERM_FRAC_NEAR_FULL);
            }
            return;
        }

        dc.setColor(litColor, BLACK);
        dc.fillCircle(xi, yi, ri);

        if (bin == Lunar.PHASE_FIRST_QUARTER || bin == Lunar.PHASE_LAST_QUARTER) {
            Lunar.resetGibbousAndCrescentBins();
            var halfDir = Lunar.halfOrientationVector(angle);
            drawDarkHalf(dc, xi, yi, r, halfDir[0], halfDir[1]);
            return;
        }

        if (bin == Lunar.PHASE_WAXING_THIN_CRESCENT || bin == Lunar.PHASE_WANING_THIN_CRESCENT ||
            bin == Lunar.PHASE_WAXING_THICK_CRESCENT || bin == Lunar.PHASE_WANING_THICK_CRESCENT) {

            Lunar.resetGibbousAndHalfBins();
            var crescentDir = Lunar.crescentOrientationVector(angle);
            var shiftFrac   = Lunar.CRESCENT_SHIFT_FRAC_THICK;
            var blackFrac   = Lunar.CRESCENT_BLACK_FRAC_THICK;

            if (bin == Lunar.PHASE_WAXING_THIN_CRESCENT || bin == Lunar.PHASE_WANING_THIN_CRESCENT) {
                shiftFrac = Lunar.CRESCENT_SHIFT_FRAC_THIN;
                blackFrac = Lunar.CRESCENT_BLACK_FRAC_THIN;
            }

            drawShiftedBlackCircle(
                dc,
                xi,
                yi,
                r,
                crescentDir[0],
                crescentDir[1],
                shiftFrac,
                blackFrac*r
            );
            return;
        }
    }

    function drawShiftedBlackCircle(dc, xi, yi, moonRadiusPx, ux, uy, shiftFrac, rb) {
        var shift = 2.0 * moonRadiusPx * shiftFrac;
        var dx = MathUtil.roundNearest(shift*ux);
        var dy = MathUtil.roundNearest(shift*uy);
        var rbi = MathUtil.roundNearest(rb);

        dc.setColor(BLACK, BLACK);
        dc.fillCircle(xi - dx, yi - dy, rbi);
    }

    function drawDarkHalf(dc, xi, yi, r, ux, uy) {
        dc.setColor(BLACK, BLACK);

        var vx = -uy;
        var vy =  ux;

        // The dark-half polygon spans the moon's near-side rectangle: from
        // 2.2r behind the moon (along -ux) up to the moon's centre, full
        // width (4.4r). The "front" edge passes through (xi, yi).
        var t = -2.2*r;
        var s =  2.2*r;

        var x0 = MathUtil.roundNearest(xi + t*ux - s*vx);
        var y0 = MathUtil.roundNearest(yi + t*uy - s*vy);
        var x1 = MathUtil.roundNearest(xi + t*ux + s*vx);
        var y1 = MathUtil.roundNearest(yi + t*uy + s*vy);
        var x2 = MathUtil.roundNearest(xi + s*vx);
        var y2 = MathUtil.roundNearest(yi + s*vy);
        var x3 = MathUtil.roundNearest(xi - s*vx);
        var y3 = MathUtil.roundNearest(yi - s*vy);

        dc.fillPolygon([
            [x0, y0],
            [x1, y1],
            [x2, y2],
            [x3, y3]
        ]);
    }

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
        var rx = MathUtil.roundNearest(r*termFrac);
        var d  = MathUtil.roundNearest(2.0*r);

        dc.setClip(
            rightSide ? xi : MathUtil.roundNearest(xi - r),
            MathUtil.roundNearest(yi - r),
            ri + 1,
            d + 1
        );
        dc.fillCircle(xi, yi, ri);
        dc.clearClip();

        dc.fillEllipse(xi, yi, rx, ri);
    }

    function drawGibbousVertical(dc, xi, yi, r, downSide, termFrac) {
        var ri = MathUtil.roundNearest(r);
        var ry = MathUtil.roundNearest(r*termFrac);
        var d  = MathUtil.roundNearest(2.0*r);

        dc.setClip(
            MathUtil.roundNearest(xi - r),
            downSide ? yi : MathUtil.roundNearest(yi - r),
            d + 1,
            ri + 1
        );
        dc.fillCircle(xi, yi, ri);
        dc.clearClip();

        dc.fillEllipse(xi, yi, ri, ry);
    }

    function fadedStarColors(nightScale) {
        var starScale = 0.8*nightScale;
        return [
            MathUtil.blendColor(BLACK, AmoledArt.STAR_YELLOW,      starScale),
            MathUtil.blendColor(BLACK, AmoledArt.STAR_SOFT_YELLOW, starScale),
            MathUtil.blendColor(BLACK, AmoledArt.STAR_RED,         starScale),
            MathUtil.blendColor(BLACK, AmoledArt.STAR_BLUE,        starScale),
            MathUtil.blendColor(BLACK, AmoledArt.STAR_WHITE,       starScale)
        ];
    }

    function drawProjectedStar(dc, xi, yi, starSize, starColor) {
        dc.setColor(starColor, BLACK);

        if (starSize == STAR_XL) {
            dc.fillRectangle(xi - 2, yi - 2, 4, 4);
        } else if (starSize == STAR_LARGE) {
            dc.fillRectangle(xi - 1, yi - 1, 3, 3);
        } else if (starSize == STAR_MEDIUM) {
            dc.fillRectangle(xi - 1, yi - 1, 2, 2);
        } else {
            dc.drawPoint(xi, yi);
        }
    }

    function closenessToFullMoon(phaseAngle) {
        return MathUtil.clamp(1.0 - MathUtil.abs(MathUtil.wrap180(phaseAngle - 180.0))/Lunar.FULL_MOON_WINDOW_DEG, 0.0, 1.0);
    }

    function moonGlowNightScale(sunAltDeg) {
        return MathUtil.clamp((-sunAltDeg)/6.0, 0.0, 1.0);
    }
}
