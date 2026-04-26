using Toybox.Graphics;
using Toybox.Math;

module Drawing {

    const BLACK = 0x000000;
    const WHITE = 0xFFFFFF;
    const SILVER = 0xC8CDD3;

    const SUN_GLOW_DEG = 18.0;
    const GLOW_STEPS = 18;
    const NEW_MOON_DIAMETER_DEG = 5.0;

    const CLOCK_RADIUS_FRAC = 0.6179775281;
    const CLOCK_AZ_DEG = 0.0;
    const COLON_GAP_FRAC = 0.0842696629;
    const COLON_V_SHIFT_FRAC = 0.0561797753;

    const TOP_FIELD_RADIUS_FRAC = 0.67;
    const BOTTOM_FIELD_RADIUS_FRAC = 0.5;
    const TOP_FIELD_AZ_DEG = 0.0;
    const SIDE_FIELD_OFFSET_DEG = 27.279612736;
    const BOTTOM_RIGHT_FIELD_AZ_DEG = 180.0 - SIDE_FIELD_OFFSET_DEG;
    const BOTTOM_LEFT_FIELD_AZ_DEG = 180.0 + SIDE_FIELD_OFFSET_DEG;

    const SECOND_TICK_OUTSET_FRAC = 0.0;
    const SECOND_TICK_LENGTH_FRAC = 0.0449438202;
    const SECOND_TICK_HALF_WIDTH_FRAC = 0.0084269663;

    function layout(w, h) {
        var cx = w/2.0;
        var cy = h/2.0;
        var R = ((w < h) ? w : h)/2.0 - 2.0;
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

    function drawSky(dc, cache, sunColor, showSun, showMoon, showStars, mipMode) {
        var cx = cache[0];
        var cy = cache[1];
        var R = cache[2];
        var sunAlt = cache[3];
        var sx = cache[4];
        var sy = cache[5];
        var mx = cache[6];
        var my = cache[7];
        var moonDiameter = cache[8];
        var moonRadius = cache[9];
        var phaseAngle = cache[10];
        var phaseBin = cache[11];

        dc.setColor(BLACK, BLACK);
        dc.clear();
        dc.fillCircle(cx.toNumber(), cy.toNumber(), R.toNumber());

        var glowRadius = R*(SUN_GLOW_DEG/90.0);
        if (showSun && intersectsSkyDisc(sx, sy, glowRadius, cx, cy, R)) {
            if (mipMode) {
                Solar.drawMipSunGlow(dc, sx, sy, R, sunAlt, NEW_MOON_DIAMETER_DEG, SUN_GLOW_DEG);
            } else {
                Solar.drawSunGlow(dc, sx, sy, cx, cy, R, sunColor, SUN_GLOW_DEG, GLOW_STEPS);
            }
        }

        if (showStars && sunAlt < 0.0) {
            Stellar.drawProjectedStars(dc);
        }

        if (showMoon && intersectsSkyDisc(mx, my, moonRadius, cx, cy, R)) {
            Lunar.drawMoonPhaseCached(
                dc,
                mx,
                my,
                moonDiameter,
                sx,
                sy,
                phaseAngle,
                phaseBin,
                sunAlt,
                mipMode ? Lunar.MIP_MOON_BRIGHT : SILVER,
                R,
                mipMode
            );
        }
    }

    function drawFace(dc, cache, hour, min, sec, showSeconds, sunsetAccent, sunColor, topText, leftText, rightText) {
        var cx = cache[0];
        var cy = cache[1];
        var R = cache[2];

        if (showSeconds) {
            drawSecondTicks(dc, cx, cy, R, sec);
        }

        drawTopField(dc, cx, cy, R, topText);
        drawDigitalClock(dc, cx, cy, R, hour, min, sunsetAccent, sunColor, leftText, rightText);
    }

    function drawSecondTickClipped(dc, cache, sec) {
        if (sec <= 0) {
            return;
        }

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

        var font = Graphics.FONT_SYSTEM_TINY;
        var w = dc.getTextWidthInPixels(text, font);
        var h = dc.getFontHeight(font);

        var padX = 2;
        var padY = 1;

        dc.setClip(x - w/2 - padX, y - h/2 - padY, w + 2*padX, h + 2*padY);
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
        var a = azDeg*Math.PI/180.0;
        return [
            cx + rho*Math.sin(a),
            cy - rho*Math.cos(a)
        ];
    }

    function secondTickPolygon(cx, cy, R, i) {
        var rOuter = R*(1.0 - SECOND_TICK_OUTSET_FRAC);
        var rInner = rOuter - R*SECOND_TICK_LENGTH_FRAC;
        var hw = R*SECOND_TICK_HALF_WIDTH_FRAC;
        var a = 2.0*Math.PI*i/60.0;

        var ux = Math.sin(a);
        var uy = -Math.cos(a);
        var px = -uy;
        var py = ux;

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
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(p[0].toNumber(), p[1].toNumber(), Graphics.FONT_SYSTEM_TINY, topText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawDigitalClock(dc, cx, cy, R, hour, min, sunsetAccent, sunColor, leftText, rightText) {
        var font = Graphics.FONT_SYSTEM_NUMBER_THAI_HOT;
        var hText = twoDigits(hour);
        var mText = twoDigits(min);

        var clockCenter = polarPoint(cx, cy, R, CLOCK_RADIUS_FRAC, CLOCK_AZ_DEG);
        var clockCx = clockCenter[0];
        var clockCy = clockCenter[1];

        var ascent = Graphics.getFontAscent(font).toFloat();
        var descent = Graphics.getFontDescent(font).toFloat();
        var baselineY = clockCy + (ascent - descent)/2.0;

        var colonGap = R*COLON_GAP_FRAC;
        var colonShift = R*COLON_V_SHIFT_FRAC;

        dc.setColor(Solar.blendColor(WHITE, 0xFF8000, sunsetAccent), Graphics.COLOR_TRANSPARENT);
        dc.drawText((clockCx - colonGap).toNumber(), baselineY.toNumber(), font, hText, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(clockCx.toNumber(), (baselineY - colonShift).toNumber(), font, ":", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(config.mipMode() ? sunColor : Solar.brightSunColor(sunColor, config.minuteSaturation()), Graphics.COLOR_TRANSPARENT);
        dc.drawText((clockCx + colonGap).toNumber(), baselineY.toNumber(), font, mText, Graphics.TEXT_JUSTIFY_LEFT);

        drawSubfields(dc, cx, cy, R, leftText, rightText);
    }

    function drawSubfields(dc, cx, cy, R, leftText, rightText) {
        var pL = polarPoint(cx, cy, R, BOTTOM_FIELD_RADIUS_FRAC, BOTTOM_LEFT_FIELD_AZ_DEG);
        var pR = polarPoint(cx, cy, R, BOTTOM_FIELD_RADIUS_FRAC, BOTTOM_RIGHT_FIELD_AZ_DEG);

        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pL[0].toNumber(), pL[1].toNumber(), Graphics.FONT_SYSTEM_TINY, leftText, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(pR[0].toNumber(), pR[1].toNumber(), Graphics.FONT_SYSTEM_TINY, rightText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function twoDigits(n) {
        if (n < 10) {
            return "0" + n.toString();
        }
        return n.toString();
    }
}
