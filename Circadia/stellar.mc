using Toybox.Graphics;
using Toybox.Math;

module Stellar {

    const BLACK = 0x000000;

    const STAR_COUNT = 200;
    const STAR_SEED = 26.0;

    const NIGHT_START_ALT_DEG = 0.0;
    const FULL_NIGHT_ALT_DEG = -18.0;

    const SOLAR_HALO_RADIUS_DEG = 18.0;

    const STAR_SMALL = 0;
    const STAR_MEDIUM = 1;
    const STAR_LARGE = 2;
    const STAR_XL = 3;

    const SMALL_FRAC = 0.7;
    const MEDIUM_FRAC = 0.25;
    const LARGE_FRAC = 0.03;
    const XL_FRAC = 0.02;

    const STAR_YELLOW = 0;
    const STAR_SOFT_YELLOW = 1;
    const STAR_RED = 2;
    const STAR_BLUE = 3;
    const STAR_WHITE = 4;

    const STAR_COLOR_VALUES = [
        0xFDEBD2,
        0xFFF6D8,
        0xFFB08A,
        0xC9D8FF,
        0xF4F4FF
    ];

    const STAR_YELLOW_FRAC = 0.55;
    const STAR_SOFT_YELLOW_FRAC = 0.20;
    const STAR_RED_FRAC = 0.12;
    const STAR_BLUE_FRAC = 0.08;
    const STAR_WHITE_FRAC = 0.05;

    var _starCatalog = null;
    var _catalogSkyRadiusPx = -1.0;
    var _catalogLatDeg = 999.0;

    function drawStars(dc, cx, cy, skyRadiusPx, year, month, day, hour, min, sec, latDeg, sunAltDeg, sunX, sunY, moonX, moonY, moonRadiusPx) {
        var nightScale = starNightScale(sunAltDeg);
        if (nightScale <= 0.0) {
            return;
        }

        ensureStarCatalog(skyRadiusPx, latDeg);

        var fadedColors = fadedStarColors(nightScale);

        var pole = polePoint(cx, cy, skyRadiusPx, latDeg);
        var px = pole[0];
        var py = pole[1];

        var spin = deg2rad(siderealAngleDeg(year, month, day, hour, min));
        if (latDeg < 0.0) {
            spin = -spin;
        }

        var skyR2 = skyRadiusPx*skyRadiusPx;
        var moonR2 = moonRadiusPx*moonRadiusPx;
        var solarHaloRadiusPx = skyRadiusPx*(SOLAR_HALO_RADIUS_DEG/90.0);
        var solarHaloR2 = solarHaloRadiusPx*solarHaloRadiusPx;
        var activeCount = activeStarCount(nightScale, _starCatalog.size());

        for (var i = 0; i < activeCount; i += 1) {
            var s = _starCatalog[i];

            var pathRadius = s[0];
            var arcStart = s[1];
            var arcLength = s[2];
            var phase0 = s[3];

            var phase = frac(phase0 + spin/arcLength);
            var a = arcStart + phase*arcLength;

            drawStarIfVisible(
                dc,
                px + pathRadius*Math.cos(a),
                py + pathRadius*Math.sin(a),
                cx,
                cy,
                skyR2,
                sunX,
                sunY,
                solarHaloR2,
                moonX,
                moonY,
                moonRadiusPx,
                moonR2,
                s[4],
                fadedColors[s[5]]
            );
        }
    }

    function ensureStarCatalog(skyRadiusPx, latDeg) {
        if (_starCatalog == null
            || abs(skyRadiusPx - _catalogSkyRadiusPx) > 0.5
            || abs(latDeg - _catalogLatDeg) > 0.25) {

            _starCatalog = buildStarCatalog(skyRadiusPx, latDeg);
            _catalogSkyRadiusPx = skyRadiusPx;
            _catalogLatDeg = latDeg;
        }
    }

    function buildStarCatalog(skyRadiusPx, latDeg) {
        var stars = [];

        var pole = polePoint(0.0, 0.0, skyRadiusPx, latDeg);
        var px = pole[0];
        var py = pole[1];

        var poleDist = Math.sqrt(px*px + py*py);
        var centerAngle = Math.atan2(-py, -px);

        for (var i = 0; i < STAR_COUNT; i += 1) {
            var w = 0.5;
            var N = 7;

            var u = (1 - w)*rand01(i, 0) + w*rand01(i % N, 0);
            var r = skyRadiusPx*Math.sqrt(u);

            var a = 2.0*Math.PI*((1 - w)*rand01(i, 1) + w*rand01(i % N, 1));
            var x = r*Math.cos(a);
            var y = r*Math.sin(a);

            var dx = x - px;
            var dy = y - py;

            var pathRadius = Math.sqrt(dx*dx + dy*dy);
            var starAngle = Math.atan2(dy, dx);
            var path = visiblePath(pathRadius, starAngle, poleDist, centerAngle, skyRadiusPx);

            stars.add([
                pathRadius,
                path[0],
                path[1],
                path[2],
                starSize(i),
                starColorBin(i)
            ]);
        }

        return stars;
    }

    function visiblePath(pathRadius, starAngle, poleDist, centerAngle, skyRadiusPx) {
        if (pathRadius <= 0.001 || poleDist <= 0.001 || pathRadius + poleDist <= skyRadiusPx) {
            return [
                0.0,
                2.0*Math.PI,
                frac(starAngle/(2.0*Math.PI))
            ];
        }

        var c = (pathRadius*pathRadius + poleDist*poleDist - skyRadiusPx*skyRadiusPx)/(2.0*pathRadius*poleDist);

        if (c <= -1.0) {
            return [
                0.0,
                2.0*Math.PI,
                frac(starAngle/(2.0*Math.PI))
            ];
        }

        if (c > 1.0) {
            c = 1.0;
        }

        var halfArc = Math.acos(c);
        var arcStart = centerAngle - halfArc;
        var arcLength = 2.0*halfArc;

        if (arcLength < 0.001) {
            arcLength = 0.001;
        }

        return [
            arcStart,
            arcLength,
            frac((starAngle - arcStart)/arcLength)
        ];
    }

    function drawStarIfVisible(dc, x, y, cx, cy, skyR2, sunX, sunY, solarHaloR2, moonX, moonY, moonRadiusPx, moonR2, starSize, starColor) {
        var dxSky = x - cx;
        var dySky = y - cy;
        if (dxSky*dxSky + dySky*dySky > skyR2) {
            return;
        }

        var dxSun = x - sunX;
        var dySun = y - sunY;
        if (dxSun*dxSun + dySun*dySun <= solarHaloR2) {
            return;
        }

        if (moonRadiusPx > 0.0) {
            var dxMoon = x - moonX;
            var dyMoon = y - moonY;
            if (dxMoon*dxMoon + dyMoon*dyMoon <= moonR2) {
                return;
            }
        }

        var xi = roundNearest(x);
        var yi = roundNearest(y);

        dc.setColor(starColor, BLACK);

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

    function activeStarCount(nightScale, totalCount) {
        var n = Math.floor(nightScale*totalCount + 0.999).toNumber();
        if (n < 0) { return 0; }
        if (n > totalCount) { return totalCount; }
        return n;
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

    function starSize(i) {
        var u = rand01(i, 2);

        if (u < SMALL_FRAC) {
            return STAR_SMALL;
        }
        if (u < SMALL_FRAC + MEDIUM_FRAC) {
            return STAR_MEDIUM;
        }
        if (u < SMALL_FRAC + MEDIUM_FRAC + LARGE_FRAC) {
            return STAR_LARGE;
        }
        return STAR_XL;
    }

    function starColorBin(i) {
        var u = rand01(i, 3);

        if (u < STAR_YELLOW_FRAC) {
            return STAR_YELLOW;
        }
        if (u < STAR_YELLOW_FRAC + STAR_SOFT_YELLOW_FRAC) {
            return STAR_SOFT_YELLOW;
        }
        if (u < STAR_YELLOW_FRAC + STAR_SOFT_YELLOW_FRAC + STAR_RED_FRAC) {
            return STAR_RED;
        }
        if (u < STAR_YELLOW_FRAC + STAR_SOFT_YELLOW_FRAC + STAR_RED_FRAC + STAR_BLUE_FRAC) {
            return STAR_BLUE;
        }
        return STAR_WHITE;
    }

    function fadedStarColors(nightScale) {
        return [
            blendColor(BLACK, STAR_COLOR_VALUES[STAR_YELLOW], nightScale),
            blendColor(BLACK, STAR_COLOR_VALUES[STAR_SOFT_YELLOW], nightScale),
            blendColor(BLACK, STAR_COLOR_VALUES[STAR_RED], nightScale),
            blendColor(BLACK, STAR_COLOR_VALUES[STAR_BLUE], nightScale),
            blendColor(BLACK, STAR_COLOR_VALUES[STAR_WHITE], nightScale)
        ];
    }

    function siderealAngleDeg(year, month, day, hour, min) {
        var dayIndex = dayNumber(year, month, day) - 1.0;
        var minuteOfDay = 60.0*hour + min.toFloat();
        return wrap360(0.985647*dayIndex + 360.985647*(minuteOfDay/1440.0));
    }

    function starNightScale(sunAltDeg) {
        return clamp((NIGHT_START_ALT_DEG - sunAltDeg)/(NIGHT_START_ALT_DEG - FULL_NIGHT_ALT_DEG), 0.0, 1.0);
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