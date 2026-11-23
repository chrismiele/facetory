using Toybox.Lang;
using Toybox.Math;

// Shared helpers used by Solar, Lunar, Stellar, Drawing, and CircadiaView.
// Centralising these removes duplicated helpers across modules.

module MathUtil {

    // Conversion constants — computed once, not per call.
    const DEG_TO_RAD = Math.PI / 180.0;
    const RAD_TO_DEG = 180.0 / Math.PI;

    function deg2rad(x) { return x * DEG_TO_RAD; }
    function rad2deg(x) { return x * RAD_TO_DEG; }

    function sinDeg(x) { return Math.sin(x * DEG_TO_RAD); }
    function cosDeg(x) { return Math.cos(x * DEG_TO_RAD); }

    function clamp(x, lo, hi) {
        if (x < lo) { return lo; }
        if (x > hi) { return hi; }
        return x;
    }

    function abs(x) { return (x < 0.0) ? -x : x; }

    function frac(x) { return x - Math.floor(x); }

    function roundNearest(x) {
        return (x >= 0.0) ? (x + 0.5).toNumber() : (x - 0.5).toNumber();
    }

    function wrap360(x) {
        while (x <    0.0) { x += 360.0; }
        while (x >= 360.0) { x -= 360.0; }
        return x;
    }

    function wrap180(x) {
        while (x <  -180.0) { x += 360.0; }
        while (x >=  180.0) { x -= 360.0; }
        return x;
    }

    function isLeapYear(year) {
        if ((year % 400) == 0) { return true;  }
        if ((year % 100) == 0) { return false; }
        return ((year % 4) == 0);
    }

    // Atmospheric refraction correction (degrees). Returns 0 below -4°.
    function refractionDeg(altDeg) {
        if (altDeg < -4.0) { return 0.0; }
        return 1.02 / (60.0 * Math.tan(deg2rad(altDeg + 10.3 / (altDeg + 5.11))));
    }

    // Linear blend of two packed RGB colours. t=0 → c0, t=1 → c1.
    function blendColor(c0, c1, t) {
        t = clamp(t, 0.0, 1.0);
        var r = ((c0 / 65536) % 256 + ((c1 / 65536) % 256 - (c0 / 65536) % 256) * t).toNumber();
        var g = ((c0 / 256)   % 256 + ((c1 / 256)   % 256 - (c0 / 256)   % 256) * t).toNumber();
        var b = ( c0          % 256 + ( c1           % 256 -  c0          % 256) * t).toNumber();
        return r * 65536 + g * 256 + b;
    }

    // Scale a packed RGB colour's brightness. s=0 → black, s=1 → unchanged.
    function scaleColor(color, s) {
        s = clamp(s, 0.0, 1.0);
        var r = (((color / 65536) % 256) * s).toNumber();
        var g = (((color / 256)   % 256) * s).toNumber();
        var b = ( (color          % 256) * s).toNumber();
        return r * 65536 + g * 256 + b;
    }

    // ── Calendar helpers (used by Solar and Stellar) ─────────────────────────

    // Days elapsed before each month (non-leap year).
    const MONTH_OFFSETS = [0.0, 31.0, 59.0, 90.0, 120.0, 151.0, 181.0, 212.0, 243.0, 273.0, 304.0, 334.0];

    function dayOfYear(year, month, day) {
        var doy = MONTH_OFFSETS[month - 1] + day.toFloat();
        if (month > 2 && isLeapYear(year)) { doy += 1.0; }
        return doy;
    }

    function daysInMonth(year, month) {
        if (month == 2) { return isLeapYear(year) ? 29 : 28; }
        if (month == 4 || month == 6 || month == 9 || month == 11) { return 30; }
        return 31;
    }

    // Advance or retreat a calendar date by one day (delta = +1 or -1).
    function shiftDate(year, month, day, delta) {
        var y = year;
        var m = month;
        var d = day + delta;

        if (delta < 0 && d < 1) {
            m -= 1;
            if (m < 1) { m = 12; y -= 1; }
            d = daysInMonth(y, m);
        } else if (delta > 0 && d > daysInMonth(y, m)) {
            d = 1;
            m += 1;
            if (m > 12) { m = 1; y += 1; }
        }
        return [y, m, d];
    }

    // Convert a local clock reading to UTC: returns [year, month, day, utcHour].
    function utcFromLocal(year, month, day, clockHour, offsetSec) {
        var utcHour = clockHour - offsetSec / 3600.0;
        var y = year;
        var m = month;
        var d = day;

        while (utcHour <    0.0) {
            utcHour += 24.0;
            var p = shiftDate(y, m, d, -1) as Lang.Array;
            y = p[0]; m = p[1]; d = p[2];
        }
        while (utcHour >= 24.0) {
            utcHour -= 24.0;
            var n = shiftDate(y, m, d,  1) as Lang.Array;
            y = n[0]; m = n[1]; d = n[2];
        }

        return [y, m, d, utcHour];
    }

    function daysSince2000Jan0(year, month, day, utcHour) {
        return 367.0 * year
            - Math.floor(7.0 * (year + Math.floor((month + 9.0) / 12.0)) / 4.0)
            + Math.floor(275.0 * month / 9.0)
            + day
            - 730530.0
            + utcHour / 24.0;
    }

    // ── Display formatting helpers ───────────────────────────────────────────

    // Two-digit string with leading zero (e.g. 7 → "07", 12 → "12").
    function twoDigits(n) {
        if (n < 10) { return "0" + n.toString(); }
        return n.toString();
    }

    // Convert a 24-hour clock hour to its displayed value, honouring the
    // user's time-format preference. In 12h mode 0 maps to 12 and 13..23
    // map to 1..11; in 24h mode the hour is returned unchanged.
    function displayHour(hour24, is12hMode) {
        if (!is12hMode) { return hour24; }
        var h = hour24 % 12;
        return (h == 0) ? 12 : h;
    }

    // Format an "HH:MM" clock string honouring the user's time-format
    // preference. Minute is always two digits. Hour leading zero stripped
    // in 12h mode only.
    function formatHourMin(hour24, min, is12hMode) {
        var h = displayHour(hour24, is12hMode);
        var hStr = is12hMode ? h.toString() : twoDigits(h);
        return hStr + ":" + twoDigits(min);
    }

}
