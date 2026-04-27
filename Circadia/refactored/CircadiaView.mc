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

    var _latDeg;
    var _lonDeg;

    var _sunColor = Drawing.WHITE;
    var _bodyBatteryText = "--";
    var _isSleeping = false;

    // Minute-level cache keys
    var _cacheYear  = -1;
    var _cacheMonth = -1;
    var _cacheDay   = -1;
    var _cacheHour  = -1;
    var _cacheMin   = -1;
    var _cacheMipMode = false;

    // Pre-computed per-minute values
    var _cachedClockHourNow  = 0.0;
    var _cachedOffsetSec     = 0;
    var _cachedMoonDiameterDeg  = Drawing.NEW_MOON_DIAMETER_DEG;
    var _cachedMoonPhaseAngle   = 0.0;
    var _cachedMoonPhaseBin     = Lunar.PHASE_NEW;
    var _cachedMoonAltAz    = [0.0, 0.0];
    var _cachedSunAltAz     = [0.0, 0.0];
    var _cachedSunsetAccent = 0.0;

    // Layout cache (invalidated on screen-size change only)
    var _cachedLayoutW = -1.0;
    var _cachedLayoutH = -1.0;
    var _layoutCache   = [0.0, 0.0, 0.0];
    var _skyCache      = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Lunar.PHASE_NEW];

    // Text caches
    var _cachedDateText    = "--";
    var _cachedWeatherText = "--";
    var _topFieldText      = "--";
    var _leftFieldText     = "--";
    var _rightFieldText    = "--";
    var _cachedStepsText   = "--";

    function initialize() {
        WatchFace.initialize();
        _latDeg = config.latDeg();
        _lonDeg = config.lonDeg();
    }

    function onLayout(dc) {}
    function onHide() {}

    function onShow() {
        updateLocation();
    }

    function onExitSleep() { _isSleeping = false; }
    function onEnterSleep() { _isSleeping = true; }

    function updateLocation() {
        var loc = LocationService.getBest();
        _latDeg = loc[0];
        _lonDeg = loc[1];
    }

    function onUpdate(dc) {
        updateLayoutCache(dc);

        var now = Time.now();
        var g = Gregorian.info(now, Time.FORMAT_SHORT);
        var t = System.getClockTime();

        // Read config flags once — avoids repeated function calls below
        var showMoon    = config.showMoon();
        var showStars   = config.showStars();
        var showSun     = config.showSun();
        var showFace    = config.showFace();
        var showSeconds = config.showSeconds();
        var mipMode     = config.mipMode() || (_isSleeping && config.sleepMipMode());

        if (g.year != _cacheYear || g.month != _cacheMonth || g.day != _cacheDay ||
            t.hour != _cacheHour || t.min != _cacheMin || mipMode != _cacheMipMode) {

            updateMinuteCache(now, g, t, mipMode);

            _cacheYear    = g.year;
            _cacheMonth   = g.month;
            _cacheDay     = g.day;
            _cacheHour    = t.hour;
            _cacheMin     = t.min;
            _cacheMipMode = mipMode;
        }

        refreshLiveFields();
        updateSkyCache(g, t);

        Drawing.drawSky(dc, _skyCache, _sunColor, showSun, showMoon, showStars, mipMode);

        if (showFace && !_isSleeping) {
            Drawing.drawFace(
                dc, _layoutCache,
                t.hour, t.min, t.sec,
                showSeconds, _cachedSunsetAccent, _sunColor,
                _topFieldText, _leftFieldText, _rightFieldText
            );
        }
    }

    function onPartialUpdate(dc) {
        if (!config.showFace() || _isSleeping) {
            return;
        }

        // Read field config once
        var topField    = config.topField();
        var leftField   = config.leftField();
        var rightField  = config.rightField();
        var showSeconds = config.showSeconds();

        var topFast   = fieldNeedsFastRefresh(topField);
        var leftFast  = fieldNeedsFastRefresh(leftField);
        var rightFast = fieldNeedsFastRefresh(rightField);

        if (!topFast && !leftFast && !rightFast && !showSeconds) {
            return;
        }

        updateLayoutCache(dc);
        refreshLiveFields();

        if (showSeconds) {
            Drawing.drawSecondTickClipped(dc, _layoutCache, System.getClockTime().sec);
        }
        if (topFast)   { Drawing.drawTopFieldClipped(dc, _layoutCache, _topFieldText); }
        if (leftFast)  { Drawing.drawLeftFieldClipped(dc, _layoutCache, _leftFieldText); }
        if (rightFast) { Drawing.drawRightFieldClipped(dc, _layoutCache, _rightFieldText); }
    }

    // ── Layout ──────────────────────────────────────────────────────────────

    function updateLayoutCache(dc) {
        var w = dc.getWidth().toFloat();
        var h = dc.getHeight().toFloat();
        if (w != _cachedLayoutW || h != _cachedLayoutH) {
            _layoutCache   = Drawing.layout(w, h);
            _cachedLayoutW = w;
            _cachedLayoutH = h;
        }
    }

    // ── Minute-level cache ───────────────────────────────────────────────────

    function updateMinuteCache(now, g, t, mipMode) {
        _cachedOffsetSec    = t.timeZoneOffset;
        _cachedClockHourNow = t.hour + t.min / 60.0;

        _cachedMoonPhaseAngle = Lunar.lunarPhaseAngle(
            g.year, g.month, g.day, _cachedClockHourNow, _cachedOffsetSec
        );
        _cachedMoonPhaseBin = Lunar.lunarPhaseBinFromAngle(_cachedMoonPhaseAngle);
        _cachedMoonDiameterDeg = (_cachedMoonPhaseBin == Lunar.PHASE_NEW)
            ? Drawing.NEW_MOON_DIAMETER_DEG
            : Drawing.MOON_DIAMETER_DEG;

        _cachedSunAltAz = Solar.solarAltAzApprox(
            g.year, g.month, g.day, _cachedClockHourNow, _cachedOffsetSec,
            _latDeg, _lonDeg
        );
        _cachedSunsetAccent = Solar.sunsetAccentScale(_cachedSunAltAz[0]);
        _sunColor = mipMode
            ? Solar.mipBrightSunColorForAlt(_cachedSunAltAz[0])
            : Solar.sunColorForAlt(_cachedSunAltAz[0]);

        _cachedMoonAltAz = [0.0, 0.0];
        if (config.showMoon()) {
            _cachedMoonAltAz = Lunar.lunarAltAzApprox(
                g.year, g.month, g.day, _cachedClockHourNow, _cachedOffsetSec,
                _latDeg, _lonDeg
            );
        }

        // Date text — FORMAT_MEDIUM only needed for day_of_week
        var gMed = Gregorian.info(now, Time.FORMAT_MEDIUM);
        _cachedDateText = gMed.day_of_week + " " + g.day.toString();

        // Only fetch data for fields that are actually displayed
        if (fieldIsVisible(config.FIELD_TEMPERATURE)) {
            _cachedWeatherText = getWeatherTempText();
        }
        if (fieldIsVisible(config.FIELD_BODY_BATTERY)) {
            _bodyBatteryText = getBodyBatteryDisplay();
        }

        _topFieldText   = getFieldText(config.topField());
        _leftFieldText  = getFieldText(config.leftField());
        _rightFieldText = getFieldText(config.rightField());
    }

    function updateSkyCache(g, t) {
        var cx = _layoutCache[0];
        var cy = _layoutCache[1];
        var R  = _layoutCache[2];

        var sp = Drawing.projectBody(_cachedSunAltAz, cx, cy, R);
        var mp = [0.0, 0.0];
        var moonDiameter = Drawing.moonDiameterPx(_cachedMoonDiameterDeg, R);
        var moonRadius   = 0.0;

        if (config.showMoon()) {
            mp         = Drawing.projectBody(_cachedMoonAltAz, cx, cy, R);
            moonRadius = Drawing.moonRadiusPx(_cachedMoonDiameterDeg, R);
        }

        _skyCache = [
            cx, cy, R,
            _cachedSunAltAz[0],
            sp[0], sp[1],
            mp[0], mp[1],
            moonDiameter, moonRadius,
            _cachedMoonPhaseAngle, _cachedMoonPhaseBin
        ];

        if (config.showStars()) {
            Stellar.updateProjectedStars(
                cx, cy, R,
                g.year, g.month, g.day, t.hour, t.min,
                _latDeg, _cachedSunAltAz[0],
                sp[0], sp[1], mp[0], mp[1],
                moonRadius, config.starCount()
            );
        }
    }

    // ── Field helpers ────────────────────────────────────────────────────────

    function fieldIsVisible(kind) {
        return config.topField() == kind
            || config.leftField() == kind
            || config.rightField() == kind;
    }

    function fieldNeedsFastRefresh(kind) {
        return kind == config.FIELD_HEART_RATE || kind == config.FIELD_STEPS;
    }

    // Only refreshes fields that change faster than once per minute
    function refreshLiveFields() {
        var topField   = config.topField();
        var leftField  = config.leftField();
        var rightField = config.rightField();

        if (fieldNeedsFastRefresh(topField))   { _topFieldText   = getFieldText(topField); }
        if (fieldNeedsFastRefresh(leftField))  { _leftFieldText  = getFieldText(leftField); }
        if (fieldNeedsFastRefresh(rightField)) { _rightFieldText = getFieldText(rightField); }
    }

    function getFieldText(kind) {
        if (kind == config.FIELD_DATE)         { return _cachedDateText; }
        if (kind == config.FIELD_TEMPERATURE)  { return _cachedWeatherText; }
        if (kind == config.FIELD_BODY_BATTERY) { return _bodyBatteryText; }
        if (kind == config.FIELD_STEPS)        { return getStepsDisplay(); }
        if (kind == config.FIELD_HEART_RATE)   { return getHeartRateDisplay(); }
        return "--";
    }

    // ── Data fetchers ────────────────────────────────────────────────────────

    function getHeartRateDisplay() {
        var info = Activity.getActivityInfo();
        if (info == null || info.currentHeartRate == null) { return "--"; }
        return info.currentHeartRate.toNumber().toString();
    }

    function getWeatherTempText() {
        var cc = Weather.getCurrentConditions();
        if (cc == null || cc.temperature == null) { return "--"; }

        var temp  = cc.temperature.toFloat();
        var units = config.tempUnits();

        if (units == config.UNIT_IMPERIAL) {
            return roundToIntString(temp * 9.0 / 5.0 + 32.0) + "\u00B0F";
        }
        if (units == config.UNIT_METRIC) {
            return roundToIntString(temp) + "\u00B0C";
        }
        return roundToIntString(temp) + "\u00B0";
    }

    function getBodyBatteryDisplay() {
        var it = SensorHistory.getBodyBatteryHistory({
            :period => 5,
            :order  => SensorHistory.ORDER_NEWEST_FIRST
        });
        if (it == null) { return _bodyBatteryText; }

        for (var i = 0; i < 5; i += 1) {
            var sample = it.next();
            if (sample == null) { break; }
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
            _cachedStepsText = oneDecimalString(info.steps.toNumber() / 1000.0) + "k";
        }
        return _cachedStepsText;
    }

    // ── Formatting helpers ───────────────────────────────────────────────────

    function oneDecimalString(x) {
        var tenth = Math.floor(x * 10.0 + 0.5).toNumber();
        var whole = Math.floor(tenth / 10.0).toNumber();
        return whole.toString() + "." + (tenth % 10).toString();
    }

    function roundToIntString(x) {
        return (x >= 0.0)
            ? (x + 0.5).toNumber().toString()
            : (x - 0.5).toNumber().toString();
    }

}
