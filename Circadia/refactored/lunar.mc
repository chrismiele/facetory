using Toybox.Math;

module Lunar {

    const PHASE_NEW                       = 0;
    const PHASE_WAXING_THIN_CRESCENT      = 1;
    const PHASE_WAXING_THICK_CRESCENT     = 2;
    const PHASE_FIRST_QUARTER             = 3;
    const PHASE_WAXING_NEAR_HALF_GIBBOUS  = 4;
    const PHASE_WAXING_NEAR_FULL_GIBBOUS  = 5;
    const PHASE_FULL                      = 6;
    const PHASE_WANING_NEAR_FULL_GIBBOUS  = 7;
    const PHASE_WANING_NEAR_HALF_GIBBOUS  = 8;
    const PHASE_LAST_QUARTER              = 9;
    const PHASE_WANING_THICK_CRESCENT     = 10;
    const PHASE_WANING_THIN_CRESCENT      = 11;

    const BLACK              = 0x000000;
    const MIP_NEW_MOON_BRIGHT = 0x000055;

    const GIBBOUS_TERM_FRAC_NEAR_HALF = 0.5;
    const GIBBOUS_TERM_FRAC_NEAR_FULL = 0.8;

    const CRESCENT_SHIFT_DEG_THIN   = 2.5;
    const CRESCENT_SHIFT_DEG_THICK  = 4.0;
    const CRESCENT_BLACK_FRAC_THIN  = 1.1;
    const CRESCENT_BLACK_FRAC_THICK = 1.0;

    const GIBBOUS_BIN_COUNT  = 4;
    const HALF_BIN_COUNT     = 8;
    const CRESCENT_BIN_COUNT = 12;
    const PHASE_BIN_COUNT    = 12;

    const GIBBOUS_HYST_DEG  = 10.0;
    const HALF_HYST_DEG     =  6.0;
    const CRESCENT_HYST_DEG =  4.0;
    const PHASE_HYST_DEG    =  2.0;

    const ORIENT_RIGHT = 0;
    const ORIENT_DOWN  = 1;
    const ORIENT_LEFT  = 2;
    const ORIENT_UP    = 3;

    const SYNODIC_MONTH_DAYS     = 29.530588;
    const FULL_MOON_WINDOW_HOURS = 48.0;
    const FULL_MOON_WINDOW_DEG   = 360.0 * FULL_MOON_WINDOW_HOURS / (24.0 * SYNODIC_MONTH_DAYS);

    var _prevGibbousBin  = -1;
    var _prevHalfBin     = -1;
    var _prevCrescentBin = -1;
    var _prevPhaseBin    = -1;

    function lunarAltAzApprox(year, month, day, clockHour, offsetSec, latDeg, lonDeg) {
        var utc     = MathUtil.utcFromLocal(year, month, day, clockHour, offsetSec);
        var d       = MathUtil.daysSince2000Jan0(utc[0], utc[1], utc[2], utc[3]);
        var utcHour = utc[3];

        var N = MathUtil.wrap360(125.1228  - 0.0529538083  * d);
        var i = 5.1454;
        var w = MathUtil.wrap360(318.0634  + 0.1643573223  * d);
        var a = 60.2666;
        var e = 0.054900;
        var M = MathUtil.wrap360(115.3654  + 13.0649929509 * d);

        var E  = M + MathUtil.rad2deg(e * Math.sin(MathUtil.deg2rad(M)) * (1.0 + e * Math.cos(MathUtil.deg2rad(M))));
        var xv = a * (Math.cos(MathUtil.deg2rad(E)) - e);
        var yv = a * (Math.sqrt(1.0 - e * e) * Math.sin(MathUtil.deg2rad(E)));

        var v  = MathUtil.rad2deg(Math.atan2(yv, xv));
        var r  = Math.sqrt(xv * xv + yv * yv);
        var vw = v + w;

        var xh = r * (MathUtil.cosDeg(N) * MathUtil.cosDeg(vw) - MathUtil.sinDeg(N) * MathUtil.sinDeg(vw) * MathUtil.cosDeg(i));
        var yh = r * (MathUtil.sinDeg(N) * MathUtil.cosDeg(vw) + MathUtil.cosDeg(N) * MathUtil.sinDeg(vw) * MathUtil.cosDeg(i));
        var zh = r * MathUtil.sinDeg(vw) * MathUtil.sinDeg(i);

        var lonecl = MathUtil.rad2deg(Math.atan2(yh, xh));
        var latecl = MathUtil.rad2deg(Math.atan2(zh, Math.sqrt(xh * xh + yh * yh)));

        var Ms = MathUtil.wrap360(356.0470 + 0.9856002585 * d);
        var ws = MathUtil.wrap360(282.9404 + 0.0000470935 * d);
        var Ls = MathUtil.wrap360(Ms + ws);
        var Lm = MathUtil.wrap360(N + w + M);
        var D  = MathUtil.wrap180(Lm - Ls);
        var F  = MathUtil.wrap180(Lm - N);

        lonecl += lunarLonCorrections(M, D, Ms, F);
        latecl += lunarLatCorrections(M, F, D);

        var eps = 23.4393 - 0.0000003563 * d;

        var xe  = MathUtil.cosDeg(lonecl) * MathUtil.cosDeg(latecl);
        var ye  = MathUtil.sinDeg(lonecl) * MathUtil.cosDeg(latecl);
        var ze  = MathUtil.sinDeg(latecl);
        var xeq = xe;
        var yeq = ye * MathUtil.cosDeg(eps) - ze * MathUtil.sinDeg(eps);
        var zeq = ye * MathUtil.sinDeg(eps) + ze * MathUtil.cosDeg(eps);

        var raDeg  = MathUtil.wrap360(MathUtil.rad2deg(Math.atan2(yeq, xeq)));
        var decDeg = MathUtil.rad2deg(Math.atan2(zeq, Math.sqrt(xeq * xeq + yeq * yeq)));

        var gmst0 = MathUtil.wrap360(Ls + 180.0);
        var lst   = MathUtil.wrap360(gmst0 + utcHour * 15.0 + lonDeg);
        var H     = MathUtil.wrap180(lst - raDeg);

        var lat = MathUtil.deg2rad(latDeg);
        var dec = MathUtil.deg2rad(decDeg);
        var Hr  = MathUtil.deg2rad(H);

        var sinAlt = MathUtil.clamp(Math.sin(lat) * Math.sin(dec) + Math.cos(lat) * Math.cos(dec) * Math.cos(Hr), -1.0, 1.0);
        var alt    = Math.asin(sinAlt);
        var altDeg = MathUtil.rad2deg(alt);

        var cosAlt = Math.cos(alt);
        if (MathUtil.abs(cosAlt) < 1e-6) { cosAlt = (cosAlt < 0.0) ? -1e-6 : 1e-6; }

        var cosAz = MathUtil.clamp((Math.sin(dec) - sinAlt * Math.sin(lat)) / (cosAlt * Math.cos(lat)), -1.0, 1.0);
        var az    = Math.acos(cosAz);
        if (Math.sin(Hr) > 0.0) { az = 2.0 * Math.PI - az; }

        var parallaxDeg = MathUtil.rad2deg(Math.asin(1.0 / r));
        altDeg = altDeg - parallaxDeg * Math.cos(alt) + MathUtil.refractionDeg(altDeg);

        if (90.0 - altDeg < 0.1) { return [altDeg, 0.0]; }
        return [altDeg, MathUtil.rad2deg(az)];
    }

    // Extracted perturbation tables to keep lunarAltAzApprox readable.
    function lunarLonCorrections(M, D, Ms, F) {
        return -1.274 * MathUtil.sinDeg(M - 2.0 * D)
               + 0.658 * MathUtil.sinDeg(2.0 * D)
               - 0.186 * MathUtil.sinDeg(Ms)
               - 0.059 * MathUtil.sinDeg(2.0 * M - 2.0 * D)
               - 0.057 * MathUtil.sinDeg(M - 2.0 * D + Ms)
               + 0.053 * MathUtil.sinDeg(M + 2.0 * D)
               + 0.046 * MathUtil.sinDeg(2.0 * D - Ms)
               + 0.041 * MathUtil.sinDeg(M - Ms)
               - 0.035 * MathUtil.sinDeg(D)
               - 0.031 * MathUtil.sinDeg(M + Ms)
               - 0.015 * MathUtil.sinDeg(2.0 * F - 2.0 * D)
               + 0.011 * MathUtil.sinDeg(M - 4.0 * D);
    }

    function lunarLatCorrections(M, F, D) {
        return -0.173 * MathUtil.sinDeg(F - 2.0 * D)
               - 0.055 * MathUtil.sinDeg(M - F - 2.0 * D)
               - 0.046 * MathUtil.sinDeg(M + F - 2.0 * D)
               + 0.033 * MathUtil.sinDeg(F + 2.0 * D)
               + 0.017 * MathUtil.sinDeg(2.0 * M + F);
    }

    function lunarPhaseBinFromAngle(phaseAngle) {
        _prevPhaseBin = stickyBin(phaseAngle, _prevPhaseBin, PHASE_BIN_COUNT, PHASE_HYST_DEG);
        return _prevPhaseBin;
    }

    function lunarPhaseAngle(year, month, day, clockHour, offsetSec) {
        var utc = MathUtil.utcFromLocal(year, month, day, clockHour, offsetSec);
        var d   = MathUtil.daysSince2000Jan0(utc[0], utc[1], utc[2], utc[3]);

        var N  = MathUtil.wrap360(125.1228  - 0.0529538083  * d);
        var w  = MathUtil.wrap360(318.0634  + 0.1643573223  * d);
        var M  = MathUtil.wrap360(115.3654  + 13.0649929509 * d);
        var Ms = MathUtil.wrap360(356.0470  + 0.9856002585  * d);
        var ws = MathUtil.wrap360(282.9404  + 0.0000470935  * d);
        var Ls = MathUtil.wrap360(Ms + ws);
        var Lm = MathUtil.wrap360(N + w + M);
        var D  = MathUtil.wrap180(Lm - Ls);
        var F  = MathUtil.wrap180(Lm - N);

        var lonecl = MathUtil.wrap360(Lm) + lunarLonCorrections(M, D, Ms, F);
        var sunLon = MathUtil.wrap360(Ls + 1.915 * MathUtil.sinDeg(Ms) + 0.020 * MathUtil.sinDeg(2.0 * Ms));
        return MathUtil.wrap360(lonecl - sunLon);
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
        return MathUtil.wrap360(MathUtil.rad2deg(Math.atan2(frame[1], frame[0])));
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
            if (MathUtil.abs(MathUtil.wrap180(angleDeg - prevBin.toFloat() * step)) <= halfStep + hystDeg) {
                return prevBin;
            }
        }

        var bin = Math.floor((MathUtil.wrap360(angleDeg) + halfStep) / step).toNumber();
        return (bin >= binCount) ? 0 : bin;
    }

    function binDirection(bin, binCount) {
        var ang = MathUtil.deg2rad(bin.toFloat() * 360.0 / binCount.toFloat());
        return [Math.cos(ang), Math.sin(ang)];
    }

}
