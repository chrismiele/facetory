using Toybox.Application;
using Toybox.System;

// Reads user settings from Application.Properties and caches them in module
// variables so the per-frame accessors don't pay the lookup cost. Call
// config.refresh() whenever settings change (at app start and from
// AppBase.onSettingsChanged).
module config {

    // ── Enums ────────────────────────────────────────────────────────────────

    const FIELD_NONE         = 17;
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
    const FIELD_RECOVERY              = 11;
    const FIELD_RUNNING_DISTANCE_7D   = 12;
    const FIELD_RUNNING_TIME_7D       = 13;
    const FIELD_RUNNING_DISTANCE_WTD  = 14;
    const FIELD_RUNNING_TIME_WTD      = 15;
    const FIELD_VO2MAX                = 16;

    const TEMP_C = 0;
    const TEMP_F = 1;
    const TEMP_K = 2;

    const DIST_KM = 0;
    const DIST_MI = 1;

    const MOON_SIZE_SMALL  = 0;
    const MOON_SIZE_MEDIUM = 1;
    const MOON_SIZE_LARGE  = 2;

    const AOD_TIME_ONLY = 0;
    const AOD_SKY_ONLY  = 1;

    const TIME_FORMAT_24H = 0;
    const TIME_FORMAT_12H = 1;

    const DATE_FORMAT_DAY_NUMBER = 0;   // e.g. "Mon 5"
    const DATE_FORMAT_MONTH_DAY  = 1;   // e.g. "Apr 5"
    const DATE_FORMAT_DAY_MONTH  = 2;   // e.g. "5 Apr"

    // Display type ("mipMode"): full colour (AMOLED art), simplified (MIP
    // art), or automatic, by the screen.
    const DISPLAY_AMOLED = 0;
    const DISPLAY_MIP    = 1;
    const DISPLAY_AUTO   = 2;

    // ── Cached property values ───────────────────────────────────────────────

    var _topField         = FIELD_BATTERY;
    var _leftField        = FIELD_HEART_RATE;
    var _rightField       = FIELD_NEXT_SUN_EVENT;
    var _tempUnits        = TEMP_C;
    var _distanceUnits    = DIST_KM;
    var _mipMode          = DISPLAY_AUTO;
    var _mipScreen        = false;   // the screen is not AMOLED (needs no burn-in protection)
    var _showSeconds      = false;
    // Stars shown at full night: always 200 ("Lots"), or 100 on watches with
    // under 100 KB for a watch face (such as the Forerunner 245, 96 KB).
    var _starCount        = 200;
    var _starMode         = 0;       // 0 = brightest, 1 = constellations, 2 = zodiac
    var _useGps           = 1;       // 1 = device GPS, 0 = home coordinates
    var _latDeg           = 49.29;
    var _lonDeg           = -123.12;
    var _aodBehaviour     = AOD_SKY_ONLY;
    var _timeFormat       = TIME_FORMAT_24H;
    var _dateFormat       = DATE_FORMAT_DAY_NUMBER;
    var _minuteSaturation = 3;       // 0-5 step index, mapped to 0.0-1.0 in step of 0.2
    // Week start day: 1=Sun, 2=Mon, ..., 7=Sat (matches Gregorian.Info.day_of_week)
    var _weekStartDay     = 2;       // default: Monday
    var _moonSize         = MOON_SIZE_MEDIUM;   // default: Medium
    var _moonDarkSide     = false;   // optional extra, off by default

    // True on displays that enforce burn-in protection (AMOLED). Read from the
    // device, not from a setting: it decides whether low power means "always-on
    // mode with restrictions" (AMOLED) or "normal face, updated less often" (MIP).
    var _burnIn           = false;

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
        var ds            = System.getDeviceSettings();
        _mipScreen        = (ds has :requiresBurnInProtection) && !ds.requiresBurnInProtection;
        _showSeconds      = readBool(  "showSeconds",      _showSeconds);
        _starCount        = (System.getSystemStats().totalMemory < 102400) ? 100 : 200;
        _starMode         = readNumber("starMode",         _starMode);
        _useGps           = readNumber("useGps",           _useGps);
        _latDeg           = readFloat( "latDeg",           _latDeg);
        _lonDeg           = readFloat( "lonDeg",           _lonDeg);
        _aodBehaviour     = readNumber("aodBehaviour",     _aodBehaviour);
        _timeFormat       = readNumber("timeFormat",       _timeFormat);
        _dateFormat       = readNumber("dateFormat",       _dateFormat);
        _minuteSaturation = readNumber("minuteSaturation", _minuteSaturation);
        _weekStartDay     = readNumber("weekStartDay",     _weekStartDay);
        _moonSize         = readNumber("moonSize",         _moonSize);
        _moonDarkSide     = readBool(  "moonDarkSide",     _moonDarkSide);

        var ds = System.getDeviceSettings();
        _burnIn = (ds has :requiresBurnInProtection) && ds.requiresBurnInProtection;
    }

    // ── Accessors (zero-cost reads of cached values) ─────────────────────────

    function topField()         { return _topField;         }
    function leftField()        { return _leftField;        }
    function rightField()       { return _rightField;       }
    function tempUnits()        { return _tempUnits;        }
    function distanceUnits()    { return _distanceUnits;    }
    // The simplified (MIP) art: chosen, or by default whenever the screen
    // is not AMOLED.
    function mipMode()          { return (_mipMode == DISPLAY_AUTO) ? _mipScreen : (_mipMode == DISPLAY_MIP); }
    function showSeconds()      { return _showSeconds;      }
    function showMoon()         { return true;              }
    function showSun()          { return true;              }
    function starCount()        { return _starCount;        }
    function starMode()         { return _starMode;         }
    function useGps()           { return _useGps > 0;       }
    function latDeg()           { return _latDeg;           }
    function lonDeg()           { return _lonDeg;           }
    function minuteSaturation() { return _minuteSaturation / 5.0; }
    function aodBehaviour()     { return _aodBehaviour;     }
    function timeFormat()       { return _timeFormat;       }
    function dateFormat()       { return _dateFormat;       }
    function weekStartDay()     { return _weekStartDay;     }
    function moonSize()         { return _moonSize;         }
    function moonDarkSide()     { return _moonDarkSide;     }
    // Moon diameter in degrees of sky, from the "Sun and moon size" setting.
    // The sun's white disc always matches it (SunArt.sizeScale()), and the
    // rest of the sun scales with it; Large (20) is the full-size sun: keep it
    // equal to 2 * SunArt.WHITE_DISC_DEG. The smaller settings are 3/4 and 7/8.
    function moonDiameterDeg() {
        if (_moonSize == MOON_SIZE_MEDIUM) { return 17.5; }
        if (_moonSize == MOON_SIZE_LARGE)  { return 20.0; }
        return 15.0;
    }

    function showStars()        { return _starCount > 0;    }
    function is12hMode()        { return _timeFormat == TIME_FORMAT_12H; }

    // True only when the always-on restrictions apply: the watch is asleep AND
    // the display needs burn-in protection (AMOLED). A MIP watch in low power
    // is not restricted, so it keeps the full face: sky, time and fields.
    function aodActive(isSleeping) {
        return isSleeping && _burnIn;
    }

    // Whether to draw the digital clock right now.
    function showFace(isSleeping) {
        if (!aodActive(isSleeping))         { return true; }
        return _aodBehaviour == AOD_TIME_ONLY;
    }

    // Whether to draw sun/moon/stars right now.
    function showSky(isSleeping) {
        if (!aodActive(isSleeping))         { return true; }
        return _aodBehaviour == AOD_SKY_ONLY;
    }

    // Data fields and seconds are hidden only in AMOLED always-on mode.
    function showFields(isSleeping) {
        return !aodActive(isSleeping);
    }

}
