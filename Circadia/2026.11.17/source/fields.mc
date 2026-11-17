using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.Math;
using Toybox.Position;
using Toybox.SensorHistory;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.UserProfile;
using Toybox.Weather;

// "No data" placeholder shown in any field whose value cannot be retrieved.
const NO_DATA = "∞";   // ∞

// DataFields — fetches and formats the three data fields (top, bottom-left,
// bottom-right). The view asks for two kinds of refresh:
//
//   refreshMinute()  everything, once a minute (and when the fields reappear)
//   refreshLive()    only the fast-changing fields, on every other update
//
// Slots are numbered with Drawing.FIELD_SLOT_TOP / _LEFT / _RIGHT.
module DataFields {

    // Current text of each slot. null means "draw nothing" (field set to None).
    var _text = [NO_DATA, NO_DATA, NO_DATA];

    // Last good value of each kind of field. A failed read keeps the old text.
    var _dateText      = NO_DATA;
    var _weatherText   = NO_DATA;
    var _bodyBatteryText = NO_DATA;
    var _batteryPctText  = NO_DATA;
    var _stressText    = NO_DATA;
    var _stepsText     = NO_DATA;
    var _caloriesText  = NO_DATA;
    var _floorsText    = NO_DATA;
    var _distanceText  = NO_DATA;
    var _recoveryText  = NO_DATA;
    var _vo2MaxText    = NO_DATA;
    var _runDistance7dText  = NO_DATA;
    var _runTime7dText      = NO_DATA;
    var _runDistanceWtdText = NO_DATA;
    var _runTimeWtdText     = NO_DATA;

    var _nextSunEventText = NO_DATA;
    var _nextSunEventAt   = null;

    // ── What the view needs ──────────────────────────────────────────────────

    // [topText, leftText, rightText]
    function texts() {
        return _text;
    }

    function text(slot) {
        return _text[slot];
    }

    // The kind of field the user has put in a slot.
    function kind(slot) {
        if (slot == Drawing.FIELD_SLOT_TOP)  { return config.topField(); }
        if (slot == Drawing.FIELD_SLOT_LEFT) { return config.leftField(); }
        return config.rightField();
    }

    // True if the slot's field can change from one second to the next.
    function isFast(slot) {
        return needsFastRefresh(kind(slot));
    }

    function anyFast() {
        return isFast(Drawing.FIELD_SLOT_TOP)
            || isFast(Drawing.FIELD_SLOT_LEFT)
            || isFast(Drawing.FIELD_SLOT_RIGHT);
    }

    // Forget cached values that depend on settings.
    function onSettingsChanged() {
        _nextSunEventAt = null;
    }

    // ── Refresh ──────────────────────────────────────────────────────────────

    // Refresh every visible field. now = Time.now(); g = Gregorian.info(now,
    // Time.FORMAT_SHORT); latDeg/lonDeg are used for the next sun event.
    function refreshMinute(now, g, latDeg, lonDeg) {
        var gMed = Gregorian.info(now, Time.FORMAT_MEDIUM);
        var df = config.dateFormat();
        if (df == config.DATE_FORMAT_MONTH_DAY) {
            _dateText = gMed.month + " " + g.day.toString();
        } else if (df == config.DATE_FORMAT_DAY_MONTH) {
            _dateText = g.day.toString() + " " + gMed.month;
        } else {
            _dateText = gMed.day_of_week + " " + g.day.toString();
        }

        if (isVisible(config.FIELD_TEMPERATURE)) {
            _weatherText = weatherTempText();
        }
        if (isVisible(config.FIELD_BODY_BATTERY)) {
            refreshBodyBattery();
        }
        if (isVisible(config.FIELD_BATTERY)) {
            refreshBatteryPercent();
        }
        if (isVisible(config.FIELD_NEXT_SUN_EVENT)) {
            updateNextSunEventIfNeeded(now, latDeg, lonDeg);
        }
        if (isVisible(config.FIELD_RUNNING_DISTANCE_7D) ||
            isVisible(config.FIELD_RUNNING_TIME_7D)      ||
            isVisible(config.FIELD_RUNNING_DISTANCE_WTD) ||
            isVisible(config.FIELD_RUNNING_TIME_WTD)) {
            updateRunningTotals(now);
        }

        var amInfo = null;
        if (usesActivityMonitor(config.topField())  ||
            usesActivityMonitor(config.leftField()) ||
            usesActivityMonitor(config.rightField())) {
            amInfo = ActivityMonitor.getInfo();
        }

        _text[Drawing.FIELD_SLOT_TOP]   = textFor(config.topField(),   amInfo);
        _text[Drawing.FIELD_SLOT_LEFT]  = textFor(config.leftField(),  amInfo);
        _text[Drawing.FIELD_SLOT_RIGHT] = textFor(config.rightField(), amInfo);
    }

    // Refresh only the fast-changing fields.
    function refreshLive() {
        var topField   = config.topField();
        var leftField  = config.leftField();
        var rightField = config.rightField();

        var topFast   = needsFastRefresh(topField);
        var leftFast  = needsFastRefresh(leftField);
        var rightFast = needsFastRefresh(rightField);

        if (!topFast && !leftFast && !rightFast) { return; }

        var amInfo = null;
        if ((topFast   && usesActivityMonitor(topField))   ||
            (leftFast  && usesActivityMonitor(leftField))  ||
            (rightFast && usesActivityMonitor(rightField))) {
            amInfo = ActivityMonitor.getInfo();
        }

        if (topFast)   { _text[Drawing.FIELD_SLOT_TOP]   = textFor(topField,   amInfo); }
        if (leftFast)  { _text[Drawing.FIELD_SLOT_LEFT]  = textFor(leftField,  amInfo); }
        if (rightFast) { _text[Drawing.FIELD_SLOT_RIGHT] = textFor(rightField, amInfo); }
    }

    // ── Field kinds ──────────────────────────────────────────────────────────

    function isVisible(fieldKind) {
        return config.topField() == fieldKind
            || config.leftField() == fieldKind
            || config.rightField() == fieldKind;
    }

    function needsFastRefresh(fieldKind) {
        return fieldKind == config.FIELD_HEART_RATE
            || fieldKind == config.FIELD_STRESS
            || fieldKind == config.FIELD_STEPS
            || fieldKind == config.FIELD_CALORIES
            || fieldKind == config.FIELD_FLOORS
            || fieldKind == config.FIELD_DISTANCE;
    }

    function usesActivityMonitor(fieldKind) {
        return fieldKind == config.FIELD_STEPS
            || fieldKind == config.FIELD_CALORIES
            || fieldKind == config.FIELD_FLOORS
            || fieldKind == config.FIELD_DISTANCE
            || fieldKind == config.FIELD_RECOVERY
            || fieldKind == config.FIELD_STRESS
            || fieldKind == config.FIELD_VO2MAX;
    }

    function textFor(fieldKind, amInfo) {
        if (fieldKind == config.FIELD_NONE)           { return null; }
        if (fieldKind == config.FIELD_DATE)           { return _dateText; }
        if (fieldKind == config.FIELD_TEMPERATURE)    { return _weatherText; }
        if (fieldKind == config.FIELD_BODY_BATTERY)   { return _bodyBatteryText; }
        if (fieldKind == config.FIELD_BATTERY)        { return _batteryPctText; }
        if (fieldKind == config.FIELD_STRESS)         { return stressText(amInfo); }
        if (fieldKind == config.FIELD_NEXT_SUN_EVENT) { return _nextSunEventText; }
        if (fieldKind == config.FIELD_STEPS)          { return stepsText(amInfo); }
        if (fieldKind == config.FIELD_CALORIES)       { return caloriesText(amInfo); }
        if (fieldKind == config.FIELD_FLOORS)         { return floorsText(amInfo); }
        if (fieldKind == config.FIELD_DISTANCE)       { return distanceText(amInfo); }
        if (fieldKind == config.FIELD_RECOVERY)       { return recoveryText(amInfo); }
        if (fieldKind == config.FIELD_HEART_RATE)     { return heartRateText(); }
        if (fieldKind == config.FIELD_RUNNING_DISTANCE_7D)  { return _runDistance7dText; }
        if (fieldKind == config.FIELD_RUNNING_TIME_7D)      { return _runTime7dText; }
        if (fieldKind == config.FIELD_RUNNING_DISTANCE_WTD) { return _runDistanceWtdText; }
        if (fieldKind == config.FIELD_RUNNING_TIME_WTD)     { return _runTimeWtdText; }
        if (fieldKind == config.FIELD_VO2MAX)               { return vo2MaxText(); }
        return NO_DATA;
    }

    // ── Live values ──────────────────────────────────────────────────────────

    function heartRateText() {
        var info = Activity.getActivityInfo();
        if (info == null || info.currentHeartRate == null) { return NO_DATA; }
        return info.currentHeartRate.toNumber().toString();
    }

    function stressText(info) {
        if (info != null && (info has :stressScore) && info.stressScore != null) {
            _stressText = info.stressScore.toNumber().toString() + "%";
        }
        return _stressText;
    }

    function stepsText(info) {
        if (info != null && info.steps != null) {
            _stepsText = oneDecimalString(info.steps.toNumber() / 1000.0) + "k";
        }
        return _stepsText;
    }

    function caloriesText(info) {
        if (info != null && info.calories != null) {
            _caloriesText = oneDecimalString(info.calories.toFloat() / 1000.0) + "k";
        }
        return _caloriesText;
    }

    function floorsText(info) {
        if (info != null && (info has :floorsClimbed) && info.floorsClimbed != null) {
            _floorsText = info.floorsClimbed.toNumber().toString();
        }
        return _floorsText;
    }

    // ActivityMonitor distance is in centimetres.
    function distanceText(info) {
        if (info != null && info.distance != null) {
            var dist = info.distance.toFloat();
            if (config.distanceUnits() == config.DIST_MI) {
                dist = dist / 160934.4;
            } else {
                dist = dist / 100000.0;
            }
            _distanceText = oneDecimalString(dist);
        }
        return _distanceText;
    }

    function recoveryText(info) {
        if (info != null && (info has :timeToRecovery) && info.timeToRecovery != null) {
            _recoveryText = info.timeToRecovery.toString() + "h";
        }
        return _recoveryText;
    }

    function vo2MaxText() {
        var profile = UserProfile.getProfile();
        if (profile != null && (profile has :vo2maxRunning) && profile.vo2maxRunning != null) {
            _vo2MaxText = profile.vo2maxRunning.toNumber().toString();
        }
        return _vo2MaxText;
    }

    // ── Once-a-minute values ─────────────────────────────────────────────────

    function refreshBatteryPercent() {
        var stats = System.getSystemStats();
        if (stats == null || stats.battery == null) {
            _batteryPctText = NO_DATA;
            return;
        }
        _batteryPctText = stats.battery.toNumber().toString() + "%";
    }

    function weatherTempText() {
        if (!(Toybox has :Weather) || !(Weather has :getCurrentConditions)) {
            return NO_DATA;
        }
        var cc = Weather.getCurrentConditions();
        if (cc == null || cc.temperature == null) { return NO_DATA; }

        var tempC = cc.temperature.toFloat();

        if (config.tempUnits() == config.TEMP_F) {
            return roundToIntString(tempC * 9.0 / 5.0 + 32.0) + "°";
        }
        if (config.tempUnits() == config.TEMP_K) {
            return roundToIntString(tempC + 273.15) + "K";
        }
        return roundToIntString(tempC) + "°";
    }

    // Newest body battery sample from the last five. Keeps the old text if
    // the history is unavailable or empty.
    function refreshBodyBattery() {
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getBodyBatteryHistory)) {
            return;
        }
        var it = SensorHistory.getBodyBatteryHistory({
            :period => 5,
            :order  => SensorHistory.ORDER_NEWEST_FIRST
        });
        if (it == null) { return; }

        for (var i = 0; i < 5; i += 1) {
            var sample = it.next();
            if (sample == null) { break; }
            if (sample.data != null) {
                _bodyBatteryText = sample.data.toNumber().toString() + "%";
                break;
            }
        }
    }

    // "+HH:MM" for the next sunrise or "-HH:MM" for the next sunset. Only
    // recalculated once the stored event has passed.
    function updateNextSunEventIfNeeded(now, latDeg, lonDeg) {
        if (_nextSunEventAt != null && now.lessThan(_nextSunEventAt)) {
            return;
        }

        if (!(Toybox has :Weather) || !(Weather has :getSunrise) || !(Weather has :getSunset)) {
            _nextSunEventText = NO_DATA;
            _nextSunEventAt   = null;
            return;
        }

        var loc = new Position.Location({
            :latitude  => latDeg,
            :longitude => lonDeg,
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

    // All four running totals in one pass over the activity history.
    function updateRunningTotals(now) {
        var iterator = null;
        if (Toybox.UserProfile has :getUserActivityHistory) {
            iterator = UserProfile.getUserActivityHistory();
        }
        if (iterator == null) {
            _runDistance7dText  = NO_DATA;
            _runTime7dText      = NO_DATA;
            _runDistanceWtdText = NO_DATA;
            _runTimeWtdText     = NO_DATA;
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

        _runDistance7dText  = formatRunDistance(dist7d);
        _runTime7dText      = formatRunTime(time7d);
        _runDistanceWtdText = formatRunDistance(distWtd);
        _runTimeWtdText     = formatRunTime(timeWtd);
    }

    // ── Formatting ───────────────────────────────────────────────────────────

    // Distance in metres → "x.x" in the user's distance units.
    function formatRunDistance(metres) {
        if (config.distanceUnits() == config.DIST_MI) {
            return oneDecimalString(metres / 1609.344);
        }
        return oneDecimalString(metres / 1000.0);
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
