using Toybox.Graphics;
using Toybox.Math;

module Solar {

    const YELLOW = 0xFFFF00;
    const RED = 0xFF0000;
    const BLUE = 0x0000FF;
    const GREY = 0x8C939C;
    const BLACK = 0x000000;
    const WHITE = 0xFFFFFF;

    const COLOR_SATURATION = 1.0;
    const OUTER_GLOW_SCALE = 0.1;

    const SUNSET_ACCENT_COLOR = 0xFF8A00;
    const SUNSET_ACCENT_ALT_DEG = 1.5;
    const MONTH_OFFSETS = [0.0,31.0,59.0,90.0,120.0,151.0,181.0,212.0,243.0,273.0,304.0,334.0];

    var _colorsReady = false;
    var _satYellow;
    var _satRed;
    var _satBlue;
    var _satGrey;
    var _yellowRedMid;
    var _redBlueMid;
    var _redGreyMid;
    var _transparent;

    var _yellowGlowBitmap;
    var _yellowGlowR;
    var _yellowGlowDeg;
    var _yellowGlowSteps;
    var _yellowGlowRadiusPx;

    function solarAltAzApprox(year, month, day, clockHour, offsetSec, latDeg, lonDeg) {
        var doy = dayOfYear(year, month, day);
        var yearLen = isLeapYear(year) ? 366.0 : 365.0;

        var lat = deg2rad(latDeg);
        var sinLat = Math.sin(lat);
        var cosLat = Math.cos(lat);

        var gamma = 2.0*Math.PI/yearLen*(doy - 1.0 + (clockHour - 12.0)/24.0);

        var sg = Math.sin(gamma);
        var cg = Math.cos(gamma);
        var s2 = 2.0*sg*cg;
        var c2 = 2.0*cg*cg - 1.0;
        var s3 = s2*cg + c2*sg;
        var c3 = c2*cg - s2*sg;

        var eqtMin = 229.18*(0.000075 + 0.001868*cg
            - 0.032077*sg
            - 0.014615*c2
            - 0.040849*s2);

        var dec = 0.006918
            - 0.399912*cg
            + 0.070257*sg
            - 0.006758*c2
            + 0.000907*s2
            - 0.002697*c3
            + 0.00148*s3;

        var tzMeridianDeg = offsetSec/240.0;
        var solarHours = clockHour + (eqtMin + 4.0*(lonDeg - tzMeridianDeg))/60.0;
        var H = deg2rad(15.0*(solarHours - 12.0));

        var sinDec = Math.sin(dec);
        var cosDec = Math.cos(dec);
        var cosH = Math.cos(H);

        var sinAlt = sinLat*sinDec + cosLat*cosDec*cosH;
        sinAlt = clamp(sinAlt, -1.0, 1.0);

        var alt = Math.asin(sinAlt);
        var altDeg = rad2deg(alt);

        if (90.0 - altDeg < 0.1) {
            return [altDeg, 0.0];
        }

        var cosAlt = Math.cos(alt);
        if (abs(cosAlt) < 1e-6) {
            cosAlt = (cosAlt < 0.0) ? -1e-6 : 1e-6;
        }

        var cosAz = (sinDec - sinAlt*sinLat)/(cosAlt*cosLat);
        cosAz = clamp(cosAz, -1.0, 1.0);

        var az = Math.acos(cosAz);
        if (Math.sin(H) > 0.0) {
            az = 2.0*Math.PI - az;
        }

        return [altDeg, rad2deg(az)];
    }

    function projectAltAz(altDeg, azDeg, cx, cy, R) {
        var rho = R*(1.0 - altDeg/90.0);
        if (rho < 0.0) {
            rho = 0.0;
        }

        var az = deg2rad(azDeg);
        return [
            cx + rho*Math.sin(az),
            cy - rho*Math.cos(az)
        ];
    }

    function drawSunGlow(dc, x, y, cx, cy, R, sunColor, glowDeg, glowSteps) {
        ensureColorCache();

        if (sunColor == _satYellow && Toybox.Graphics has :createBufferedBitmap) {
            var bmp = getYellowGlowBitmap(R, glowDeg, glowSteps);
            if (bmp != null) {
                dc.drawBitmap(
                    x.toNumber() - _yellowGlowRadiusPx,
                    y.toNumber() - _yellowGlowRadiusPx,
                    bmp
                );
                return;
            }
        }

        drawSunGlowDirect(dc, x, y, cx, cy, R, sunColor, glowDeg, glowSteps);
    }

    function drawSunGlowDirect(dc, x, y, cx, cy, R, sunColor, glowDeg, glowSteps) {
        var glowPx = R*(glowDeg/90.0);
        var invSteps = 1.0/glowSteps.toFloat();
        var xi = x.toNumber();
        var yi = y.toNumber();

        var dx = xi - cx.toNumber();
        var dy = yi - cy.toNumber();
        var d = Math.sqrt(dx*dx + dy*dy);

        var outerGlowColor = scaleColor(sunColor, OUTER_GLOW_SCALE);

        for (var i = glowSteps; i >= 1; i -= 1) {
            var f = i.toFloat()*invSteps;
            var ri = (glowPx*f).toNumber();

            if (d - ri >= R) {
                continue;
            }

            dc.setColor(blendColor(outerGlowColor, sunColor, 1.0 - f), BLACK);
            dc.fillCircle(xi, yi, ri);
        }
    }

    function getYellowGlowBitmap(R, glowDeg, glowSteps) {
        if (_yellowGlowBitmap != null
            && _yellowGlowR == R
            && _yellowGlowDeg == glowDeg
            && _yellowGlowSteps == glowSteps) {
            return _yellowGlowBitmap;
        }

        var glowPx = R*(glowDeg/90.0);
        var maxRadius = (glowPx > R) ? glowPx : R;
        var radiusPx = maxRadius.toNumber() + 2;
        var size = 2*radiusPx + 1;

        var ref = Graphics.createBufferedBitmap({
            :width => size,
            :height => size,
            :alphaBlending => Graphics.ALPHA_BLENDING_FULL
        });

        if (ref == null) {
            return null;
        }

        var bmp = ref.get();
        if (bmp == null) {
            return null;
        }

        var bdc = bmp.getDc();

        if (_transparent == null) {
            _transparent = Graphics.createColor(0, 0, 0, 0);
        }

        bdc.setColor(BLACK, _transparent);
        bdc.clear();

        drawSunGlowDirect(bdc, radiusPx, radiusPx, radiusPx, radiusPx, R, _satYellow, glowDeg, glowSteps);

        _yellowGlowBitmap = bmp;
        _yellowGlowR = R;
        _yellowGlowDeg = glowDeg;
        _yellowGlowSteps = glowSteps;
        _yellowGlowRadiusPx = radiusPx;

        return _yellowGlowBitmap;
    }

    function sunColorForAlt(altDeg) {
        ensureColorCache();

        if (altDeg >= 18.0) {
            return _satYellow;
        }

        if (altDeg >= 6.0) {
            return blendColor(_satYellow, _yellowRedMid, (18.0 - altDeg)/12.0);
        }

        if (altDeg >= 0.0) {
            return blendColor(_yellowRedMid, _satRed, (6.0 - altDeg)/6.0);
        }

        if (altDeg >= -6.0) {
            return blendColor(_satRed, _redBlueMid, (-altDeg)/6.0);
        }

        if (altDeg >= -12.0) {
            return blendColor(_redBlueMid, _satBlue, (-6.0 - altDeg)/6.0);
        }

        return _satBlue;
    }

    function minuteColorForAlt(altDeg) {
        ensureColorCache();

        if (altDeg >= 18.0) {
            return _satYellow;
        }

        if (altDeg >= 6.0) {
            return blendColor(_satYellow, _yellowRedMid, (18.0 - altDeg)/12.0);
        }

        if (altDeg >= 0.0) {
            return blendColor(_yellowRedMid, _satRed, (6.0 - altDeg)/6.0);
        }

        if (altDeg >= -6.0) {
            return blendColor(_satRed, _redGreyMid, (-altDeg)/6.0);
        }

        if (altDeg >= -12.0) {
            return blendColor(_redGreyMid, _satGrey, (-6.0 - altDeg)/6.0);
        }

        return _satGrey;
    }

    function brightSunColor(sunColor) {
        return blendColor(sunColor, WHITE, 0.45);
    }

    function sunsetAccentScale(sunAltDeg) {
        return clamp(1.0 - abs(sunAltDeg)/SUNSET_ACCENT_ALT_DEG, 0.0, 1.0);
    }

    function ensureColorCache() {
        if (_colorsReady) {
            return;
        }

        _satYellow = saturated(YELLOW);
        _satRed = saturated(RED);
        _satBlue = saturated(BLUE);
        _satGrey = saturated(GREY);

        _yellowRedMid = blendColor(_satYellow, _satRed, 0.5);
        _redBlueMid = blendColor(_satRed, _satBlue, 0.5);
        _redGreyMid = blendColor(_satRed, _satGrey, 0.5);

        _colorsReady = true;
    }

    function saturated(color) {
        return blendColor(toGrey(color), color, clamp(COLOR_SATURATION, 0.0, 1.0));
    }

    function toGrey(color) {
        var r = (color/65536) % 256;
        var g = (color/256) % 256;
        var b = color % 256;
        var y = (0.299*r + 0.587*g + 0.114*b).toNumber();
        return y*65536 + y*256 + y;
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

    function scaleColor(color, s) {
        s = clamp(s, 0.0, 1.0);

        var r = (((color/65536) % 256)*s).toNumber();
        var g = (((color/256) % 256)*s).toNumber();
        var b = ((color % 256)*s).toNumber();

        return r*65536 + g*256 + b;
    }

    function applySaturation(color) {
        return blendColor(toGrey(color), color, clamp(COLOR_SATURATION, 0.0, 1.0));
    }

    function dayOfYear(year, month, day) {
        var doy = MONTH_OFFSETS[month - 1] + day.toFloat();
        if (month > 2 && isLeapYear(year)) { doy += 1.0; }
        return doy;
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

    function deg2rad(x) {
        return x*Math.PI/180.0;
    }

    function rad2deg(x) {
        return x*180.0/Math.PI;
    }
}