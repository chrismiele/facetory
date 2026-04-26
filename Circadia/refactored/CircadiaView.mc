using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.Math;
using Toybox.SensorHistory;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;
using Toybox.Weather;

class CircadiaView extends WatchUi.WatchFace {

    const WHITE = 0xFFFFFF;
    const NEW_MOON_DIAMETER_DEG = 5.0;
    const MOON_DIAMETER_DEG = 12.0;

    var LAT_DEG = 52.09;
    var LON_DEG = 5.12;

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
    var _cachedMoonPhaseAngle = 0.0;
    var _cachedMoonPhaseBin = Lunar.PHASE_NEW;
    var _cachedMoonAltAz = [0.0, 0.0];
    var _cachedSunAltAz = [0.0, 0.0];
    var _cachedSunsetAccent = 0.0;

    var _cachedLayoutW = -1.0;
    var _cachedLayoutH = -1.0;
    var _layoutCache = [0.0, 0.0, 0.0];
    var _skyCache = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Lunar.PHASE_NEW];

    var _cachedDateText = "--";
    var _cachedWeatherText = "--";

    var _topFieldText = "--";
    var _leftFieldText = "--";
    var _rightFieldText = "--";
    var _cachedStepsText = "--";

    function initialize() {
        WatchFace.initialize();
        LAT_DEG = config.latDeg();
        LON_DEG = config.lonDeg();
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
        LAT_DEG = config.latDeg();
        LON_DEG = config.lonDeg();

        if (!config.useGps()) {
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
        updateLayoutCache(dc);

        var now = Time.now();
        var g = Gregorian.info(now, Time.FORMAT_SHORT);
        var t = System.getClockTime();

        var showMoon = config.showMoon();
        var showStars = config.showStars();
        var showSun = config.showSun();
        var showFace = config.showFace();
        var showSeconds = config.showSeconds();
        var mipMode = config.mipMode() || (_isSleeping && config.sleepMipMode());

        if (g.year != _cacheYear || g.month != _cacheMonth || g.day != _cacheDay ||
            t.hour != _cacheHour || t.min != _cacheMin) {

            updateMinuteCache(now, g, t);

            _cacheYear = g.year;
            _cacheMonth = g.month;
            _cacheDay = g.day;
            _cacheHour = t.hour;
            _cacheMin = t.min;
        }

        refreshLiveFields();
        updateSkyCache(g, t);

        Drawing.drawSky(
            dc,
            _skyCache,
            _sunColor,
            showSun,
            showMoon,
            showStars,
            mipMode
        );

        if (showFace && !_isSleeping) {
            Drawing.drawFace(
                dc,
                _layoutCache,
                t.hour,
                t.min,
                t.sec,
                showSeconds,
                _cachedSunsetAccent,
                _sunColor,
                _topFieldText,
                _leftFieldText,
                _rightFieldText
            );
        }
    }

    function onPartialUpdate(dc) {
        if (!config.showFace() || _isSleeping) {
            return;
        }

        updateLayoutCache(dc);

        var topField = config.topField();
        var leftField = config.leftField();
        var rightField = config.rightField();

        var topFast = fieldNeedsFastRefresh(topField);
        var leftFast = fieldNeedsFastRefresh(leftField);
        var rightFast = fieldNeedsFastRefresh(rightField);
        var showSeconds = config.showSeconds();

        if (!topFast && !leftFast && !rightFast && !showSeconds) {
            return;
        }

        refreshLiveFields();

        if (showSeconds) {
            Drawing.drawSecondTickClipped(dc, _layoutCache, System.getClockTime().sec);
        }

        if (topFast) {
            Drawing.drawTopFieldClipped(dc, _layoutCache, _topFieldText);
        }

        if (leftFast) {
            Drawing.drawLeftFieldClipped(dc, _layoutCache, _leftFieldText);
        }

        if (rightFast) {
            Drawing.drawRightFieldClipped(dc, _layoutCache, _rightFieldText);
        }
    }

    function updateLayoutCache(dc) {
        var w = dc.getWidth().toFloat();
        var h = dc.getHeight().toFloat();

        if (w != _cachedLayoutW || h != _cachedLayoutH) {
            _layoutCache = Drawing.layout(w, h);
            _cachedLayoutW = w;
            _cachedLayoutH = h;
        }
    }

    function updateMinuteCache(now, g, t) {
        _cachedOffsetSec = t.timeZoneOffset;
        _cachedClockHourNow = t.hour + t.min/60.0;

        _cachedMoonPhaseAngle = Lunar.lunarPhaseAngle(
            g.year,
            g.month,
            g.day,
            _cachedClockHourNow,
            _cachedOffsetSec
        );
        _cachedMoonPhaseBin = Lunar.lunarPhaseBinFromAngle(_cachedMoonPhaseAngle);

        _cachedMoonDiameterDeg = (_cachedMoonPhaseBin == Lunar.PHASE_NEW) ? NEW_MOON_DIAMETER_DEG : MOON_DIAMETER_DEG;

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
        _sunColor = config.mipMode() ? Solar.mipBrightSunColorForAlt(_cachedSunAltAz[0]) : Solar.sunColorForAlt(_cachedSunAltAz[0]);

        _cachedMoonAltAz = [0.0, 0.0];
        if (config.showMoon()) {
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

        _topFieldText = getFieldText(config.topField());
        _leftFieldText = getFieldText(config.leftField());
        _rightFieldText = getFieldText(config.rightField());
    }

    function updateSkyCache(g, t) {
        var cx = _layoutCache[0];
        var cy = _layoutCache[1];
        var R = _layoutCache[2];

        var sp = Drawing.projectBody(_cachedSunAltAz, cx, cy, R);
        var mp = [0.0, 0.0];
        var moonDiameter = Drawing.moonDiameterPx(_cachedMoonDiameterDeg, R);
        var moonRadius = 0.0;

        if (config.showMoon()) {
            mp = Drawing.projectBody(_cachedMoonAltAz, cx, cy, R);
            moonRadius = Drawing.moonRadiusPx(_cachedMoonDiameterDeg, R);
        }

        _skyCache = [
            cx,
            cy,
            R,
            _cachedSunAltAz[0],
            sp[0],
            sp[1],
            mp[0],
            mp[1],
            moonDiameter,
            moonRadius,
            _cachedMoonPhaseAngle,
            _cachedMoonPhaseBin
        ];

        if (config.showStars() && _cachedSunAltAz[0] < 0.0) {
            Stellar.updateProjectedStars(
                cx,
                cy,
                R,
                g.year,
                g.month,
                g.day,
                t.hour,
                t.min,
                LAT_DEG,
                _cachedSunAltAz[0],
                sp[0],
                sp[1],
                mp[0],
                mp[1],
                moonRadius,
                config.starCount()
            );
        }
    }

    function refreshLiveFields() {
        var topField = config.topField();
        var leftField = config.leftField();
        var rightField = config.rightField();

        if (fieldNeedsFastRefresh(topField)) {
            _topFieldText = getFieldText(topField);
        }

        if (fieldNeedsFastRefresh(leftField)) {
            _leftFieldText = getFieldText(leftField);
        }

        if (fieldNeedsFastRefresh(rightField)) {
            _rightFieldText = getFieldText(rightField);
        }
    }

    function fieldNeedsFastRefresh(kind) {
        return kind == config.FIELD_HEART_RATE || kind == config.FIELD_STEPS;
    }

    function getFieldText(kind) {
        if (kind == config.FIELD_DATE) {
            return _cachedDateText;
        }

        if (kind == config.FIELD_TEMPERATURE) {
            return _cachedWeatherText;
        }

        if (kind == config.FIELD_BODY_BATTERY) {
            return _bodyBatteryText;
        }

        if (kind == config.FIELD_STEPS) {
            return getStepsDisplay();
        }

        if (kind == config.FIELD_HEART_RATE) {
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

    function getWeatherTempText() {
        var cc = Weather.getCurrentConditions();
        if (cc == null || cc.temperature == null) {
            return "--";
        }

        var temp = cc.temperature.toFloat();
        var units = config.tempUnits();

        if (units == config.UNIT_IMPERIAL) {
            temp = temp*9.0/5.0 + 32.0;
            return roundToIntString(temp) + "\u00B0F";
        }

        if (units == config.UNIT_METRIC) {
            return roundToIntString(temp) + "\u00B0C";
        }

        return roundToIntString(temp) + "\u00B0";
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
            _cachedStepsText = oneDecimalString(info.steps.toNumber()/1000.0) + "k";
        }
        return _cachedStepsText;
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

}