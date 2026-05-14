using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.Math;
using Toybox.Position;
using Toybox.SensorHistory;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.UserProfile;
using Toybox.WatchUi;
using Toybox.Weather;

// "No data" placeholder shown in any field whose value cannot be retrieved.
const NO_DATA = "\u221E";   // ∞

class CircadiaView extends WatchUi.WatchFace {

    var _latDeg;
    var _lonDeg;

    var _sunColor     = AmoledArt.WHITE;
    var _bodyBatteryText = NO_DATA;
    var _stressText      = NO_DATA;
    var _batteryPctText  = NO_DATA;
    var _nextSunEventText = NO_DATA;
    var _nextSunEventAt   = null;
    var _isSleeping = false;

    var _cacheYear  = -1;
    var _cacheMonth = -1;
    var _cacheDay   = -1;
    var _cacheHour  = -1;
    var _cacheMin   = -1;
    var _cacheMipMode = false;

    var _cachedMoonDiameterDeg = Drawing.NEW_MOON_DIAMETER_DEG;
    var _cachedMoonPhaseAngle  = 0.0;
    var _cachedMoonPhaseBin    = Lunar.PHASE_NEW;
    var _cachedMoonAltAz       = [0.0, 0.0];
    var _cachedSunAltAz        = [0.0, 0.0];
    var _cachedSunsetAccent    = 0.0;

    var _cachedLayoutW = -1.0;
    var _cachedLayoutH = -1.0;
    var _layoutCache   = [0.0, 0.0, 0.0];
    var _skyCache      = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Lunar.PHASE_NEW];

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
    var _cachedRunningDistance7dText  = NO_DATA;
    var _cachedRunningTime7dText      = NO_DATA;
    var _cachedRunningDistanceWtdText = NO_DATA;
    var _cachedRunningTimeWtdText     = NO_DATA;
    var _cachedVo2MaxText             = NO_DATA;

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

        var showSky    = config.showSky(_isSleeping);
        var showFace   = config.showFace(_isSleeping);
        var showFields = config.showFields(_isSleeping);
        var mipMode    = config.mipMode();

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

        if (showFields) {
            refreshLiveFields();
        }

        if (showSky) {
            updateSkyCache(g, t);
            Drawing.drawSky(
                dc, _skyCache, _sunColor,
                config.showSun(), config.showMoon(), config.showStars(),
                mipMode
            );
        } else {
            Drawing.clearScreen(dc);
        }

        if (showFace) {
            Drawing.drawFace(
                dc, _layoutCache,
                t.hour, t.min, t.sec,
                config.showSeconds() && showFields, _cachedSunsetAccent, _sunColor,
                showFields ? _topFieldText : null,
                showFields ? _leftFieldText : null,
                showFields ? _rightFieldText : null,
                mipMode
            );
        }
    }

    function onPartialUpdate(dc) {
        if (!config.showFace(_isSleeping) || !config.showFields(_isSleeping)) { return; }

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

    function updateLayoutCache(dc) {
        var w = dc.getWidth().toFloat();
        var h = dc.getHeight().toFloat();
        if (w != _cachedLayoutW || h != _cachedLayoutH) {
            _layoutCache   = Drawing.layout(w, h);
            _cachedLayoutW = w;
            _cachedLayoutH = h;
        }
    }

    function updateMinuteCache(now, g, t, mipMode) {
        updateLocation();

        var clockHour = t.hour + t.min / 60.0;
        var offsetSec = t.timeZoneOffset;

        _cachedMoonPhaseAngle = Lunar.lunarPhaseAngle(
            g.year, g.month, g.day, clockHour, offsetSec
        );
        _cachedMoonPhaseBin = Lunar.lunarPhaseBinFromAngle(_cachedMoonPhaseAngle);
        _cachedMoonDiameterDeg = (_cachedMoonPhaseBin == Lunar.PHASE_NEW)
            ? Drawing.NEW_MOON_DIAMETER_DEG
            : config.moonDiameterDeg();

        _cachedSunAltAz = Solar.solarAltAzApprox(
            g.year, g.month, g.day, clockHour, offsetSec,
            _latDeg, _lonDeg
        );
        _cachedSunsetAccent = AmoledArt.sunsetAccentScale(_cachedSunAltAz[0]);
        _sunColor = mipMode
            ? MiPArt.brightSunColorForAlt(_cachedSunAltAz[0])
            : AmoledArt.sunColorForAlt(_cachedSunAltAz[0]);

        _cachedMoonAltAz = [0.0, 0.0];
        if (config.showMoon()) {
            _cachedMoonAltAz = Lunar.lunarAltAzApprox(
                g.year, g.month, g.day, clockHour, offsetSec,
                _latDeg, _lonDeg
            );
        }

        var gMed = Gregorian.info(now, Time.FORMAT_MEDIUM);
        var df = config.dateFormat();
        if (df == config.DATE_FORMAT_MONTH_DAY) {
            _cachedDateText = gMed.month + " " + g.day.toString();
        } else if (df == config.DATE_FORMAT_DAY_MONTH) {
            _cachedDateText = g.day.toString() + " " + gMed.month;
        } else {
            _cachedDateText = gMed.day_of_week + " " + g.day.toString();
        }

        if (fieldIsVisible(config.FIELD_TEMPERATURE)) {
            _cachedWeatherText = getWeatherTempText();
        }
        if (fieldIsVisible(config.FIELD_BODY_BATTERY)) {
            _bodyBatteryText = getBodyBatteryDisplay();
        }
        if (fieldIsVisible(config.FIELD_BATTERY)) {
            refreshBatteryPercent();
        }
        if (fieldIsVisible(config.FIELD_NEXT_SUN_EVENT)) {
            updateNextSunEventIfNeeded(now);
        }
        if (fieldIsVisible(config.FIELD_RUNNING_DISTANCE_7D) ||
            fieldIsVisible(config.FIELD_RUNNING_TIME_7D)      ||
            fieldIsVisible(config.FIELD_RUNNING_DISTANCE_WTD) ||
            fieldIsVisible(config.FIELD_RUNNING_TIME_WTD)) {
            updateRunningCache(now);
        }

        var amInfo = anyActivityMonitorFieldVisible() ? ActivityMonitor.getInfo() : null;
        _topFieldText   = getFieldText(config.topField(),   amInfo);
        _leftFieldText  = getFieldText(config.leftField(),  amInfo);
        _rightFieldText = getFieldText(config.rightField(), amInfo);
    }

    function updateNextSunEventIfNeeded(now) {
        if (_nextSunEventAt != null && now.lessThan(_nextSunEventAt)) {
            return;
        }

        if (!(Toybox has :Weather) || !(Weather has :getSunrise) || !(Weather has :getSunset)) {
            _nextSunEventText = NO_DATA;
            _nextSunEventAt   = null;
            return;
        }

        var loc = new Position.Location({
            :latitude  => _latDeg,
            :longitude => _lonDeg,
            :format    => :degrees
        });

        var sr = Weather.getSunrise(loc, now);
        var ss = Weather.getSunset(loc, now);

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
            var info = Gregorian.info(moment, Time.FORMAT_SHORT);
            _nextSunEventText = prefix + MathUtil.formatHourMin(info.hour, info.min, config.is12hMode());
            _nextSunEventAt   = moment;
        }
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

    function fieldIsVisible(kind) {
        return config.topField() == kind
            || config.leftField() == kind
            || config.rightField() == kind;
    }

    function fieldNeedsFastRefresh(kind) {
        return kind == config.FIELD_HEART_RATE
            || kind == config.FIELD_STRESS
            || kind == config.FIELD_STEPS
            || kind == config.FIELD_CALORIES
            || kind == config.FIELD_FLOORS
            || kind == config.FIELD_DISTANCE;
    }

    function fieldUsesActivityMonitor(kind) {
        return kind == config.FIELD_STEPS
            || kind == config.FIELD_CALORIES
            || kind == config.FIELD_FLOORS
            || kind == config.FIELD_DISTANCE
            || kind == config.FIELD_RECOVERY
            || kind == config.FIELD_STRESS
            || kind == config.FIELD_VO2MAX;
    }

    function anyActivityMonitorFieldVisible() {
        return fieldUsesActivityMonitor(config.topField())
            || fieldUsesActivityMonitor(config.leftField())
            || fieldUsesActivityMonitor(config.rightField());
    }

    function refreshLiveFields() {
        var topField   = config.topField();
        var leftField  = config.leftField();
        var rightField = config.rightField();

        var topFast   = fieldNeedsFastRefresh(topField);
        var leftFast  = fieldNeedsFastRefresh(leftField);
        var rightFast = fieldNeedsFastRefresh(rightField);

        if (!topFast && !leftFast && !rightFast) { return; }

        var amInfo = null;
        if ((topFast   && fieldUsesActivityMonitor(topField))   ||
            (leftFast  && fieldUsesActivityMonitor(leftField))  ||
            (rightFast && fieldUsesActivityMonitor(rightField))) {
            amInfo = ActivityMonitor.getInfo();
        }

        if (topFast)   { _topFieldText   = getFieldText(topField,   amInfo); }
        if (leftFast)  { _leftFieldText  = getFieldText(leftField,  amInfo); }
        if (rightFast) { _rightFieldText = getFieldText(rightField, amInfo); }
    }

    function getFieldText(kind, amInfo) {
        if (kind == config.FIELD_DATE)         { return _cachedDateText; }
        if (kind == config.FIELD_TEMPERATURE)  { return _cachedWeatherText; }
        if (kind == config.FIELD_BODY_BATTERY) { return _bodyBatteryText; }
        if (kind == config.FIELD_BATTERY)      { return _batteryPctText; }
        if (kind == config.FIELD_STRESS)       { return getStressDisplay(amInfo); }
        if (kind == config.FIELD_NEXT_SUN_EVENT) { return _nextSunEventText; }
        if (kind == config.FIELD_STEPS)        { return getStepsDisplay(amInfo); }
        if (kind == config.FIELD_CALORIES)     { return getCaloriesDisplay(amInfo); }
        if (kind == config.FIELD_FLOORS)       { return getFloorsDisplay(amInfo); }
        if (kind == config.FIELD_DISTANCE)     { return getDistanceDisplay(amInfo); }
        if (kind == config.FIELD_RECOVERY)     { return getRecoveryDisplay(amInfo); }
        if (kind == config.FIELD_HEART_RATE)   { return getHeartRateDisplay(); }
        if (kind == config.FIELD_RUNNING_DISTANCE_7D)  { return _cachedRunningDistance7dText;  }
        if (kind == config.FIELD_RUNNING_TIME_7D)       { return _cachedRunningTime7dText;       }
        if (kind == config.FIELD_RUNNING_DISTANCE_WTD)  { return _cachedRunningDistanceWtdText;  }
        if (kind == config.FIELD_RUNNING_TIME_WTD)      { return _cachedRunningTimeWtdText;      }
        if (kind == config.FIELD_VO2MAX)                { return getVo2MaxDisplay(amInfo);       }
        return NO_DATA;
    }

    function getHeartRateDisplay() {
        var info = Activity.getActivityInfo();
        if (info == null || info.currentHeartRate == null) { return NO_DATA; }
        return info.currentHeartRate.toNumber().toString();
    }

    function refreshBatteryPercent() {
        var stats = System.getSystemStats();
        if (stats == null || stats.battery == null) {
            _batteryPctText = NO_DATA;
            return;
        }
        _batteryPctText = stats.battery.toNumber().toString() + "%";
    }

    function getStressDisplay(info) {
        if (info != null && (info has :stressScore) && info.stressScore != null) {
            _stressText = info.stressScore.toNumber().toString() + "%";
        }
        return _stressText;
    }

    function getWeatherTempText() {
        if (!(Toybox has :Weather) || !(Weather has :getCurrentConditions)) {
            return NO_DATA;
        }
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
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getBodyBatteryHistory)) {
            return _bodyBatteryText;
        }
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

    function getStepsDisplay(info) {
        if (info != null && info.steps != null) {
            _cachedStepsText = oneDecimalString(info.steps.toNumber() / 1000.0) + "k";
        }
        return _cachedStepsText;
    }

    function getCaloriesDisplay(info) {
        if (info != null && info.calories != null) {
            _cachedCaloriesText = oneDecimalString(info.calories.toFloat() / 1000.0) + "k";
        }
        return _cachedCaloriesText;
    }

    function getFloorsDisplay(info) {
        if (info != null && (info has :floorsClimbed) && info.floorsClimbed != null) {
            _cachedFloorsText = info.floorsClimbed.toNumber().toString();
        }
        return _cachedFloorsText;
    }

    function getDistanceDisplay(info) {
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
            _cachedDistanceText = oneDecimalString(dist);
        }
        return _cachedDistanceText;
    }

    function getRecoveryDisplay(info) {
        if (info != null && (info has :timeToRecovery) && info.timeToRecovery != null) {
            _cachedRecoveryText = info.timeToRecovery.toString() + 'h';
        }
        return _cachedRecoveryText;
    }

    function getVo2MaxDisplay(info) {
        var profile = UserProfile.getProfile();
        if (profile != null && (profile has :vo2maxRunning) && profile.vo2maxRunning != null) {
            _cachedVo2MaxText = profile.vo2maxRunning.toNumber().toString();
        }
        return _cachedVo2MaxText;
    }

    // Compute all four running metrics in one pass over activity history.
    // Called once per minute when any of the four fields is visible.
    function updateRunningCache(now) {
        if (!(Toybox.UserProfile has :getUserActivityHistory)) {
            _cachedRunningDistance7dText  = NO_DATA;
            _cachedRunningTime7dText      = NO_DATA;
            _cachedRunningDistanceWtdText = NO_DATA;
            _cachedRunningTimeWtdText     = NO_DATA;
            return;
        }

        var iterator = UserProfile.getUserActivityHistory();
        if (iterator == null) {
            _cachedRunningDistance7dText  = NO_DATA;
            _cachedRunningTime7dText      = NO_DATA;
            _cachedRunningDistanceWtdText = NO_DATA;
            _cachedRunningTimeWtdText     = NO_DATA;
            return;
        }

        var localNow = Gregorian.info(now, Time.FORMAT_SHORT);
        var secsSinceMidnight = localNow.hour * 3600
                              + localNow.min  * 60
                              + localNow.sec;
        var cutoff7d = now.subtract(new Time.Duration(
            secsSinceMidnight + 6 * Gregorian.SECONDS_PER_DAY
        ));

        var todayDow = localNow.day_of_week;
        var startDow = config.weekStartDay();
        var daysBack = (todayDow - startDow + 7) % 7;
        var cutoffWtd = now.subtract(new Time.Duration(
            secsSinceMidnight + daysBack * Gregorian.SECONDS_PER_DAY
        ));

        var dist7d  = 0.0;
        var time7d  = 0;
        var distWtd = 0.0;
        var timeWtd = 0;

        var item = iterator.next();
        while (item != null) {
            if (item.startTime == null || item.type != Activity.SPORT_RUNNING) {
                item = iterator.next();
                continue;
            }

            var d = (item.distance != null) ? item.distance.toFloat() : 0.0;
            var s = (item.duration != null) ? item.duration.value()   : 0;

            if (!item.startTime.lessThan(cutoff7d))  { dist7d  += d; time7d  += s; }
            if (!item.startTime.lessThan(cutoffWtd)) { distWtd += d; timeWtd += s; }

            item = iterator.next();
        }

        _cachedRunningDistance7dText  = formatRunDistance(dist7d);
        _cachedRunningTime7dText      = formatRunTime(time7d);
        _cachedRunningDistanceWtdText = formatRunDistance(distWtd);
        _cachedRunningTimeWtdText     = formatRunTime(timeWtd);
    }

    // Distance in metres → "x.x km" or "x.x mi"
    function formatRunDistance(metres) {
        var value;
        var suffix;
        if (config.distanceUnits() == config.DIST_MI) {
            value  = metres / 1609.344;
            suffix = "mi";
        } else {
            value  = metres / 1000.0;
            suffix = "km";
        }
        return oneDecimalString(value);
    }

    // Seconds → "H:MM" or "HH:MM"
    function formatRunTime(seconds) {
        var totalMin = seconds / 60;
        var h   = totalMin / 60;
        var min = totalMin % 60;
        return h.toString() + ":" + min.format("%02d");
    }

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