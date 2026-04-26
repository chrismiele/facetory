using Toybox.Math;

module Lunar {

    const PHASE_NEW = 0;
    const PHASE_WAXING_THIN_CRESCENT = 1;
    const PHASE_WAXING_THICK_CRESCENT = 2;
    const PHASE_FIRST_QUARTER = 3;
    const PHASE_WAXING_NEAR_HALF_GIBBOUS = 4;
    const PHASE_WAXING_NEAR_FULL_GIBBOUS = 5;
    const PHASE_FULL = 6;
    const PHASE_WANING_NEAR_FULL_GIBBOUS = 7;
    const PHASE_WANING_NEAR_HALF_GIBBOUS = 8;
    const PHASE_LAST_QUARTER = 9;
    const PHASE_WANING_THICK_CRESCENT = 10;
    const PHASE_WANING_THIN_CRESCENT = 11;

    const BLACK = 0x000000;
    const NEW_MOON_GREY = 0x0A142B;
    const MIP_MOON_BRIGHT = 0xFFFFFF;
    const MIP_MOON_MEDIUM = 0xAAAAAA;
    const MIP_MOON_DARK = 0x555555;
    const MIP_NEW_MOON_BRIGHT = 0x000055;

    const MOON_GLOW_DEG = 45.0;
    const MOON_RING_THICKNESS_DEG = 15.0;
    const MIP_MOON_RING_THICKNESS_DEG = 3.0;
    const SUN_GLOW_CUTOFF_DEG = 18.0;
    const MAX_MOON_GLOW_BRIGHTNESS = 0.5;
    const INNER_MOON_GLOW_BRIGHTNESS_SCALE = 0.5;

    const GIBBOUS_TERM_FRAC_NEAR_HALF = 0.5;
    const GIBBOUS_TERM_FRAC_NEAR_FULL = 0.8;

    const CRESCENT_SHIFT_DEG_THIN = 2.5;
    const CRESCENT_SHIFT_DEG_THICK = 4.0;
    const CRESCENT_BLACK_FRAC_THIN = 1.1;
    const CRESCENT_BLACK_FRAC_THICK = 1.0;

    const GIBBOUS_BIN_COUNT = 4;
    const HALF_BIN_COUNT = 8;
    const CRESCENT_BIN_COUNT = 12;
    const PHASE_BIN_COUNT = 12;

    const GIBBOUS_HYST_DEG = 10.0;
    const HALF_HYST_DEG = 6.0;
    const CRESCENT_HYST_DEG = 4.0;
    const PHASE_HYST_DEG = 2.0;

    const ORIENT_RIGHT = 0;
    const ORIENT_DOWN = 1;
    const ORIENT_LEFT = 2;
    const ORIENT_UP = 3;

    const SYNODIC_MONTH_DAYS = 29.530588;
    const FULL_MOON_WINDOW_HOURS = 48.0;
    const FULL_MOON_WINDOW_DEG = 360.0*FULL_MOON_WINDOW_HOURS/(24.0*SYNODIC_MONTH_DAYS);

    var _prevGibbousBin = -1;
    var _prevHalfBin = -1;
    var _prevCrescentBin = -1;
    var _prevPhaseBin = -1;

    function lunarAltAzApprox(year, month, day, clockHour, offsetSec, latDeg, lonDeg) {
        var utc = utcFromLocal(year, month, day, clockHour, offsetSec);
        var y = utc[0];
        var m = utc[1];
        var d0 = utc[2];
        var utcHour = utc[3];

        var d = daysSince2000Jan0(y, m, d0, utcHour);

        var N = wrap360(125.1228 - 0.0529538083*d);
        var i = 5.1454;
        var w = wrap360(318.0634 + 0.1643573223*d);
        var a = 60.2666;
        var e = 0.054900;
        var M = wrap360(115.3654 + 13.0649929509*d);

        var E = M + rad2deg(e*Math.sin(deg2rad(M))*(1.0 + e*Math.cos(deg2rad(M))));
        var xv = a*(Math.cos(deg2rad(E)) - e);
        var yv = a*(Math.sqrt(1.0 - e*e)*Math.sin(deg2rad(E)));

        var v = rad2deg(Math.atan2(yv, xv));
        var r = Math.sqrt(xv*xv + yv*yv);

        var xh = r*(cosDeg(N)*cosDeg(v + w) - sinDeg(N)*sinDeg(v + w)*cosDeg(i));
        var yh = r*(sinDeg(N)*cosDeg(v + w) + cosDeg(N)*sinDeg(v + w)*cosDeg(i));
        var zh = r*sinDeg(v + w)*sinDeg(i);

        var lonecl = rad2deg(Math.atan2(yh, xh));
        var latecl = rad2deg(Math.atan2(zh, Math.sqrt(xh*xh + yh*yh)));

        var Ms = wrap360(356.0470 + 0.9856002585*d);
        var ws = wrap360(282.9404 + 0.0000470935*d);
        var Ls = wrap360(Ms + ws);
        var Lm = wrap360(N + w + M);
        var D = wrap180(Lm - Ls);
        var F = wrap180(Lm - N);

        lonecl += -1.274*sinDeg(M - 2.0*D)
               +  0.658*sinDeg(2.0*D)
               -  0.186*sinDeg(Ms)
               -  0.059*sinDeg(2.0*M - 2.0*D)
               -  0.057*sinDeg(M - 2.0*D + Ms)
               +  0.053*sinDeg(M + 2.0*D)
               +  0.046*sinDeg(2.0*D - Ms)
               +  0.041*sinDeg(M - Ms)
               -  0.035*sinDeg(D)
               -  0.031*sinDeg(M + Ms)
               -  0.015*sinDeg(2.0*F - 2.0*D)
               +  0.011*sinDeg(M - 4.0*D);

        latecl += -0.173*sinDeg(F - 2.0*D)
               -  0.055*sinDeg(M - F - 2.0*D)
               -  0.046*sinDeg(M + F - 2.0*D)
               +  0.033*sinDeg(F + 2.0*D)
               +  0.017*sinDeg(2.0*M + F);

        var eps = 23.4393 - 0.0000003563*d;

        var xe = cosDeg(lonecl)*cosDeg(latecl);
        var ye = sinDeg(lonecl)*cosDeg(latecl);
        var ze = sinDeg(latecl);

        var xeq = xe;
        var yeq = ye*cosDeg(eps) - ze*sinDeg(eps);
        var zeq = ye*sinDeg(eps) + ze*cosDeg(eps);

        var raDeg = wrap360(rad2deg(Math.atan2(yeq, xeq)));
        var decDeg = rad2deg(Math.atan2(zeq, Math.sqrt(xeq*xeq + yeq*yeq)));

        var gmst0 = wrap360(Ls + 180.0);
        var lst = wrap360(gmst0 + utcHour*15.0 + lonDeg);
        var H = wrap180(lst - raDeg);

        var lat = deg2rad(latDeg);
        var dec = deg2rad(decDeg);
        var Hr = deg2rad(H);

        var sinAlt = Math.sin(lat)*Math.sin(dec) + Math.cos(lat)*Math.cos(dec)*Math.cos(Hr);
        sinAlt = clamp(sinAlt, -1.0, 1.0);

        var alt = Math.asin(sinAlt);
        var altDeg = rad2deg(alt);

        var cosAlt = Math.cos(alt);
        if (abs(cosAlt) < 1e-6) {
            cosAlt = (cosAlt < 0.0) ? -1e-6 : 1e-6;
        }

        var cosAz;
        if (abs(cosAlt) < 1e-6) {
            cosAz = 1.0;
        } else {
            cosAz = (Math.sin(dec) - Math.sin(alt)*Math.sin(lat)) / (cosAlt*Math.cos(lat));
            cosAz = clamp(cosAz, -1.0, 1.0);
        }

        var az = Math.acos(cosAz);
        if (Math.sin(Hr) > 0.0) {
            az = 2.0*Math.PI - az;
        }

        var parallaxDeg = rad2deg(Math.asin(1.0/r));
        altDeg -= parallaxDeg*Math.cos(alt);
        altDeg += refractionDeg(altDeg);

        if (90.0 - altDeg < 0.1) {
            return [altDeg, 0.0];
        }

        return [altDeg, rad2deg(az)];
    }

    function refractionDeg(altDeg) {
        if (altDeg < -4.0) {
            return 0.0;
        }

        return 1.02/(60.0*Math.tan(deg2rad(altDeg + 10.3/(altDeg + 5.11))));
    }

    function lunarPhaseBin(year, month, day, clockHour, offsetSec) {
        return lunarPhaseBinFromAngle(lunarPhaseAngle(year, month, day, clockHour, offsetSec));
    }

    function lunarPhaseBinFromAngle(phaseAngle) {
        _prevPhaseBin = stickyBin(phaseAngle, _prevPhaseBin, PHASE_BIN_COUNT, PHASE_HYST_DEG);
        return _prevPhaseBin;
    }

    function resetOrientationBins() {
        _prevGibbousBin = -1;
        _prevHalfBin = -1;
        _prevCrescentBin = -1;
    }

    function resetHalfAndCrescentBins() {
        _prevHalfBin = -1;
        _prevCrescentBin = -1;
    }

    function resetGibbousAndCrescentBins() {
        _prevGibbousBin = -1;
        _prevCrescentBin = -1;
    }

    function resetGibbousAndHalfBins() {
        _prevGibbousBin = -1;
        _prevHalfBin = -1;
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

    function lunarPhaseAngle(year, month, day, clockHour, offsetSec) {
        var utc = utcFromLocal(year, month, day, clockHour, offsetSec);
        var y = utc[0];
        var m = utc[1];
        var d0 = utc[2];
        var utcHour = utc[3];

        var d = daysSince2000Jan0(y, m, d0, utcHour);

        var N = wrap360(125.1228 - 0.0529538083*d);
        var w = wrap360(318.0634 + 0.1643573223*d);
        var M = wrap360(115.3654 + 13.0649929509*d);

        var Ms = wrap360(356.0470 + 0.9856002585*d);
        var ws = wrap360(282.9404 + 0.0000470935*d);
        var Ls = wrap360(Ms + ws);
        var Lm = wrap360(N + w + M);
        var D = wrap180(Lm - Ls);
        var F = wrap180(Lm - N);

        var lonecl = wrap360(N + w + M);

        lonecl += -1.274*sinDeg(M - 2.0*D)
               +  0.658*sinDeg(2.0*D)
               -  0.186*sinDeg(Ms)
               -  0.059*sinDeg(2.0*M - 2.0*D)
               -  0.057*sinDeg(M - 2.0*D + Ms)
               +  0.053*sinDeg(M + 2.0*D)
               +  0.046*sinDeg(2.0*D - Ms)
               +  0.041*sinDeg(M - Ms)
               -  0.035*sinDeg(D)
               -  0.031*sinDeg(M + Ms)
               -  0.015*sinDeg(2.0*F - 2.0*D)
               +  0.011*sinDeg(M - 4.0*D);

        var sunLon = wrap360(Ls + 1.915*sinDeg(Ms) + 0.020*sinDeg(2.0*Ms));
        return wrap360(lonecl - sunLon);
    }

    function moonFrame(x, y, sunX, sunY) {
        var ux = sunX - x;
        var uy = sunY - y;
        var un = Math.sqrt(ux*ux + uy*uy);

        if (un < 1e-6) {
            ux = 1.0;
            uy = 0.0;
            un = 1.0;
        }

        ux /= un;
        uy /= un;

        return [ux, uy];
    }

    function stickyBin(angleDeg, prevBin, binCount, hystDeg) {
        var step = 360.0/binCount.toFloat();
        var halfStep = 0.5*step;

        if (prevBin >= 0 && prevBin < binCount) {
            var prevCenter = prevBin.toFloat()*step;
            if (abs(wrap180(angleDeg - prevCenter)) <= halfStep + hystDeg) {
                return prevBin;
            }
        }

        var bin = Math.floor((wrap360(angleDeg) + halfStep)/step).toNumber();
        if (bin >= binCount) {
            bin = 0;
        }
        return bin;
    }

    function binDirection(bin, binCount) {
        var step = 360.0/binCount.toFloat();
        var ang = deg2rad(bin.toFloat()*step);
        return [Math.cos(ang), Math.sin(ang)];
    }

    function blendColor(c0, c1, t) {
        t = clamp(t, 0.0, 1.0);

        var r0 = (c0/65536) % 256;
        var g0 = (c0/256) % 256;
        var b0 = c0 % 256;

        var r1 = (c1/65536) % 256;
        var g1 = (c1/256) % 256;
        var b1 = c1 % 256;

        var r = (r0 + (r1 - r0)*t).toNumber();
        var g = (g0 + (g1 - g0)*t).toNumber();
        var b = (b0 + (b1 - b0)*t).toNumber();

        return r*65536 + g*256 + b;
    }

    function roundNearest(x) {
        if (x >= 0.0) {
            return (x + 0.5).toNumber();
        }
        return (x - 0.5).toNumber();
    }

    function daysInMonth(year, month) {
        if (month == 1 || month == 3 || month == 5 || month == 7 ||
            month == 8 || month == 10 || month == 12) {
            return 31;
        }

        if (month == 4 || month == 6 || month == 9 || month == 11) {
            return 30;
        }

        return isLeapYear(year) ? 29 : 28;
    }

    function shiftDate(year, month, day, delta) {
        var y = year;
        var m = month;
        var d = day + delta;

        if (delta < 0) {
            if (d < 1) {
                m -= 1;
                if (m < 1) {
                    m = 12;
                    y -= 1;
                }
                d = daysInMonth(y, m);
            }
        } else if (delta > 0) {
            var dim = daysInMonth(y, m);
            if (d > dim) {
                d = 1;
                m += 1;
                if (m > 12) {
                    m = 1;
                    y += 1;
                }
            }
        }

        return [y, m, d];
    }

    function utcFromLocal(year, month, day, clockHour, offsetSec) {
        var utcHour = clockHour - offsetSec/3600.0;
        var y = year;
        var m = month;
        var d = day;

        while (utcHour < 0.0) {
            utcHour += 24.0;
            var prev = shiftDate(y, m, d, -1);
            y = prev[0];
            m = prev[1];
            d = prev[2];
        }

        while (utcHour >= 24.0) {
            utcHour -= 24.0;
            var next = shiftDate(y, m, d, 1);
            y = next[0];
            m = next[1];
            d = next[2];
        }

        return [y, m, d, utcHour];
    }

    function daysSince2000Jan0(year, month, day, utcHour) {
        return 367.0*year
            - Math.floor(7.0*(year + Math.floor((month + 9.0)/12.0))/4.0)
            + Math.floor(275.0*month/9.0)
            + day
            - 730530.0
            + utcHour/24.0;
    }

    function isLeapYear(year) {
        if ((year % 400) == 0) { return true; }
        if ((year % 100) == 0) { return false; }
        return ((year % 4) == 0);
    }

    function clamp(x, lo, hi) {
        if (x < lo) { return lo; }
        if (x > hi) { return hi; }
        return x;
    }

    function abs(x) {
        if (x < 0.0) { return -x; }
        return x;
    }

    function wrap360(x) {
        while (x < 0.0) { x += 360.0; }
        while (x >= 360.0) { x -= 360.0; }
        return x;
    }

    function wrap180(x) {
        while (x < -180.0) { x += 360.0; }
        while (x >= 180.0) { x -= 360.0; }
        return x;
    }

    function sinDeg(x) {
        return Math.sin(deg2rad(x));
    }

    function cosDeg(x) {
        return Math.cos(deg2rad(x));
    }

    function deg2rad(x) {
        return x*Math.PI/180.0;
    }

    function rad2deg(x) {
        return x*180.0/Math.PI;
    }
}