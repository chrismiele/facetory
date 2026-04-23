using Toybox.Graphics;
using Toybox.Math;

module Stellar {

    const BLACK = 0x000000;

    const STAR_COUNT = 200;
    const STAR_SEED = 26.0;

    const NIGHT_START_ALT_DEG = 0.0;
    const FULL_NIGHT_ALT_DEG = -18.0;

    const STAR_SMALL = 0;
    const STAR_MEDIUM = 1;
    const STAR_LARGE = 2;
    const STAR_XL = 3;

    // Adjustable size mix
    const SMALL_FRAC = 0.7;
    const MEDIUM_FRAC = 0.25;
    const LARGE_FRAC = 0.03;
    const XL_FRAC = 0.02;

    const STAR_FADE_COLORS = [
        0x000000,
        0x201E1B,
        0x3F3C36,
        0x5E5A50,
        0x7D7769,
        0x9C9482,
        0xC6BDA8,
        0xFDEBD2
    ];

    const POLE_OFFSET_SCALE = 0.8;
    const STAR_BUDGET_FALLOFF = 0.55;
    const MIN_STAR_BUDGET = 120;

    var _starCatalog = null;
    var _catalogFieldRadiusPx = -1.0;
    var _catalogSkyRadiusPx = -1.0;
    var _catalogLatDeg = 999.0;

    function drawStars(dc, cx, cy, skyRadiusPx, year, month, day, hour, min, sec, latDeg, sunAltDeg, moonX, moonY, moonRadiusPx) {
        var nightScale = starNightScale(sunAltDeg);
        if (nightScale <= 0.0) {
            return;
        }

        var fadeIndex = Math.floor(nightScale*7.999).toNumber();
        dc.setColor(STAR_FADE_COLORS[fadeIndex], BLACK);

        var pole = polePoint(cx, cy, skyRadiusPx, latDeg);
        var px = pole[0];
        var py = pole[1];

        var spin = siderealAngleDeg(year, month, day, hour, min);
        var ang = deg2rad(spin);
        var cs = Math.cos(ang);
        var sn = Math.sin(ang);

        if (latDeg < 0.0) {
            sn = -sn;
        }

        var skyR2 = skyRadiusPx*skyRadiusPx;
        var moonR2 = moonRadiusPx*moonRadiusPx;

        var fieldRadiusPx = starFieldRadiusPx(skyRadiusPx, latDeg);
        ensureStarCatalog(fieldRadiusPx, skyRadiusPx, latDeg);

        var activeCount = activeStarCount(nightScale, _starCatalog.size());

        drawPolaris(dc, px, py, nightScale, moonX, moonY, moonR2);

        for (var i = 0; i < activeCount; i += 1) {
            var s = _starCatalog[i];

            var x0 = s[0];
            var y0 = s[1];
            var starSize = s[2];

            var x = px + x0*cs - y0*sn;
            var y = py + x0*sn + y0*cs;

            var dxSky = x - cx;
            var dySky = y - cy;
            if (dxSky*dxSky + dySky*dySky > skyR2) {
                continue;
            }

            if (moonRadiusPx > 0.0) {
                var dxMoon = x - moonX;
                var dyMoon = y - moonY;
                if (dxMoon*dxMoon + dyMoon*dyMoon <= moonR2) {
                    continue;
                }
            }

            var xi = roundNearest(x);
            var yi = roundNearest(y);

            if (starSize == STAR_XL) {
                dc.fillRectangle(xi - 2, yi - 2, 4, 4);
            } else if (starSize == STAR_LARGE) {
                dc.fillRectangle(xi - 1, yi - 1, 3, 3);
            } else if (starSize == STAR_MEDIUM) {
                dc.fillRectangle(xi - 1, yi - 1, 2, 2);
            } else {
                dc.drawPoint(xi, yi);
            }
        }
    }

    function activeStarCount(nightScale, totalCount) {
        var n = Math.floor(nightScale*totalCount + 0.999).toNumber();
        if (n < 0) {
            return 0;
        }
        if (n > totalCount) {
            return totalCount;
        }
        return n;
    }

    function ensureStarCatalog(fieldRadiusPx, skyRadiusPx, latDeg) {
        if (_starCatalog == null
            || abs(fieldRadiusPx - _catalogFieldRadiusPx) > 0.5
            || abs(skyRadiusPx - _catalogSkyRadiusPx) > 0.5
            || abs(latDeg - _catalogLatDeg) > 0.25) {

            _starCatalog = buildStarCatalog(fieldRadiusPx, skyRadiusPx, latDeg);
            _catalogFieldRadiusPx = fieldRadiusPx;
            _catalogSkyRadiusPx = skyRadiusPx;
            _catalogLatDeg = latDeg;
        }
    }

    function buildStarCatalog(fieldRadiusPx, skyRadiusPx, latDeg) {
        var stars = [];

        var altDeg = abs(latDeg);
        if (altDeg > 90.0) {
            altDeg = 90.0;
        }

        var poleOffsetPx = skyRadiusPx*(1.0 - altDeg/90.0);
        var poleFrac = poleOffsetPx/skyRadiusPx;

        var starBudget = (STAR_COUNT*(1.0 - STAR_BUDGET_FALLOFF*poleFrac*poleFrac) + 0.999).toNumber();
        if (starBudget < MIN_STAR_BUDGET) {
            starBudget = MIN_STAR_BUDGET;
        }

        var candidateCount = (starBudget*(fieldRadiusPx*fieldRadiusPx)/(skyRadiusPx*skyRadiusPx) + 0.999).toNumber();

        for (var i = 0; i < candidateCount; i += 1) {
            stars.add(starSample(i, fieldRadiusPx));
        }

        return stars;
    }

    function polePoint(cx, cy, skyRadiusPx, latDeg) {
        var altDeg = abs(latDeg);
        if (altDeg > 90.0) {
            altDeg = 90.0;
        }

        var rho = skyRadiusPx*(1.0 - altDeg/90.0);
        var azDeg = (latDeg >= 0.0) ? 0.0 : 180.0;
        var az = deg2rad(azDeg);

        return [
            cx + rho*Math.sin(az),
            cy - rho*Math.cos(az)
        ];
    }

    function drawPolaris(dc, x, y, nightScale, moonX, moonY, moonR2) {
        if (nightScale <= 0.42) {
            return;
        }

        var dxMoon = x - moonX;
        var dyMoon = y - moonY;
        if (moonR2 > 0.0 && dxMoon*dxMoon + dyMoon*dyMoon <= moonR2) {
            return;
        }

        var xi = roundNearest(x);
        var yi = roundNearest(y);
        dc.fillRectangle(xi - 1, yi - 1, 2, 2);
    }

    function starSample(i, fieldRadiusPx) {
        var u0 = rand01(i, 0);
        var u1 = rand01(i, 1);
        var u2 = rand01(i, 2);

        var r = fieldRadiusPx*Math.sqrt(u0);
        var a = 2.0*Math.PI*u1;

        var x0 = r*Math.cos(a);
        var y0 = r*Math.sin(a);

        var starSize;
        if (u2 < SMALL_FRAC) {
            starSize = STAR_SMALL;
        } else if (u2 < SMALL_FRAC + MEDIUM_FRAC) {
            starSize = STAR_MEDIUM;
        } else if (u2 < SMALL_FRAC + MEDIUM_FRAC + LARGE_FRAC) {
            starSize = STAR_LARGE;
        } else {
            starSize = STAR_XL;
        }

        return [x0, y0, starSize];
    }

    function siderealAngleDeg(year, month, day, hour, min) {
        var dayIndex = dayNumber(year, month, day) - 1.0;
        var minuteOfDay = 60.0*hour + min.toFloat();

        return wrap360(0.985647*dayIndex + 360.985647*(minuteOfDay/1440.0));
    }

    function starNightScale(sunAltDeg) {
        return clamp((NIGHT_START_ALT_DEG - sunAltDeg)/(NIGHT_START_ALT_DEG - FULL_NIGHT_ALT_DEG), 0.0, 1.0);
    }

    function starFieldRadiusPx(skyRadiusPx, latDeg) {
        var altDeg = abs(latDeg);
        if (altDeg > 90.0) {
            altDeg = 90.0;
        }

        var poleOffsetPx = skyRadiusPx*(1.0 - altDeg/90.0);
        return skyRadiusPx + POLE_OFFSET_SCALE*poleOffsetPx;
    }

    function rand01(i, channel) {
        var x = Math.sin(
            (i.toFloat() + 1.0)*12.9898
            + (channel.toFloat() + 1.0)*78.233
            + STAR_SEED*0.12345
        )*43758.5453;

        return frac(x);
    }

    function frac(x) {
        return x - Math.floor(x);
    }

    function dayNumber(year, month, day) {
        var n = day.toFloat();

        if (month > 1) { n += 31.0; }
        if (month > 2) { n += 28.0; }
        if (month > 3) { n += 31.0; }
        if (month > 4) { n += 30.0; }
        if (month > 5) { n += 31.0; }
        if (month > 6) { n += 30.0; }
        if (month > 7) { n += 31.0; }
        if (month > 8) { n += 31.0; }
        if (month > 9) { n += 30.0; }
        if (month > 10) { n += 31.0; }
        if (month > 11) { n += 30.0; }

        if (month > 2 && isLeapYear(year)) {
            n += 1.0;
        }

        return n;
    }

    function roundNearest(x) {
        if (x >= 0.0) {
            return (x + 0.5).toNumber();
        }
        return (x - 0.5).toNumber();
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

    function deg2rad(x) {
        return x*Math.PI/180.0;
    }
}