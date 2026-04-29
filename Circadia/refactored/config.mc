using Toybox.Application;

// Reads user settings from Application.Properties and caches them in module
// variables so the per-frame accessors don't pay the lookup cost. Call
// config.refresh() whenever settings change (at app start and from
// AppBase.onSettingsChanged).
module config {

    // ── Enums ────────────────────────────────────────────────────────────────

    const FIELD_DATE         = 0;
    const FIELD_BODY_BATTERY = 1;
    const FIELD_TEMPERATURE  = 2;
    const FIELD_HEART_RATE   = 3;
    const FIELD_STEPS        = 4;
    const FIELD_BATTERY      = 5;
    const FIELD_NEXT_SUN_EVENT = 6;
    const FIELD_STRESS       = 7;

    const UNIT_METRIC   = 0;
    const UNIT_IMPERIAL = 1;

    const AOD_TIME_ONLY = 0;
    const AOD_SKY_ONLY  = 1;
    const AOD_SHOW_ALL  = 2;

    const TIME_FORMAT_24H = 0;
    const TIME_FORMAT_12H = 1;

    const DATE_FORMAT_DAY_NUMBER = 0;   // e.g. "Mon 5"
    const DATE_FORMAT_MONTH_DAY  = 1;   // e.g. "Apr 5"
    const DATE_FORMAT_DAY_MONTH  = 2;   // e.g. "5 Apr"

    // ── Cached property values ───────────────────────────────────────────────

    var _topField         = FIELD_BATTERY;
    var _leftField        = FIELD_HEART_RATE;
    var _rightField       = FIELD_NEXT_SUN_EVENT;
    var _tempUnits        = UNIT_METRIC;
    var _mipMode          = 0;       // 0 = AMOLED, 1 = MIP
    var _showSeconds      = false;
    var _showMoon         = true;
    var _showSun          = true;
    var _starCount        = 100;
    var _useGps           = 1;       // 1 = device GPS, 0 = home coordinates
    var _latDeg           = 49.29;
    var _lonDeg           = -123.12;
    var _minuteSaturation = 0.7;
    var _aodBehaviour     = AOD_SKY_ONLY;
    var _timeFormat       = TIME_FORMAT_24H;
    var _dateFormat       = DATE_FORMAT_DAY_NUMBER;

    // Helpers — getValue throws if a key is missing from properties.xml,
    // so wrap each read in a try/catch and fall back to the current value.
    function readNumber(key, fallback) {
        try {
            var v = Application.Properties.getValue(key);
            if (v == null) { return fallback; }
            return v.toNumber();
        } catch (e) {
            return fallback;
        }
    }

    function readFloat(key, fallback) {
        try {
            var v = Application.Properties.getValue(key);
            if (v == null) { return fallback; }
            return v.toFloat();
        } catch (e) {
            return fallback;
        }
    }

    function readBool(key, fallback) {
        try {
            var v = Application.Properties.getValue(key);
            if (v == null) { return fallback; }
            return v;
        } catch (e) {
            return fallback;
        }
    }

    // ── Refresh — called at startup and whenever settings change ─────────────

    function refresh() {
        _topField         = readNumber("topField",         _topField);
        _leftField        = readNumber("leftField",        _leftField);
        _rightField       = readNumber("rightField",       _rightField);
        _tempUnits        = readNumber("tempUnits",        _tempUnits);
        _mipMode          = readNumber("mipMode",          _mipMode);
        _showSeconds      = readBool(  "showSeconds",      _showSeconds);
        _showMoon         = readBool(  "showMoon",         _showMoon);
        _showSun          = readBool(  "showSun",          _showSun);
        _starCount        = readNumber("starCount",        _starCount);
        _useGps           = readNumber("useGps",           _useGps);
        _latDeg           = readFloat( "latDeg",           _latDeg);
        _lonDeg           = readFloat( "lonDeg",           _lonDeg);
        _minuteSaturation = readFloat( "minuteSaturation", _minuteSaturation);
        _aodBehaviour     = readNumber("aodBehaviour",     _aodBehaviour);
        _timeFormat       = readNumber("timeFormat",       _timeFormat);
        _dateFormat       = readNumber("dateFormat",       _dateFormat);
    }

    // ── Accessors (zero-cost reads of cached values) ─────────────────────────

    function topField()         { return _topField;         }
    function leftField()        { return _leftField;        }
    function rightField()       { return _rightField;       }
    function tempUnits()        { return _tempUnits;        }
    function mipMode()          { return _mipMode > 0;      }
    function showSeconds()      { return _showSeconds;      }
    function showMoon()         { return _showMoon;         }
    function showSun()          { return _showSun;          }
    function starCount()        { return _starCount;        }
    function useGps()           { return _useGps > 0;       }
    function latDeg()           { return _latDeg;           }
    function lonDeg()           { return _lonDeg;           }
    function minuteSaturation() { return _minuteSaturation; }
    function aodBehaviour()     { return _aodBehaviour;     }
    function timeFormat()       { return _timeFormat;       }
    function dateFormat()       { return _dateFormat;       }

    function showStars()        { return _starCount > 0;    }

    // Whether to draw the digital clock + data fields right now, given AOD mode.
    function showFace(isSleeping) {
        if (!isSleeping)                            { return true; }
        if (_aodBehaviour == AOD_SHOW_ALL)          { return true; }
        if (_aodBehaviour == AOD_TIME_ONLY)         { return true; }
        return false;   // AOD_SKY_ONLY
    }

    // Whether to draw sun/moon/stars right now, given AOD mode.
    function showSky(isSleeping) {
        if (!isSleeping)                            { return true; }
        if (_aodBehaviour == AOD_SHOW_ALL)          { return true; }
        if (_aodBehaviour == AOD_SKY_ONLY)          { return true; }
        return false;   // AOD_TIME_ONLY
    }

}
