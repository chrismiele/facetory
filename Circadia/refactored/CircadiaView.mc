using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.Math;
using Toybox.Position;
using Toybox.SensorHistory;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;
using Toybox.Weather;

// "No data" placeholder shown in any field whose value cannot be retrieved.
const NO_DATA = "\u221E";   // ∞

class CircadiaView extends WatchUi.WatchFace {

    var _latDeg;
    var _lonDeg;

    var _sunColor = Colours.WHITE;
    var _bodyBatteryText = NO_DATA;
    var _stressText      = NO_DATA;
    var _batteryPctText  = NO_DATA;   // "87%" — refreshed once per minute
    var _nextSunEventText = NO_DATA;
    var _nextSunEventAt   = null;    // Time.Moment when the cached event occurs
    var _isSleeping = false;

    // Minute-level cache keys
    var _cacheYear  = -1;
    var _cacheMonth = -1;
    var _cacheDay   = -1;
    var _cacheHour  = -1;
    var _cacheMin   = -1;
    var _cacheMipMode = false;

    // Pre-computed per-minute values
    var _cachedMoonDiameterDeg = Drawing.NEW_MOON_DIAMETER_DEG;
    var _cachedMoonPhaseAngle  = 0.0;
    var _cachedMoonPhaseBin    = Lunar.PHASE_NEW;
    var _cachedMoonAltAz       = [0.0, 0.0];
    var _cachedSunAltAz        = [0.0, 0.0];
    var _cachedSunsetAccent    = 0.0;

    // Layout cache (invalidated on screen-size change only)
    var _cachedLayoutW = -1.0;
    var _cachedLayoutH = -1.0;
    var _layoutCache   = [0.0, 0.0, 0.0];
    var _skyCache      = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Lunar.PHASE_NEW];

    // Text caches
    var _cachedDateText    = NO_DATA;
    var _cachedWeatherText = NO_DATA;
    var _topFieldText      = NO_DATA;
    var _leftFieldText     = NO_DATA;
    var _rightFieldText    = NO_DATA;
    var _cachedStepsText    = NO_DATA;
    var _cachedCaloriesText = NO_DATA;
    var _cachedFloorsText   = NO_DATA;
    var _cachedDistanceText = NO_DATA;
    var _cachedRecoveryText = NO_DATA;

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

    function onExitSleep()  { _isSleeping = false; }
    function onEnterSleep() { _isSleeping = true; }

    // Called by CircadiaApp.onSettingsChanged after config.refresh().
    // We invalidate the minute cache so all derived values re-compute on
    // the next onUpdate. Also drop the next-sun-event cache, since the
    // user may have just changed home coordinates.
    function onSettingsChanged() {
        _cacheMin = -1;
        _nextSunEventAt = null;
        updateLocation();
    }

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

        var showSky  = config.showSky(_isSleeping);
        var showFace = config.showFace(_isSleeping);
        var mipMode  = config.mipMode();

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

        if (showSky) {
            updateSkyCache(g, t);
            Drawing.drawSky(
                dc, _skyCache, _sunColor,
                config.showSun(), config.showMoon(), config.showStars(),
                mipMode
            );
        } else {
            Drawing.clearScreen(dc, _layoutCache);
        }

        if (showFace) {
            Drawing.drawFace(
                dc, _layoutCache,
                t.hour, t.min, t.sec,
                config.showSeconds(), _cachedSunsetAccent, _sunColor,
                _topFieldText, _leftFieldText, _rightFieldText
            );
        }
    }

    function onPartialUpdate(dc) {
        if (!config.showFace(_isSleeping)) { return; }

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
        var clockHour = t.hour + t.min / 60.0;
        var offsetSec = t.timeZoneOffset;

        _cachedMoonPhaseAngle = Lunar.lunarPhaseAngle(
            g.year, g.month, g.day, clockHour, offsetSec
        );
        _cachedMoonPhaseBin = Lunar.lunarPhaseBinFromAngle(_cachedMoonPhaseAngle);
        _cachedMoonDiameterDeg = (_cachedMoonPhaseBin == Lunar.PHASE_NEW)
            ? Drawing.NEW_MOON_DIAMETER_DEG
            : Drawing.MOON_DIAMETER_DEG;

        _cachedSunAltAz = Solar.solarAltAzApprox(
            g.year, g.month, g.day, clockHour, offsetSec,
            _latDeg, _lonDeg
        );
        _cachedSunsetAccent = Solar.sunsetAccentScale(_cachedSunAltAz[0]);
        _sunColor = mipMode
            ? Solar.mipBrightSunColorForAlt(_cachedSunAltAz[0])
            : Solar.sunColorForAlt(_cachedSunAltAz[0]);

        _cachedMoonAltAz = [0.0, 0.0];
        if (config.showMoon()) {
            _cachedMoonAltAz = Lunar.lunarAltAzApprox(
                g.year, g.month, g.day, clockHour, offsetSec,
                _latDeg, _lonDeg
            );
        }

        // Date text — formatted per user preference. FORMAT_MEDIUM gives month as
        // a 3-letter String ("Apr"); FORMAT_SHORT gives month as Number.
        var gMed = Gregorian.info(now, Time.FORMAT_MEDIUM);
        var df = config.dateFormat();
        if (df == config.DATE_FORMAT_MONTH_DAY) {
            _cachedDateText = gMed.month + " " + g.day.toString();
        } else if (df == config.DATE_FORMAT_DAY_MONTH) {
            _cachedDateText = g.day.toString() + " " + gMed.month;
        } else {
            _cachedDateText = gMed.day_of_week + " " + g.day.toString();
        }

        // Only fetch data for fields that are actually displayed
        if (fieldIsVisible(config.FIELD_TEMPERATURE)) {
            _cachedWeatherText = getWeatherTempText();
        }
        if (fieldIsVisible(config.FIELD_BODY_BATTERY)) {
            _bodyBatteryText = getBodyBatteryDisplay();
        }
        if (fieldIsVisible(config.FIELD_STRESS)) {
            _stressText = getStressDisplay();
        }
        if (fieldIsVisible(config.FIELD_BATTERY)) {
            refreshBatteryPercent();
        }
        if (fieldIsVisible(config.FIELD_NEXT_SUN_EVENT)) {
            updateNextSunEventIfNeeded(now);
        }

        _topFieldText   = getFieldText(config.topField());
        _leftFieldText  = getFieldText(config.leftField());
        _rightFieldText = getFieldText(config.rightField());
    }

    // The next sunrise or sunset, whichever comes first. Cached as a
    // Time.Moment; recomputed only when "now" reaches the cached event.
    // Sunrise text gets a "+" prefix; sunset gets a "-".
    function updateNextSunEventIfNeeded(now) {
        if (_nextSunEventAt != null && now.lessThan(_nextSunEventAt)) {
            return;
        }

        var loc = new Position.Location({
            :latitude  => _latDeg,
            :longitude => _lonDeg,
            :format    => :degrees
        });

        var sr = Weather.getSunrise(loc, now);
        var ss = Weather.getSunset(loc, now);

        // If either event is in the future, the next one is the earlier of
        // those two. Otherwise both are past — query tomorrow's sunrise.
        var prefix = null;
        var moment = null;

        if (sr != null && now.lessThan(sr)) {
            prefix = "+";
            moment = sr;
        }
        if (ss != null && now.lessThan(ss) && (moment == null || ss.lessThan(moment))) {
            prefix = "-";
            moment = ss;
        }

        if (moment == null) {
            // Both today's events are past — try tomorrow's sunrise.
            var tomorrow = now.add(new Time.Duration(Gregorian.SECONDS_PER_DAY));
            var srNext = Weather.getSunrise(loc, tomorrow);
            if (srNext != null) {
                prefix = "+";
                moment = srNext;
            }
        }

        if (moment == null) {
            _nextSunEventText = NO_DATA;
            _nextSunEventAt   = null;
        } else {
            _nextSunEventText = prefix + formatMoment(moment);
            _nextSunEventAt   = moment;
        }
    }

    function formatMoment(moment) {
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        return formatHourMin(info.hour, info.min);
    }

    // Format a time as "HH:MM" honouring config.timeFormat().
    // Always two-digit minute; hour leading zero stripped in 12h mode.
    function formatHourMin(hour, min) {
        var h = hour;
        if (config.timeFormat() == config.TIME_FORMAT_12H) {
            h = hour % 12;
            if (h == 0) { h = 12; }
            return h.toString() + ":" + twoDigits(min);
        }
        return twoDigits(h) + ":" + twoDigits(min);
    }

    function twoDigits(n) {
        if (n < 10) { return "0" + n.toString(); }
        return n.toString();
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
        return kind == config.FIELD_HEART_RATE
            || kind == config.FIELD_STEPS
            || kind == config.FIELD_CALORIES
            || kind == config.FIELD_FLOORS
            || kind == config.FIELD_DISTANCE
            || kind == config.FIELD_BATTERY;
    }

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
        if (kind == config.FIELD_BATTERY)      { return getBatteryDisplay(); }
        if (kind == config.FIELD_STRESS)       { return _stressText; }
        if (kind == config.FIELD_NEXT_SUN_EVENT) { return _nextSunEventText; }
        if (kind == config.FIELD_STEPS)        { return getStepsDisplay(); }
        if (kind == config.FIELD_CALORIES)     { return getCaloriesDisplay(); }
        if (kind == config.FIELD_FLOORS)       { return getFloorsDisplay(); }
        if (kind == config.FIELD_DISTANCE)     { return getDistanceDisplay(); }
        if (kind == config.FIELD_RECOVERY)     { return getRecoveryDisplay(); }
        if (kind == config.FIELD_HEART_RATE)   { return getHeartRateDisplay(); }
        return NO_DATA;
    }

    // ── Data fetchers ────────────────────────────────────────────────────────

    function getHeartRateDisplay() {
        var info = Activity.getActivityInfo();
        if (info == null || info.currentHeartRate == null) { return NO_DATA; }
        return info.currentHeartRate.toNumber().toString();
    }

    // Re-reads the battery percentage. Called once per minute from
    // updateMinuteCache. Cheap, but no need to do more often than that.
    function refreshBatteryPercent() {
        var stats = System.getSystemStats();
        if (stats == null || stats.battery == null) {
            _batteryPctText = NO_DATA;
            return;
        }
        _batteryPctText = stats.battery.toNumber().toString() + "%";
    }

    // Composes the battery field text from the cached percent and a fresh
    // read of the charging flag. Cheap enough to call every second from
    // onPartialUpdate so the colour flips immediately on plug/unplug.
    function getBatteryDisplay() {
        if (_batteryPctText.equals(NO_DATA)) { return NO_DATA; }
        var stats = System.getSystemStats();
        var charging = (stats != null && stats has :charging && stats.charging);
        return charging ? "*" + _batteryPctText : _batteryPctText;
    }

    function getStressDisplay() {
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getStressHistory)) {
            return NO_DATA;
        }
        var it = SensorHistory.getStressHistory({
            :period => 5,
            :order  => SensorHistory.ORDER_NEWEST_FIRST
        });
        if (it == null) { return _stressText; }

        for (var i = 0; i < 5; i += 1) {
            var sample = it.next();
            if (sample == null) { break; }
            if (sample.data != null) {
                _stressText = sample.data.toNumber().toString() + "%";
                break;
            }
        }
        return _stressText;
    }

    function getWeatherTempText() {
        var cc = Weather.getCurrentConditions();
        if (cc == null || cc.temperature == null) { return NO_DATA; }

        var tempC = cc.temperature.toFloat();

        if (config.tempUnits() == config.TEMP_F) {
            return roundToIntString(tempC * 9.0 / 5.0 + 32.0) + "\u00B0";
        }
        if (config.tempUnits() == config.TEMP_K) {
            return roundToIntString(tempC + 273.15) + "K";
        }
        return roundToIntString(tempC) + "\u00B0";
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

    function getCaloriesDisplay() {
        var info = ActivityMonitor.getInfo();
        if (info != null && info.calories != null) {
            _cachedCaloriesText = oneDecimalString(info.calories.toFloat()) + " k";
        }
        return _cachedCaloriesText;
    }

    function getFloorsDisplay() {
        var info = ActivityMonitor.getInfo();
        if (info != null && info.floorsClimbed != null) {
            _cachedFloorsText = info.floorsClimbed.toNumber().toString();
        }
        return _cachedFloorsText;
    }

    function getDistanceDisplay() {
        var info = ActivityMonitor.getInfo();
        if (info != null && info.distance != null) {
            var dist = info.distance.toFloat();
            var suffix;
            if (config.distanceUnits() == config.DIST_MI) {
                dist = dist / 160934.4;
                suffix = " mi";
            } else {
                dist = dist / 100000.0;
                suffix = " km";
            }
            _cachedDistanceText = oneDecimalString(dist) + suffix;
        }
        return _cachedDistanceText;
    }

    function getRecoveryDisplay() {
        var info = ActivityMonitor.getInfo();
        return (info != null && (info has :timeToRecovery) && info.timeToRecovery != null)
            ? info.timeToRecovery.toString() + 'h'
            : NO_DATA;
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
