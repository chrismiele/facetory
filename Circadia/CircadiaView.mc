using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.Graphics;
using Toybox.Math;
using Toybox.Position;
using Toybox.SensorHistory;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;
using Toybox.Weather;

class CircadiaView extends WatchUi.WatchFace {

    const BLACK = 0x000000;
    const WHITE = 0xFFFFFF;
    const SILVER = 0xC8CDD3;

    const SHOW_MOON = true;
    const SHOW_SECONDS = false;
    const USE_GPS = true;
    const SHOW_STARS = true;
    const SHOW_FACE = true;

    const SUN_GLOW_DEG = 18.0;
    const GLOW_STEPS = 18;
    const NEW_MOON_DIAMETER_DEG = 5.0;
    const MOON_DIAMETER_DEG = 12.0;

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

    const FIELD_TEMPERATURE = 0;
    const FIELD_BODY_BATTERY = 1;
    const FIELD_HEART_RATE = 2;
    const FIELD_STEPS = 3;

    const LEFT_FIELD_KIND = FIELD_TEMPERATURE;
    const RIGHT_FIELD_KIND = FIELD_BODY_BATTERY;

    const FIELD_CLIP_W = 60;
    const FIELD_CLIP_H = 20;

    var LAT_DEG = 49.28;
    var LON_DEG = 123.12;

    var _sunColor = WHITE;
    var _bodyBatteryText = "--";
    var _isSleeping = false;

    var _cacheYear = -1;
    var _cacheMonth = -1;
    var _cacheDay = -1;
    var _cacheHour = -1;
    var _cacheMin = -1;

    var _cachedClockHourNow = 0.0;
    var _cachedOffsetSec = 0;

    var _cachedMoonDiameterDeg = NEW_MOON_DIAMETER_DEG;
    var _cachedMoonAltAz = [0.0, 0.0];
    var _cachedSunAltAz = [0.0, 0.0];
    var _cachedSunsetAccent = 0.0;

    var _cachedDateText = "--";
    var _cachedWeatherText = "--";

    var _leftFieldText = "--";
    var _rightFieldText = "--";
    var _cachedStepsText = "--";

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc) {}

    function onShow() {
        updateLocationOnce();
    }

    function onHide() {}

    function onExitSleep() {
        _isSleeping = false;
    }

    function onEnterSleep() {
        _isSleeping = true;
    }

    function isSensibleDeg(deg) {
        if (deg == null || deg.size() < 2) {
            return false;
        }

        var lat = deg[0].toFloat();
        var lon = deg[1].toFloat();

        if (lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0) {
            return false;
        }

        if (lat == 180.0 && lon == 180.0) {
            return false;
        }

        return true;
    }

    function updateLocationOnce() {
        if (!USE_GPS) {
            return;
        }

        var cc = Weather.getCurrentConditions();
        if (cc != null) {
            var pos = cc.observationLocationPosition;
            if (pos != null) {
                var deg = pos.toDegrees();
                if (isSensibleDeg(deg)) {
                    LAT_DEG = deg[0].toFloat();
                    LON_DEG = deg[1].toFloat();
                    return;
                }
            }
        }

        var info = Activity.getActivityInfo();
        if (info != null) {
            var pos2 = info.currentLocation;
            if (pos2 != null) {
                var deg2 = pos2.toDegrees();
                if (isSensibleDeg(deg2)) {
                    LAT_DEG = deg2[0].toFloat();
                    LON_DEG = deg2[1].toFloat();
                    return;
                }
            }
        }
    }

    function onUpdate(dc) {
        var w = dc.getWidth().toFloat();
        var h = dc.getHeight().toFloat();
        var cx = w/2.0;
        var cy = h/2.0;
        var R = ((w < h) ? w : h)/2.0 - 2.0;

        var now = Time.now();
        var g = Gregorian.info(now, Time.FORMAT_SHORT);
        var t = System.getClockTime();

        if (g.year != _cacheYear || g.month != _cacheMonth || g.day != _cacheDay ||
            t.hour != _cacheHour || t.min != _cacheMin) {

            updateMinuteCache(now, g, t);

            _cacheYear = g.year;
            _cacheMonth = g.month;
            _cacheDay = g.day;
            _cacheHour = t.hour;
            _cacheMin = t.min;
        }

        refreshLiveBottomFields();

        var sun = _cachedSunAltAz;
        var sp = Solar.projectAltAz(sun[0], sun[1], cx, cy, R);

        var moonDiameter = R*(_cachedMoonDiameterDeg/90.0);
        var mp = [0.0, 0.0];
        var moonRadius = 0.0;

        if (SHOW_MOON) {
            mp = Solar.projectAltAz(_cachedMoonAltAz[0], _cachedMoonAltAz[1], cx, cy, R);
            moonRadius = moonDiameter/2.0 + 1.0;
        }

        dc.setColor(BLACK, BLACK);
        dc.clear();
        dc.fillCircle(cx.toNumber(), cy.toNumber(), R.toNumber());

        var glowRadius = R*(SUN_GLOW_DEG/90.0);
        if (intersectsSkyDisc(sp[0], sp[1], glowRadius, cx, cy, R)) {
            Solar.drawSunGlow(dc, sp[0], sp[1], cx, cy, R, _sunColor, SUN_GLOW_DEG, GLOW_STEPS);
        }

        if (SHOW_STARS && sun[0] < 0.0) {
            Stellar.drawStars(
                dc,
                cx,
                cy,
                R,
                g.year,
                g.month,
                g.day,
                t.hour,
                t.min,
                t.sec,
                LAT_DEG,
                sun[0],
                mp[0],
                mp[1],
                moonRadius
            );
        }

        if (SHOW_MOON && intersectsSkyDisc(mp[0], mp[1], moonRadius, cx, cy, R)) {
            Lunar.drawMoonPhase(
                dc,
                mp[0],
                mp[1],
                moonDiameter,
                sp[0],
                sp[1],
                g.year,
                g.month,
                g.day,
                _cachedClockHourNow,
                _cachedOffsetSec,
                sun[0],
                SILVER,
                R
            );
        }

        if (SHOW_FACE && !_isSleeping) {
            if (SHOW_SECONDS) {
                drawSecondTicks(dc, cx, cy, R, t.sec);
            }

            drawTopDate(dc, cx, cy, R);
            drawDigitalClock(dc, cx, cy, R, t.hour, t.min, _cachedSunsetAccent);
        }
    }

    function onPartialUpdate(dc) {
        if (!SHOW_FACE || _isSleeping) {
            return;
        }

        if (!fieldNeedsFastRefresh(LEFT_FIELD_KIND) && !fieldNeedsFastRefresh(RIGHT_FIELD_KIND)) {
            return;
        }

        refreshLiveBottomFields();

        var w = dc.getWidth().toFloat();
        var h = dc.getHeight().toFloat();
        var cx = w/2.0;
        var cy = h/2.0;
        var R = ((w < h) ? w : h)/2.0 - 2.0;

        if (fieldNeedsFastRefresh(LEFT_FIELD_KIND)) {
            drawOneBottomField(dc, cx, cy, R, BOTTOM_LEFT_FIELD_AZ_DEG, _leftFieldText);
        }

        if (fieldNeedsFastRefresh(RIGHT_FIELD_KIND)) {
            drawOneBottomField(dc, cx, cy, R, BOTTOM_RIGHT_FIELD_AZ_DEG, _rightFieldText);
        }
    }

    function drawOneBottomField(dc, cx, cy, R, azDeg, text) {
        var p = polarPoint(cx, cy, R, BOTTOM_FIELD_RADIUS_FRAC, azDeg);
        var x = p[0].toNumber();
        var y = p[1].toNumber();

        var clipX = x - FIELD_CLIP_W/2;
        var clipY = y - FIELD_CLIP_H/2;

        dc.setClip(clipX, clipY, FIELD_CLIP_W, FIELD_CLIP_H);
        dc.setColor(BLACK, BLACK);
        dc.fillRectangle(clipX, clipY, FIELD_CLIP_W, FIELD_CLIP_H);

        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            x,
            y,
            Graphics.FONT_SYSTEM_TINY,
            text,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        dc.clearClip();
    }

    function updateMinuteCache(now, g, t) {
        _cachedOffsetSec = t.timeZoneOffset;
        _cachedClockHourNow = t.hour + t.min/60.0;

        var moonBin = Lunar.lunarPhaseBin(
            g.year,
            g.month,
            g.day,
            _cachedClockHourNow,
            _cachedOffsetSec
        );

        _cachedMoonDiameterDeg = (moonBin == Lunar.PHASE_NEW) ? NEW_MOON_DIAMETER_DEG : MOON_DIAMETER_DEG;

        _cachedSunAltAz = Solar.solarAltAzApprox(
            g.year,
            g.month,
            g.day,
            _cachedClockHourNow,
            _cachedOffsetSec,
            LAT_DEG,
            LON_DEG
        );

        _cachedSunsetAccent = Solar.sunsetAccentScale(_cachedSunAltAz[0]);
        _sunColor = Solar.sunColorForAlt(_cachedSunAltAz[0]);

        _cachedMoonAltAz = [0.0, 0.0];
        if (SHOW_MOON) {
            _cachedMoonAltAz = Lunar.lunarAltAzApprox(
                g.year,
                g.month,
                g.day,
                _cachedClockHourNow,
                _cachedOffsetSec,
                LAT_DEG,
                LON_DEG
            );
        }

        var gMed = Gregorian.info(now, Time.FORMAT_MEDIUM);
        _cachedDateText = gMed.day_of_week + " " + g.day.toString();
        _cachedWeatherText = getWeatherTempText();
        _bodyBatteryText = getBodyBatteryDisplay();

        _leftFieldText = getBottomFieldText(LEFT_FIELD_KIND);
        _rightFieldText = getBottomFieldText(RIGHT_FIELD_KIND);
    }

    function refreshLiveBottomFields() {
        if (fieldNeedsFastRefresh(LEFT_FIELD_KIND)) {
            _leftFieldText = getBottomFieldText(LEFT_FIELD_KIND);
        }

        if (fieldNeedsFastRefresh(RIGHT_FIELD_KIND)) {
            _rightFieldText = getBottomFieldText(RIGHT_FIELD_KIND);
        }
    }

    function fieldNeedsFastRefresh(kind) {
        return kind == FIELD_HEART_RATE || kind == FIELD_STEPS;
    }

    function getBottomFieldText(kind) {
        if (kind == FIELD_TEMPERATURE) {
            return _cachedWeatherText;
        }

        if (kind == FIELD_BODY_BATTERY) {
            return _bodyBatteryText;
        }

        if (kind == FIELD_STEPS) {
            return getStepsDisplay();
        }

        if (kind == FIELD_HEART_RATE) {
            return getHeartRateDisplay();
        }

        return "--";
    }

    function getHeartRateDisplay() {
        var info = Activity.getActivityInfo();
        if (info == null || info.currentHeartRate == null) {
            return "--";
        }
        return info.currentHeartRate.toNumber().toString();
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

    function drawSecondTicks(dc, cx, cy, R, sec) {
        var rOuter = R*(1.0 - SECOND_TICK_OUTSET_FRAC);
        var rInner = rOuter - R*SECOND_TICK_LENGTH_FRAC;
        var hw = R*SECOND_TICK_HALF_WIDTH_FRAC;

        dc.setColor(WHITE, WHITE);

        for (var i = 0; i < sec; i += 1) {
            var a = 2.0*Math.PI*i/60.0;

            var ux = Math.sin(a);
            var uy = -Math.cos(a);

            var px = -uy;
            var py = ux;

            var x0 = cx + rInner*ux;
            var y0 = cy + rInner*uy;
            var x1 = cx + rOuter*ux;
            var y1 = cy + rOuter*uy;

            var p0 = [ (x0 - hw*px).toNumber(), (y0 - hw*py).toNumber() ];
            var p1 = [ (x0 + hw*px).toNumber(), (y0 + hw*py).toNumber() ];
            var p2 = [ (x1 + hw*px).toNumber(), (y1 + hw*py).toNumber() ];
            var p3 = [ (x1 - hw*px).toNumber(), (y1 - hw*py).toNumber() ];

            dc.fillPolygon([ p0, p1, p2, p3 ]);
        }
    }

    function drawTopDate(dc, cx, cy, R) {
        var p = polarPoint(cx, cy, R, TOP_FIELD_RADIUS_FRAC, TOP_FIELD_AZ_DEG);

        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            p[0].toNumber(),
            p[1].toNumber(),
            Graphics.FONT_SYSTEM_TINY,
            _cachedDateText,
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    function drawDigitalClock(dc, cx, cy, R, hour, min, sunsetAccent) {
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

        dc.setColor(
            Solar.applySaturation(Solar.blendColor(WHITE, 0xFF8000, sunsetAccent)),
            Graphics.COLOR_TRANSPARENT
        );
        dc.drawText(
            (clockCx - colonGap).toNumber(),
            baselineY.toNumber(),
            font,
            hText,
            Graphics.TEXT_JUSTIFY_RIGHT
        );

        dc.drawText(
            clockCx.toNumber(),
            (baselineY - colonShift).toNumber(),
            font,
            ":",
            Graphics.TEXT_JUSTIFY_CENTER
        );

        dc.setColor(Solar.brightSunColor(_sunColor), Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            (clockCx + colonGap).toNumber(),
            baselineY.toNumber(),
            font,
            mText,
            Graphics.TEXT_JUSTIFY_LEFT
        );

        drawSubfields(dc, cx, cy, R);
    }

    function drawSubfields(dc, cx, cy, R) {
        var pL = polarPoint(cx, cy, R, BOTTOM_FIELD_RADIUS_FRAC, BOTTOM_LEFT_FIELD_AZ_DEG);
        var pR = polarPoint(cx, cy, R, BOTTOM_FIELD_RADIUS_FRAC, BOTTOM_RIGHT_FIELD_AZ_DEG);

        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);

        dc.drawText(
            pL[0].toNumber(),
            pL[1].toNumber(),
            Graphics.FONT_SYSTEM_TINY,
            _leftFieldText,
            Graphics.TEXT_JUSTIFY_CENTER
        );

        dc.drawText(
            pR[0].toNumber(),
            pR[1].toNumber(),
            Graphics.FONT_SYSTEM_TINY,
            _rightFieldText,
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    function getWeatherTempText() {
        var cc = Weather.getCurrentConditions();
        if (cc == null || cc.temperature == null) {
            return "--";
        }
        return roundToIntString(cc.temperature.toFloat()) + "\u00B0";
    }

    function getBodyBatteryDisplay() {
        var it = SensorHistory.getBodyBatteryHistory({
            :period => 5,
            :order => SensorHistory.ORDER_NEWEST_FIRST
        });

        if (it == null) {
            return _bodyBatteryText;
        }

        for (var i = 0; i < 5; i += 1) {
            var sample = it.next();
            if (sample == null) {
                break;
            }
            if (sample.data != null) {
                _bodyBatteryText = sample.data.toNumber().toString() + "%";
                break;
            }
        }

        return _bodyBatteryText;
    }

    function getStepsDisplay() {
        var info = ActivityMonitor.getInfo();
        if (info != null && info.steps != null) {
            _cachedStepsText = formatSteps(info.steps.toNumber());
        }
        return _cachedStepsText;
    }

    function formatSteps(steps) {
        if (steps < 1000) {
            return steps.toString();
        }

        if (steps < 100000) {
            return oneDecimalString(steps/1000.0) + "k";
        }

        return Math.floor(steps/1000.0).toNumber().toString() + "k";
    }

    function oneDecimalString(x) {
        var tenth = Math.floor(x*10.0 + 0.5).toNumber();
        var whole = Math.floor(tenth/10.0).toNumber();
        var frac = tenth % 10;
        return whole.toString() + "." + frac.toString();
    }

    function roundToIntString(x) {
        if (x >= 0.0) {
            return (x + 0.5).toNumber().toString();
        }
        return (x - 0.5).toNumber().toString();
    }

    function twoDigits(n) {
        if (n < 10) {
            return "0" + n.toString();
        }
        return n.toString();
    }
}
