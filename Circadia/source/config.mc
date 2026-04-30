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
    const FIELD_CALORIES     = 8;
    const FIELD_FLOORS       = 9;
    const FIELD_DISTANCE     = 10;
    const FIELD_RECOVERY     = 11;

    const TEMP_C = 0;
    const TEMP_F = 1;
    const TEMP_K = 2;

    const DIST_KM = 0;
    const DIST_MI = 1;

    const AOD_TIME_ONLY = 0;
    const AOD_SKY_ONLY  = 1;
    const AOD_SHOW_ALL  = 2;

    const TIME_FORMAT_24H = 0;
    const TIME_FORMAT_12H = 1;

    const HALO_RING = 0;
    const HALO_DISC = 1;

    const DATE_FORMAT_DAY_NUMBER = 0;   // e.g. "Mon 5"
    const DATE_FORMAT_MONTH_DAY  = 1;   // e.g. "Apr 5"
    const DATE_FORMAT_DAY_MONTH  = 2;   // e.g. "5 Apr"

    // ── Cached property values ───────────────────────────────────────────────

    var _topField         = FIELD_BATTERY;
    var _leftField        = FIELD_HEART_RATE;
    var _rightField       = FIELD_NEXT_SUN_EVENT;
    var _tempUnits        = TEMP_C;
    var _distanceUnits    = DIST_KM;
    var _mipMode          = 0;       // 0 = AMOLED, 1 = MIP
    var _showSeconds      = false;
    var _starCount        = 100;
    var _useGps           = 1;       // 1 = device GPS, 0 = home coordinates
    var _latDeg           = 49.29;
    var _lonDeg           = -123.12;
    var _aodBehaviour     = AOD_SKY_ONLY;
    var _timeFormat       = TIME_FORMAT_24H;
    var _dateFormat       = DATE_FORMAT_DAY_NUMBER;
    var _minuteSaturation = 3;       // 0-5 step index, mapped to 0.0-1.0 in step of 0.2
    var _fieldSaturation  = 0;       // 0-5 step index for data-field text
    var _haloStyle        = HALO_RING;

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
        _distanceUnits    = readNumber("distanceUnits",    _distanceUnits);
        _mipMode          = readNumber("mipMode",          _mipMode);
        _showSeconds      = readBool(  "showSeconds",      _showSeconds);
        _starCount        = readNumber("starCount",        _starCount);
        _useGps           = readNumber("useGps",           _useGps);
        _latDeg           = readFloat( "latDeg",           _latDeg);
        _lonDeg           = readFloat( "lonDeg",           _lonDeg);
        _aodBehaviour     = readNumber("aodBehaviour",     _aodBehaviour);
        _timeFormat       = readNumber("timeFormat",       _timeFormat);
        _dateFormat       = readNumber("dateFormat",       _dateFormat);
        _minuteSaturation = readNumber("minuteSaturation", _minuteSaturation);
        _fieldSaturation  = readNumber("fieldSaturation",  _fieldSaturation);
        _haloStyle        = readNumber("haloStyle",        _haloStyle);
    }

    // ── Accessors (zero-cost reads of cached values) ─────────────────────────

    function topField()         { return _topField;         }
    function leftField()        { return _leftField;        }
    function rightField()       { return _rightField;       }
    function tempUnits()        { return _tempUnits;        }
    function distanceUnits()    { return _distanceUnits;    }
    function mipMode()          { return _mipMode > 0;      }
    function showSeconds()      { return _showSeconds;      }
    function showMoon()         { return true;              }
    function showSun()          { return true;              }
    function starCount()        { return _starCount;        }
    function useGps()           { return _useGps > 0;       }
    function latDeg()           { return _latDeg;           }
    function lonDeg()           { return _lonDeg;           }
    function minuteSaturation() { return _minuteSaturation / 5.0; }
    function fieldSaturation()  { return _fieldSaturation  / 5.0; }
    function haloStyle()        { return _haloStyle;        }
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
