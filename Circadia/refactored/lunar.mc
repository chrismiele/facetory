using Toybox.Math;

module Lunar {

    const PHASE_NEW                    = 0;
    const PHASE_WAXING_THIN_CRESCENT   = 1;
    const PHASE_WAXING_THICK_CRESCENT  = 2;
    const PHASE_FIRST_QUARTER          = 3;
    const PHASE_WAXING_NEAR_HALF_GIBBOUS  = 4;
    const PHASE_WAXING_NEAR_FULL_GIBBOUS  = 5;
    const PHASE_FULL                   = 6;
    const PHASE_WANING_NEAR_FULL_GIBBOUS  = 7;
    const PHASE_WANING_NEAR_HALF_GIBBOUS  = 8;
    const PHASE_LAST_QUARTER           = 9;
    const PHASE_WANING_THICK_CRESCENT  = 10;
    const PHASE_WANING_THIN_CRESCENT   = 11;

    const BLACK            = 0x000000;
    const MIP_NEW_MOON_BRIGHT = 0x000055;

    const GIBBOUS_TERM_FRAC_NEAR_HALF = 0.5;
    const GIBBOUS_TERM_FRAC_NEAR_FULL = 0.8;

    const CRESCENT_SHIFT_DEG_THIN  = 2.5;
    const CRESCENT_SHIFT_DEG_THICK = 4.0;
    const CRESCENT_BLACK_FRAC_THIN  = 1.1;
    const CRESCENT_BLACK_FRAC_THICK = 1.0;

    const GIBBOUS_BIN_COUNT = 4;
    const HALF_BIN_COUNT    = 8;
    const CRESCENT_BIN_COUNT = 12;
    const PHASE_BIN_COUNT   = 12;

    const GIBBOUS_HYST_DEG  = 10.0;
    const HALF_HYST_DEG     = 6.0;
    const CRESCENT_HYST_DEG = 4.0;
    const PHASE_HYST_DEG    = 2.0;

    const ORIENT_RIGHT = 0;
    const ORIENT_DOWN  = 1;
    const ORIENT_LEFT  = 2;
    const ORIENT_UP    = 3;

    const SYNODIC_MONTH_DAYS    = 29.530588;
    const FULL_MOON_WINDOW_HOURS = 48.0;
    const FULL_MOON_WINDOW_DEG  = 360.0 * FULL_MOON_WINDOW_HOURS / (24.0 * SYNODIC_MONTH_DAYS);

    var _prevGibbousBin  = -1;
    var _prevHalfBin     = -1;
    var _prevCrescentBin = -1;
    var _prevPhaseBin    = -1;

    function lunarAltAzApprox(year, month, day, clockHour, offsetSec, latDeg, lonDeg) {
        var utc     = utcFromLocal(year, month, day, clockHour, offsetSec);
        var d       = daysSince2000Jan0(utc[0], utc[1], utc[2], utc[3]);
        var utcHour = utc[3];

        var N = wrap360(125.1228  - 0.0529538083  * d);
        var i = 5.1454;
        var w = wrap360(318.0634  + 0.1643573223  * d);
        var a = 60.2666;
        var e = 0.054900;
        var M = wrap360(115.3654  + 13.0649929509 * d);

        var E  = M + rad2deg(e * Math.sin(deg2rad(M)) * (1.0 + e * Math.cos(deg2rad(M))));
        var xv = a * (Math.cos(deg2rad(E)) - e);
        var yv = a * (Math.sqrt(1.0 - e * e) * Math.sin(deg2rad(E)));

        var v  = rad2deg(Math.atan2(yv, xv));
        var r  = Math.sqrt(xv * xv + yv * yv);
        var vw = v + w;

        var xh = r * (cosDeg(N) * cosDeg(vw) - sinDeg(N) * sinDeg(vw) * cosDeg(i));
        var yh = r * (sinDeg(N) * cosDeg(vw) + cosDeg(N) * sinDeg(vw) * cosDeg(i));
        var zh = r * sinDeg(vw) * sinDeg(i);

        var lonecl = rad2deg(Math.atan2(yh, xh));
        var latecl = rad2deg(Math.atan2(zh, Math.sqrt(xh * xh + yh * yh)));

        var Ms = wrap360(356.0470 + 0.9856002585 * d);
        var ws = wrap360(282.9404 + 0.0000470935 * d);
        var Ls = wrap360(Ms + ws);
        var Lm = wrap360(N + w + M);
        var D  = wrap180(Lm - Ls);
        var F  = wrap180(Lm - N);

        lonecl += lunarLonCorrections(M, D, Ms, F);
        latecl += lunarLatCorrections(M, F, D);

        var eps = 23.4393 - 0.0000003563 * d;

        var xe  = cosDeg(lonecl) * cosDeg(latecl);
        var ye  = sinDeg(lonecl) * cosDeg(latecl);
        var ze  = sinDeg(latecl);
        var xeq = xe;
        var yeq = ye * cosDeg(eps) - ze * sinDeg(eps);
        var zeq = ye * sinDeg(eps) + ze * cosDeg(eps);

        var raDeg  = wrap360(rad2deg(Math.atan2(yeq, xeq)));
        var decDeg = rad2deg(Math.atan2(zeq, Math.sqrt(xeq * xeq + yeq * yeq)));

        var gmst0 = wrap360(Ls + 180.0);
        var lst   = wrap360(gmst0 + utcHour * 15.0 + lonDeg);
        var H     = wrap180(lst - raDeg);

        var lat    = deg2rad(latDeg);
        var dec    = deg2rad(decDeg);
        var Hr     = deg2rad(H);

        var sinAlt = clamp(Math.sin(lat) * Math.sin(dec) + Math.cos(lat) * Math.cos(dec) * Math.cos(Hr), -1.0, 1.0);
        var alt    = Math.asin(sinAlt);
        var altDeg = rad2deg(alt);

        var cosAlt = Math.cos(alt);
        if (abs(cosAlt) < 1e-6) { cosAlt = (cosAlt < 0.0) ? -1e-6 : 1e-6; }

        var cosAz = clamp((Math.sin(dec) - sinAlt * Math.sin(lat)) / (cosAlt * Math.cos(lat)), -1.0, 1.0);
        var az    = Math.acos(cosAz);
        if (Math.sin(Hr) > 0.0) { az = 2.0 * Math.PI - az; }

        var parallaxDeg = rad2deg(Math.asin(1.0 / r));
        altDeg = altDeg - parallaxDeg * Math.cos(alt) + refractionDeg(altDeg);

        if (90.0 - altDeg < 0.1) { return [altDeg, 0.0]; }
        return [altDeg, rad2deg(az)];
    }

    // Extracted perturbation tables to keep lunarAltAzApprox readable
    function lunarLonCorrections(M, D, Ms, F) {
        return -1.274 * sinDeg(M - 2.0 * D)
               + 0.658 * sinDeg(2.0 * D)
               - 0.186 * sinDeg(Ms)
               - 0.059 * sinDeg(2.0 * M - 2.0 * D)
               - 0.057 * sinDeg(M - 2.0 * D + Ms)
               + 0.053 * sinDeg(M + 2.0 * D)
               + 0.046 * sinDeg(2.0 * D - Ms)
               + 0.041 * sinDeg(M - Ms)
               - 0.035 * sinDeg(D)          // D correction (not M - something)
               - 0.031 * sinDeg(M + Ms)
               - 0.015 * sinDeg(2.0 * F - 2.0 * D)
               + 0.011 * sinDeg(M - 4.0 * D);
    }

    function lunarLatCorrections(M, F, D) {
        return -0.173 * sinDeg(F - 2.0 * D)
               - 0.055 * sinDeg(M - F - 2.0 * D)
               - 0.046 * sinDeg(M + F - 2.0 * D)
               + 0.033 * sinDeg(F + 2.0 * D)
               + 0.017 * sinDeg(2.0 * M + F);
    }

    function refractionDeg(altDeg) {
        if (altDeg < -4.0) { return 0.0; }
        return 1.02 / (60.0 * Math.tan(deg2rad(altDeg + 10.3 / (altDeg + 5.11))));
    }

    function lunarPhaseBinFromAngle(phaseAngle) {
        _prevPhaseBin = stickyBin(phaseAngle, _prevPhaseBin, PHASE_BIN_COUNT, PHASE_HYST_DEG);
        return _prevPhaseBin;
    }

    function lunarPhaseAngle(year, month, day, clockHour, offsetSec) {
        var utc = utcFromLocal(year, month, day, clockHour, offsetSec);
        var d   = daysSince2000Jan0(utc[0], utc[1], utc[2], utc[3]);

        var N  = wrap360(125.1228  - 0.0529538083  * d);
        var w  = wrap360(318.0634  + 0.1643573223  * d);
        var M  = wrap360(115.3654  + 13.0649929509 * d);
        var Ms = wrap360(356.0470  + 0.9856002585  * d);
        var ws = wrap360(282.9404  + 0.0000470935  * d);
        var Ls = wrap360(Ms + ws);
        var Lm = wrap360(N + w + M);
        var D  = wrap180(Lm - Ls);
        var F  = wrap180(Lm - N);

        var lonecl = wrap360(Lm) + lunarLonCorrections(M, D, Ms, F);
        var sunLon = wrap360(Ls + 1.915 * sinDeg(Ms) + 0.020 * sinDeg(2.0 * Ms));
        return wrap360(lonecl - sunLon);
    }

    // ── Orientation bin management ───────────────────────────────────────────

    function resetOrientationBins() {
        _prevGibbousBin  = -1;
        _prevHalfBin     = -1;
        _prevCrescentBin = -1;
    }

    function resetHalfAndCrescentBins() {
        _prevHalfBin     = -1;
        _prevCrescentBin = -1;
    }

    function resetGibbousAndCrescentBins() {
        _prevGibbousBin  = -1;
        _prevCrescentBin = -1;
    }

    function resetGibbousAndHalfBins() {
        _prevGibbousBin = -1;
        _prevHalfBin    = -1;
    }

    function moonOrientationAngle(x, y, sunX, sunY) {
        var frame = moonFrame(x, y, sunX, sunY);
        return wrap360(rad2deg(Math.atan2(frame[1], frame[0])));
    }

    function gibbousOrientationBin(angle) {
        _prevGibbousBin = stickyBin(angle, _prevGibbousBin, GIBBOUS_BIN_COUNT, GIBBOUS_HYST_DEG);
        return _prevGibbousBin;
    }

    function halfOrientationVector(angle) {
        _prevHalfBin = stickyBin(angle, _prevHalfBin, HALF_BIN_COUNT, HALF_HYST_DEG);
        return binDirection(_prevHalfBin, HALF_BIN_COUNT);
    }

    function crescentOrientationVector(angle) {
        _prevCrescentBin = stickyBin(angle, _prevCrescentBin, CRESCENT_BIN_COUNT, CRESCENT_HYST_DEG);
        return binDirection(_prevCrescentBin, CRESCENT_BIN_COUNT);
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    function moonFrame(x, y, sunX, sunY) {
        var ux = sunX - x;
        var uy = sunY - y;
        var un = Math.sqrt(ux * ux + uy * uy);
        if (un < 1e-6) { return [1.0, 0.0]; }
        return [ux / un, uy / un];
    }

    function stickyBin(angleDeg, prevBin, binCount, hystDeg) {
        var step     = 360.0 / binCount.toFloat();
        var halfStep = 0.5 * step;

        if (prevBin >= 0 && prevBin < binCount) {
            if (abs(wrap180(angleDeg - prevBin.toFloat() * step)) <= halfStep + hystDeg) {
                return prevBin;
            }
        }

        var bin = Math.floor((wrap360(angleDeg) + halfStep) / step).toNumber();
        return (bin >= binCount) ? 0 : bin;
    }

    function binDirection(bin, binCount) {
        var ang = deg2rad(bin.toFloat() * 360.0 / binCount.toFloat());
        return [Math.cos(ang), Math.sin(ang)];
    }

    function blendColor(c0, c1, t) {
        t = clamp(t, 0.0, 1.0);
        var r = ((c0 / 65536) % 256 + ((c1 / 65536) % 256 - (c0 / 65536) % 256) * t).toNumber();
        var g = ((c0 / 256)   % 256 + ((c1 / 256)   % 256 - (c0 / 256)   % 256) * t).toNumber();
        var b = ( c0          % 256 + ( c1           % 256 -  c0          % 256) * t).toNumber();
        return r * 65536 + g * 256 + b;
    }

    function roundNearest(x) {
        return (x >= 0.0) ? (x + 0.5).toNumber() : (x - 0.5).toNumber();
    }

    // ── Date utilities ───────────────────────────────────────────────────────

    function daysInMonth(year, month) {
        if (month == 2) { return isLeapYear(year) ? 29 : 28; }
        // Months with 30 days: Apr(4), Jun(6), Sep(9), Nov(11)
        if (month == 4 || month == 6 || month == 9 || month == 11) { return 30; }
        return 31;
    }

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

    function utcFromLocal(year, month, day, clockHour, offsetSec) {
        var utcHour = clockHour - offsetSec / 3600.0;
        var y = year;
        var m = month;
        var d = day;

        while (utcHour < 0.0)   { utcHour += 24.0; var p = shiftDate(y, m, d, -1); y = p[0]; m = p[1]; d = p[2]; }
        while (utcHour >= 24.0) { utcHour -= 24.0; var n = shiftDate(y, m, d,  1); y = n[0]; m = n[1]; d = n[2]; }

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

    function isLeapYear(year) {
        if ((year % 400) == 0) { return true; }
        if ((year % 100) == 0) { return false; }
        return ((year % 4) == 0);
    }

    // ── Math helpers ─────────────────────────────────────────────────────────

    function clamp(x, lo, hi) {
        if (x < lo) { return lo; }
        if (x > hi) { return hi; }
        return x;
    }

    function abs(x)     { return (x < 0.0) ? -x : x; }
    function sinDeg(x)  { return Math.sin(deg2rad(x)); }
    function cosDeg(x)  { return Math.cos(deg2rad(x)); }
    function deg2rad(x) { return x * Math.PI / 180.0; }
    function rad2deg(x) { return x * 180.0 / Math.PI; }

    function wrap360(x) {
        while (x < 0.0)    { x += 360.0; }
        while (x >= 360.0) { x -= 360.0; }
        return x;
    }

    function wrap180(x) {
        while (x < -180.0) { x += 360.0; }
        while (x >= 180.0) { x -= 360.0; }
        return x;
    }
}
