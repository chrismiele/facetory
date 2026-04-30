using Toybox.Graphics;
using Toybox.Math;

module Drawing {

    // Local shorthands for the two colours used pervasively. Every other
    // colour comes from Colours.* — see colours.mc for the single source.
    const BLACK = 0x000000;
    const WHITE = 0xFFFFFF;

    const SUN_GLOW_DEG     = 18.0;
    const MOON_GLOW_DEG    = 45.0;
    const GLOW_STEPS       = 18;
    const NEW_MOON_DIAMETER_DEG = 5.0;
    const MOON_DIAMETER_DEG     = 12.0;
    const RING_THICKNESS_DEG    = 6.0;
    const MIP_RING_THICKNESS_DEG  = 3.0;
    const MOON_RING_THICKNESS_DEG = 15.0;
    const SUN_GLOW_CUTOFF_DEG     = 18.0;
    const MAX_MOON_GLOW_BRIGHTNESS         = 0.5;
    const INNER_MOON_GLOW_BRIGHTNESS_SCALE = 0.5;
    const RING_OUTER_EDGE_SCALE = 0.1;
    const RING_INNER_EDGE_SCALE = 0.2;
    const RING_PEAK_SCALE       = 0.4;

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

    const STAR_YELLOW_FRAC      = 0.55;
    const STAR_SOFT_YELLOW_FRAC = 0.20;
    const STAR_RED_FRAC         = 0.12;
    const STAR_BLUE_FRAC        = 0.08;

    // ── Glow bitmap cache ──────────────────────────────────────────────────
    // One unified cache per buffered colour. Slot 0 = YELLOW, Slot 1 = BLUE.
    // (The transitional colours — orange/red/purple — appear briefly during
    // sunrise/sunset and are drawn directly without a cache.)
    const GLOW_SLOT_YELLOW = 0;
    const GLOW_SLOT_BLUE   = 1;

    var _glowBitmap   = [null, null];
    var _glowR        = [-1.0, -1.0];
    var _glowDeg      = [-1.0, -1.0];
    var _glowSteps    = [-1, -1];
    var _glowRadiusPx = [0, 0];

    var _transparent;

    const CLOCK_RADIUS_FRAC  = 0.6179775281;
    const CLOCK_AZ_DEG       = 0.0;
    const COLON_GAP_FRAC     = 0.0842696629;
    const COLON_V_SHIFT_FRAC = 0.0561797753;

    const TOP_FIELD_RADIUS_FRAC    = 0.67;
    const BOTTOM_FIELD_RADIUS_FRAC = 0.5;
    const TOP_FIELD_AZ_DEG         = 0.0;
    const SIDE_FIELD_OFFSET_DEG     = 45.0;
    const BOTTOM_RIGHT_FIELD_AZ_DEG = 180.0 - SIDE_FIELD_OFFSET_DEG;
    const BOTTOM_LEFT_FIELD_AZ_DEG  = 180.0 + SIDE_FIELD_OFFSET_DEG;

    const SECOND_TICK_LENGTH_FRAC     = 0.0449438202;
    const SECOND_TICK_HALF_WIDTH_FRAC = 0.0084269663;

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

    function ensureTransparent() {
        if (_transparent == null) {
            _transparent = Graphics.createColor(0, 0, 0, 0);
        }
    }

    function layout(w, h) {
        var cx = w/2.0;
        var cy = h/2.0;
        var R  = ((w < h) ? w : h)/2.0 - 2.0;
        return [cx, cy, R, w, h];
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

    // Clear the whole screen to black. Used when AOD shows time-only
    // (i.e. sky drawing is suppressed but we still need to wipe stale pixels).
    function clearScreen(dc, cache) {
        var cx = cache[0];
        var cy = cache[1];
        var R  = cache[2];

        dc.setColor(BLACK, BLACK);
        dc.clear();
        dc.fillCircle(cx.toNumber(), cy.toNumber(), R.toNumber());
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
        dc.fillCircle(cx.toNumber(), cy.toNumber(), R.toNumber());

        var glowRadius = R*(SUN_GLOW_DEG/90.0);
        if (showSun && intersectsSkyDisc(sx, sy, glowRadius, cx, cy, R)) {
            if (mipMode) {
                drawMipSun(dc, sx, sy, R, sunAlt);
            } else {
                drawSunGlow(dc, sx, sy, cx, cy, R, sunColor, SUN_GLOW_DEG, GLOW_STEPS);
            }
        }

        if (showStars) {
            Stellar.drawProjectedStars(dc);
        }

        if (showMoon && intersectsSkyDisc(mx, my, moonRadius, cx, cy, R)) {
            drawMoonPhaseCached(
                dc,
                mx, my,
                moonDiameter,
                sx, sy,
                phaseAngle,
                phaseBin,
                sunAlt,
                mipMode ? Colours.MIP_MOON_BRIGHT : Colours.MOON_AMOLED,
                R,
                mipMode
            );
        }
    }

    function drawFace(dc, cache, hour, min, sec, showSeconds, sunsetAccent, sunColor, topText, leftText, rightText) {
        var cx = cache[0];
        var cy = cache[1];
        var R  = cache[2];

        if (showSeconds) {
            drawSecondTicks(dc, cx, cy, R, sec);
        }

        drawTopField(dc, cx, cy, R, topText);
        drawDigitalClock(dc, cx, cy, R, hour, min, sunsetAccent, sunColor, leftText, rightText);
    }

    function drawSecondTickClipped(dc, cache, sec) {
        if (sec <= 0) { return; }
        drawOneSecondTickClipped(dc, cache[0], cache[1], cache[2], sec - 1);
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

        var color = WHITE;
        if (text.length() > 0 && text.substring(0, 1).equals("*")) {
            color = Colours.CHARGING;
            text = text.substring(1, text.length());
        }

        var font = Graphics.FONT_SYSTEM_TINY;
        var w = dc.getTextWidthInPixels(text, font);
        var h = dc.getFontHeight(font);

        var padX = 2;
        var padY = 1;

        dc.setClip(x - w/2 - padX, y - h/2 - padY, w + 2*padX, h + 2*padY);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
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
        dc.setColor(WHITE, WHITE);
        for (var i = 0; i < sec; i += 1) {
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
        dc.setColor(WHITE, WHITE);
        dc.fillPolygon(p);
        dc.clearClip();
    }

    function drawTopField(dc, cx, cy, R, topText) {
        var p = polarPoint(cx, cy, R, TOP_FIELD_RADIUS_FRAC, TOP_FIELD_AZ_DEG);
        drawFieldText(dc, p[0].toNumber(), p[1].toNumber(), topText);
    }

    function drawDigitalClock(dc, cx, cy, R, hour, min, sunsetAccent, sunColor, leftText, rightText) {
        var font  = Graphics.FONT_SYSTEM_NUMBER_THAI_HOT;
        var displayHour = hour;
        if (config.timeFormat() == config.TIME_FORMAT_12H) {
            displayHour = hour % 12;
            if (displayHour == 0) { displayHour = 12; }
        }
        var hText = twoDigits(displayHour);
        var mText = twoDigits(min);

        var clockCenter = polarPoint(cx, cy, R, CLOCK_RADIUS_FRAC, CLOCK_AZ_DEG);
        var clockCx = clockCenter[0];
        var clockCy = clockCenter[1];

        var ascent  = Graphics.getFontAscent(font).toFloat();
        var descent = Graphics.getFontDescent(font).toFloat();
        var baselineY = clockCy + (ascent - descent)/2.0;

        var colonGap   = R*COLON_GAP_FRAC;
        var colonShift = R*COLON_V_SHIFT_FRAC;

        dc.setColor(MathUtil.blendColor(WHITE, Colours.SUNSET_ACCENT, sunsetAccent), Graphics.COLOR_TRANSPARENT);
        dc.drawText((clockCx - colonGap).toNumber(), baselineY.toNumber(), font, hText, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(clockCx.toNumber(), (baselineY - colonShift).toNumber(), font, ":", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Solar.brightSunColor(sunColor, config.minuteSaturation()), Graphics.COLOR_TRANSPARENT);
        dc.drawText((clockCx + colonGap).toNumber(), baselineY.toNumber(), font, mText, Graphics.TEXT_JUSTIFY_LEFT);

        drawSubfields(dc, cx, cy, R, leftText, rightText);
    }

    function drawSubfields(dc, cx, cy, R, leftText, rightText) {
        var pL = polarPoint(cx, cy, R, BOTTOM_FIELD_RADIUS_FRAC, BOTTOM_LEFT_FIELD_AZ_DEG);
        var pR = polarPoint(cx, cy, R, BOTTOM_FIELD_RADIUS_FRAC, BOTTOM_RIGHT_FIELD_AZ_DEG);

        drawFieldText(dc, pL[0].toNumber(), pL[1].toNumber(), leftText);
        drawFieldText(dc, pR[0].toNumber(), pR[1].toNumber(), rightText);
    }

    // Render a field's text. A leading "+" is the "charging" marker — we
    // strip it and colour the remaining text yellow.
    function drawFieldText(dc, x, y, text) {
        var color = WHITE;
        if (text.length() > 0 && text.substring(0, 1).equals("*")) {
            color = Colours.CHARGING;
            text = text.substring(1, text.length());
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_SYSTEM_TINY, text, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Map a sun colour to a glow-cache slot, or -1 if no cache exists for it.
    function glowCacheSlot(sunColor) {
        if (sunColor == Colours.SUN_YELLOW) { return GLOW_SLOT_YELLOW; }
        if (sunColor == Colours.SUN_BLUE)   { return GLOW_SLOT_BLUE; }
        return -1;
    }

    function drawSunGlow(dc, x, y, cx, cy, R, sunColor, glowDeg, glowSteps) {
        if (Toybox.Graphics has :createBufferedBitmap) {
            var slot = glowCacheSlot(sunColor);
            if (slot >= 0) {
                var bmp = getGlowBitmap(slot, sunColor, R, glowDeg, glowSteps);
                if (bmp != null) {
                    dc.drawBitmap(x.toNumber() - _glowRadiusPx[slot], y.toNumber() - _glowRadiusPx[slot], bmp);
                    return;
                }
            }
        }
        drawSunGlowDirect(dc, x, y, cx, cy, R, sunColor, glowDeg, glowSteps);
    }

    function drawSunGlowDirect(dc, x, y, cx, cy, R, sunColor, glowDeg, glowSteps) {
        var glowPx = R*(glowDeg/90.0);
        var thicknessPx = R*(RING_THICKNESS_DEG/90.0);
        var innerPx = glowPx - thicknessPx;
        if (innerPx < 0.0) { innerPx = 0.0; }

        var midPx    = 0.5*(glowPx + innerPx);
        var invSteps = 1.0/glowSteps.toFloat();
        var xi = x.toNumber();
        var yi = y.toNumber();

        var dx = xi - cx.toNumber();
        var dy = yi - cy.toNumber();
        var d = Math.sqrt(dx*dx + dy*dy);

        for (var i = glowSteps; i >= 1; i -= 1) {
            var f  = i.toFloat()*invSteps;
            var ri = (glowPx*f).toNumber();

            if (d - ri >= R) { continue; }

            var brightness;

            if (ri >= midPx) {
                brightness = RING_PEAK_SCALE
                    + (RING_OUTER_EDGE_SCALE - RING_PEAK_SCALE)*(ri - midPx)/(glowPx - midPx);
            } else if (ri >= innerPx) {
                brightness = RING_INNER_EDGE_SCALE
                    + (RING_PEAK_SCALE - RING_INNER_EDGE_SCALE)*(ri - innerPx)/(midPx - innerPx);
            } else if (innerPx > 0.0) {
                brightness = 1.0
                    + (RING_INNER_EDGE_SCALE - 1.0)*ri/innerPx;
            } else {
                brightness = 1.0;
            }

            dc.setColor(Solar.scaleColor(sunColor, brightness), BLACK);
            dc.fillCircle(xi, yi, ri);
        }
    }

    // Unified glow-bitmap getter — replaces the duplicated yellow/blue versions.
    function getGlowBitmap(slot, sunColor, R, glowDeg, glowSteps) {
        if (_glowBitmap[slot] != null
            && _glowR[slot]     == R
            && _glowDeg[slot]   == glowDeg
            && _glowSteps[slot] == glowSteps) {
            return _glowBitmap[slot];
        }

        var glowPx   = R*(glowDeg/90.0);
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

        drawSunGlowDirect(bdc, radiusPx, radiusPx, radiusPx, radiusPx, R, sunColor, glowDeg, glowSteps);

        _glowBitmap[slot]   = bmp;
        _glowR[slot]        = R;
        _glowDeg[slot]      = glowDeg;
        _glowSteps[slot]    = glowSteps;
        _glowRadiusPx[slot] = radiusPx;

        return bmp;
    }

    function drawMipSun(dc, x, y, R, altDeg) {
        // Three concentric rings with evenly-spaced radii at 6°, 12°, 18° of
        // sky-disc angle (core, middle, outer). Painted outermost first so
        // the white/ember core lands on top.
        var colors = Solar.mipSunColorsForAlt(altDeg);

        var outerR  = R * (18.0 / 90.0);
        var middleR = R * (12.0 / 90.0);
        var coreR   = R * ( 6.0 / 90.0);

        var xi = x.toNumber();
        var yi = y.toNumber();

        dc.setColor(colors[0], BLACK);
        dc.fillCircle(xi, yi, MathUtil.roundNearest(outerR));

        dc.setColor(colors[1], BLACK);
        dc.fillCircle(xi, yi, MathUtil.roundNearest(middleR));

        dc.setColor(colors[2], BLACK);
        dc.fillCircle(xi, yi, MathUtil.roundNearest(coreR));
    }

    function drawNewMoon(dc, xi, yi, ri, mipMode) {
        dc.setColor(BLACK, BLACK);
        dc.fillCircle(xi, yi, ri);
    }

    function drawFullMoon(dc, xi, yi, moonRadiusPx, phaseAngle, sunAltDeg, litColor, skyRadiusPx, mipMode) {
        if (mipMode) {
            var scale = moonGlowNightScale(sunAltDeg)*closenessToFullMoon(phaseAngle);
            drawMipHaloBodyScaled(dc, xi, yi, skyRadiusPx, moonRadiusPx, MOON_GLOW_DEG, scale, Colours.WHITE, Colours.MIP_MOON_DARK, Colours.MIP_MOON_MEDIUM);
            return;
        }

        drawMoonGlow(dc, xi, yi, moonRadiusPx, phaseAngle, sunAltDeg, litColor, skyRadiusPx);
        dc.setColor(litColor, BLACK);
        dc.fillCircle(xi, yi, MathUtil.roundNearest(moonRadiusPx));
    }


    function drawMoonPhaseCached(dc, x, y, diameterPx, sunX, sunY, phaseAngle, bin, sunAltDeg, litColor, skyRadiusPx, mipMode) {
        var r  = diameterPx/2.0;
        var xi = MathUtil.roundNearest(x);
        var yi = MathUtil.roundNearest(y);
        var ri = MathUtil.roundNearest(r);

        if (mipMode) {
            litColor = (bin == Lunar.PHASE_FULL) ? Colours.WHITE : Colours.MIP_MOON_BRIGHT;
        }

        if (bin == Lunar.PHASE_NEW) {
            Lunar.resetOrientationBins();
            drawNewMoon(dc, xi, yi, ri, mipMode);
            return;
        }

        if (bin == Lunar.PHASE_FULL) {
            Lunar.resetOrientationBins();
            drawFullMoon(dc, xi, yi, r, phaseAngle, sunAltDeg, litColor, skyRadiusPx, mipMode);
            return;
        }

        var angle = Lunar.moonOrientationAngle(x, y, sunX, sunY);

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
            var shiftDeg    = Lunar.CRESCENT_SHIFT_DEG_THICK;
            var blackFrac   = Lunar.CRESCENT_BLACK_FRAC_THICK;

            if (bin == Lunar.PHASE_WAXING_THIN_CRESCENT || bin == Lunar.PHASE_WANING_THIN_CRESCENT) {
                shiftDeg  = Lunar.CRESCENT_SHIFT_DEG_THIN;
                blackFrac = Lunar.CRESCENT_BLACK_FRAC_THIN;
            }

            drawShiftedBlackCircle(
                dc,
                xi,
                yi,
                skyRadiusPx,
                r,
                crescentDir[0],
                crescentDir[1],
                shiftDeg,
                blackFrac*r
            );
            return;
        }
    }

    function drawMipHaloBodyScaled(dc, x, y, R, bodyR, glowDeg, scale, brightColor, innerColor, outerColor) {
        var xi = x.toNumber();
        var yi = y.toNumber();
        var bodyRi = MathUtil.roundNearest(bodyR);

        if (scale <= 0.0) {
            dc.setColor(brightColor, BLACK);
            dc.fillCircle(xi, yi, bodyRi);
            return;
        }

        var glowR  = R*(glowDeg/90.0)*scale;
        var innerR = glowR - R*(MIP_RING_THICKNESS_DEG/90.0);

        if (innerR < bodyR) { innerR = bodyR; }

        dc.setColor(outerColor, BLACK);
        dc.fillCircle(xi, yi, MathUtil.roundNearest(glowR));

        dc.setColor(innerColor, BLACK);
        dc.fillCircle(xi, yi, MathUtil.roundNearest(innerR));

        dc.setColor(brightColor, BLACK);
        dc.fillCircle(xi, yi, bodyRi);
    }

    function drawMoonGlow(dc, xi, yi, moonRadiusPx, phaseAngle, sunAltDeg, litColor, skyRadiusPx) {
        var fullMoonScale = closenessToFullMoon(phaseAngle);
        if (fullMoonScale <= 0.0) { return; }

        var nightScale = moonGlowNightScale(sunAltDeg);
        if (nightScale <= 0.0) { return; }

        var outerR = skyRadiusPx*(MOON_GLOW_DEG/90.0)*fullMoonScale;
        if (outerR <= 0.5) { return; }

        var glowBrightness = MAX_MOON_GLOW_BRIGHTNESS*nightScale*fullMoonScale;
        var glowSteps = MathUtil.roundNearest(1.0*MOON_GLOW_DEG*fullMoonScale);
        if (glowSteps < 1) { glowSteps = 1; }

        drawOffsetMoonGlowCircle(dc, xi, yi, moonRadiusPx, outerR, litColor, glowBrightness, glowSteps);
    }

    function drawOffsetMoonGlowCircle(dc, xg, yg, moonRadiusPx, outerR, litColor, brightnessScale, glowSteps) {
        var thicknessR = outerR*(MOON_RING_THICKNESS_DEG/MOON_GLOW_DEG);
        var innerR = outerR - thicknessR;
        if (innerR < 0.0) { innerR = 0.0; }

        var midR = 0.5*(outerR + innerR);
        var outerEdgeBrightness = 0.1*brightnessScale;
        var innerEdgeBrightness = INNER_MOON_GLOW_BRIGHTNESS_SCALE*brightnessScale;

        for (var i = glowSteps; i >= 1; i -= 1) {
            var f  = i.toFloat()/glowSteps.toFloat();
            var rr = outerR*f;
            var brightness;

            if (rr >= midR) {
                brightness = brightnessScale
                    + (outerEdgeBrightness - brightnessScale)*(rr - midR)/(outerR - midR);
            } else if (rr >= innerR) {
                brightness = innerEdgeBrightness
                    + (brightnessScale - innerEdgeBrightness)*(rr - innerR)/(midR - innerR);
            } else if (rr >= moonRadiusPx && innerR > moonRadiusPx) {
                brightness = brightnessScale
                    + (innerEdgeBrightness - brightnessScale)*(rr - moonRadiusPx)/(innerR - moonRadiusPx);
            } else {
                continue;
            }

            var c = MathUtil.blendColor(BLACK, litColor, brightness);

            dc.setColor(c, BLACK);
            dc.fillCircle(MathUtil.roundNearest(xg), MathUtil.roundNearest(yg), MathUtil.roundNearest(rr));
        }
    }


    function drawShiftedBlackCircle(dc, xi, yi, skyRadiusPx, moonRadiusPx, ux, uy, shiftDeg, rb) {
        var shift = skyRadiusPx*(shiftDeg/90.0);
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
        var t = -2.2*r;     // back distance
        var s =  2.2*r;     // half-width

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
            MathUtil.blendColor(BLACK, Colours.STAR_YELLOW,      starScale),
            MathUtil.blendColor(BLACK, Colours.STAR_SOFT_YELLOW, starScale),
            MathUtil.blendColor(BLACK, Colours.STAR_RED,         starScale),
            MathUtil.blendColor(BLACK, Colours.STAR_BLUE,        starScale),
            MathUtil.blendColor(BLACK, Colours.STAR_WHITE,       starScale)
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
        return MathUtil.clamp((-sunAltDeg)/SUN_GLOW_CUTOFF_DEG, 0.0, 1.0);
    }

    function twoDigits(n) {
        if (n < 10) { return "0" + n.toString(); }
        return n.toString();
    }
}
