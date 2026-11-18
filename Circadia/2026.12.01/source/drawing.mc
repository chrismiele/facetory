using Toybox.Graphics;
using Toybox.Math;

module Drawing {

    const BLACK = 0x000000;
    const WHITE = 0xFFFFFF;

    const STAR_SMALL  = 0;
    const STAR_MEDIUM = 1;
    const STAR_LARGE  = 2;
    const STAR_XL     = 3;

    // Star-colour bin indices, used to index AmoledArt.starColors() and
    // MiPArt.STAR_COLORS, and stored in the star catalogue (from each star's
    // B-V colour index: blue below -0.02, white to 0.30, soft yellow to 0.65,
    // yellow to 1.35, red beyond). Don't renumber without rebuilding
    // resources/jsonData/stars.json.
    const STAR_BIN_YELLOW      = 0;
    const STAR_BIN_SOFT_YELLOW = 1;
    const STAR_BIN_RED         = 2;
    const STAR_BIN_BLUE        = 3;
    const STAR_BIN_WHITE       = 4;

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

    // Data-field slots.
    const FIELD_SLOT_TOP   = 0;
    const FIELD_SLOT_LEFT  = 1;
    const FIELD_SLOT_RIGHT = 2;

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

    // ── Region repaint ───────────────────────────────────────────────────────
    // While a region is active, every draw call is clipped to it. Used by the
    // low-power per-second update on MIP to repaint one field's rectangle with
    // the normal drawing code, so old text is erased and the sky behind it is
    // restored. _region = [x, y, w, h], or null for a normal full-screen draw.
    var _region = null;

    function beginRegion(dc, x, y, w, h) {
        _region = [x, y, w, h];
        dc.setClip(x, y, w, h);
    }

    function endRegion(dc) {
        _region = null;
        dc.clearClip();
    }

    // Padded bounds [x0, y0, x1, y1] of the active region, or null.
    function regionBounds(pad) {
        if (_region == null) { return null; }
        return [_region[0] - pad, _region[1] - pad,
                _region[0] + _region[2] + pad, _region[1] + _region[3] + pad];
    }

    // Black background: the whole screen, or just the active region.
    function clearBackground(dc) {
        dc.setColor(BLACK, BLACK);
        if (_region == null) {
            dc.clear();
        } else {
            dc.fillRectangle(_region[0], _region[1], _region[2], _region[3]);
        }
    }

    // Set a clip for one shape without escaping the active region. Returns
    // false when nothing of the shape is inside the region (skip the draw).
    function setInnerClip(dc, x, y, w, h) {
        if (_region == null) {
            dc.setClip(x, y, w, h);
            return true;
        }
        var x0 = (x > _region[0]) ? x : _region[0];
        var y0 = (y > _region[1]) ? y : _region[1];
        var x1 = (x + w < _region[0] + _region[2]) ? x + w : _region[0] + _region[2];
        var y1 = (y + h < _region[1] + _region[3]) ? y + h : _region[1] + _region[3];
        if (x1 <= x0 || y1 <= y0) { return false; }
        dc.setClip(x0, y0, x1 - x0, y1 - y0);
        return true;
    }

    // Undo setInnerClip: back to the active region, or to no clip at all.
    function restoreClip(dc) {
        if (_region == null) {
            dc.clearClip();
        } else {
            dc.setClip(_region[0], _region[1], _region[2], _region[3]);
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

    // Back to front: stars, sun, moon. Everything is painted opaque, so the
    // sun (spread along the horizon or not) and the moon hide the stars
    // behind them simply by being drawn later; nothing has to test stars
    // against them.
    function drawSky(dc, cache, showSun, showMoon, showStars, mipMode) {
        clearBackground(dc);

        if (showStars) {
            Stellar.drawProjectedStars(dc);
        }

        if (showSun) {
            // cache = [cx, cy, R, sunAlt, sunX, sunY, ...]
            SunArt.draw(dc, cache[0], cache[1], cache[2], cache[4], cache[5], cache[3], mipMode);
        }

        if (showMoon) {
            MoonArt.draw(dc, cache, mipMode);
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

        drawField(dc, cx, cy, R, FIELD_SLOT_TOP, fields[0]);
        drawDigitalClock(dc, cx, cy, R, time, sunsetAccent, sunColor, mipMode);
        drawField(dc, cx, cy, R, FIELD_SLOT_LEFT,  fields[1]);
        drawField(dc, cx, cy, R, FIELD_SLOT_RIGHT, fields[2]);
    }

    // The part of the face that can overlap one field's rectangle, in the same
    // paint order as drawFace. Called inside a region, after drawSky, when a
    // single field's text has changed. Second ticks sit on the rim, outside
    // every field rectangle, so they are not redrawn here.
    function drawFaceInRegion(dc, cache, time, sunsetAccent, sunColor, slot, text, mipMode) {
        var cx = cache[0];
        var cy = cache[1];
        var R  = cache[2];

        if (slot == FIELD_SLOT_TOP) { drawField(dc, cx, cy, R, slot, text); }
        drawDigitalClock(dc, cx, cy, R, time, sunsetAccent, sunColor, mipMode);
        if (slot != FIELD_SLOT_TOP) { drawField(dc, cx, cy, R, slot, text); }
    }

    function drawSecondTickClipped(dc, cache, sec) {
        drawOneSecondTickClipped(dc, cache[0], cache[1], cache[2], sec);
    }

    // Where a field's text is drawn: [x centre, y top].
    function fieldAnchor(cx, cy, R, slot) {
        var p;
        if (slot == FIELD_SLOT_TOP) {
            p = polarPoint(cx, cy, R, TOP_FIELD_RADIUS_FRAC, TOP_FIELD_AZ_DEG);
        } else if (slot == FIELD_SLOT_LEFT) {
            p = polarPoint(cx, cy, R, BOTTOM_FIELD_RADIUS_FRAC, BOTTOM_LEFT_FIELD_AZ_DEG);
        } else {
            p = polarPoint(cx, cy, R, BOTTOM_FIELD_RADIUS_FRAC, BOTTOM_RIGHT_FIELD_AZ_DEG);
        }
        return [p[0].toNumber(), p[1].toNumber()];
    }

    function drawField(dc, cx, cy, R, slot, text) {
        if (text == null) { return; }
        var p = fieldAnchor(cx, cy, R, slot);
        drawFieldText(dc, p[0], p[1], text);
    }

    // Screen rectangle [x, y, w, h] that covers a field's old and new text,
    // including the 1px outline. drawFieldText centres text on x with its top at y.
    function fieldRect(dc, cache, slot, oldText, newText) {
        var p    = fieldAnchor(cache[0], cache[1], cache[2], slot);
        var font = Graphics.FONT_SYSTEM_TINY;
        var w    = 0;
        if (oldText != null) { w = dc.getTextWidthInPixels(oldText, font); }
        if (newText != null) {
            var wNew = dc.getTextWidthInPixels(newText, font);
            if (wNew > w) { w = wNew; }
        }
        var pad = 2;
        return [p[0] - w/2 - pad - 1, p[1] - pad, w + 2*pad + 2, dc.getFontHeight(font) + 2*pad];
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

    // time = [hour, min, ...]
    function drawDigitalClock(dc, cx, cy, R, time, sunsetAccent, sunColor, mipMode) {
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

        var hourColor = mipMode
            ? MiPArt.hourColor(sunsetAccent)
            : MathUtil.blendColor(WHITE, AmoledArt.SUNSET_ACCENT, sunsetAccent);
        dc.setColor(hourColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText((clockCx - colonGap).toNumber(), baselineY.toNumber(), font, hText, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(clockCx.toNumber(), (baselineY - colonShift).toNumber(), font, ":", Graphics.TEXT_JUSTIFY_CENTER);

        var minuteColor = mipMode
            ? MiPArt.minuteColor(sunColor, config.minuteSaturation())
            : AmoledArt.brightSunColor(sunColor, config.minuteSaturation());
        dc.setColor(minuteColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText((clockCx + colonGap).toNumber(), baselineY.toNumber(), font, mText, Graphics.TEXT_JUSTIFY_LEFT);
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

}
