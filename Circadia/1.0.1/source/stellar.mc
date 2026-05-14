using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;

module Stellar {

    const STAR_SEED = 13.0;

    const NIGHT_START_ALT_DEG = -5.0;
    const FULL_NIGHT_ALT_DEG  = -18.0;

    const SOLAR_HALO_RADIUS_DEG = 18.0;

    var _starCatalog        = null;
    var _catalogSkyRadiusPx = -1.0;
    var _catalogLatDeg      = 999.0;
    var _catalogStarCount   = -1;

    var _projectedStars        = [];
    var _projectionKey         = null;
    var _fullBrightnessColors  = null;

    function keysEqual(a, b) {
        if (a.size() != b.size()) { return false; }
        for (var i = 0; i < a.size(); i += 1) {
            if (a[i] != b[i]) { return false; }
        }
        return true;
    }

    function updateProjectedStars(cx, cy, skyRadiusPx, year, month, day, hour, min,
                                   latDeg, sunAltDeg, sunX, sunY, moonX, moonY,
                                   moonRadiusPx, starCount) {
        var nightScale = starNightScale(sunAltDeg);
        if (nightScale <= 0.0) {
            _projectedStars = [];
            _projectionKey  = null;
            return;
        }

        var key = [
            cx.toNumber(), cy.toNumber(), skyRadiusPx.toNumber(),
            year, month, day, hour, min,
            (latDeg    * 100.0).toNumber(),
            (sunAltDeg * 100.0).toNumber(),
            sunX.toNumber(),  sunY.toNumber(),
            moonX.toNumber(), moonY.toNumber(),
            moonRadiusPx.toNumber(), starCount
        ];

        if (_projectionKey != null && keysEqual(key, _projectionKey)) {
            return;
        }

        ensureStarCatalog(skyRadiusPx, latDeg, starCount);

        if (_fullBrightnessColors == null) {
            _fullBrightnessColors = Drawing.fadedStarColors(1.0);
        }
        var fadedColors       = _fullBrightnessColors;
        var pole              = polePoint(cx, cy, skyRadiusPx, latDeg) as Lang.Array;
        var px                = pole[0];
        var py                = pole[1];
        var spin              = MathUtil.deg2rad(siderealAngleDeg(year, month, day, hour, min));
        if (latDeg < 0.0)     { spin = -spin; }

        var skyR2             = skyRadiusPx * skyRadiusPx;
        var moonR2            = moonRadiusPx * moonRadiusPx;
        var solarHaloRadiusPx = skyRadiusPx * (SOLAR_HALO_RADIUS_DEG / 90.0);
        var solarHaloR2       = solarHaloRadiusPx * solarHaloRadiusPx;
        var activeCount       = activeStarCount(nightScale, _starCatalog.size());
        var stars             = [];

        for (var i = 0; i < activeCount; i += 1) {
            var s          = _starCatalog[i] as Lang.Array;
            var pathRadius = s[0];
            var arcStart   = s[1];
            var arcLength  = s[2];
            var phase0     = s[3];

            var phase = MathUtil.frac(phase0 + spin / arcLength);
            var angle = arcStart + phase * arcLength;
            var x     = px + pathRadius * Math.cos(angle);
            var y     = py + pathRadius * Math.sin(angle);

            if (starIsVisible(x, y, cx, cy, skyR2, sunX, sunY, solarHaloR2, moonX, moonY, moonRadiusPx, moonR2)) {
                stars.add([MathUtil.roundNearest(x), MathUtil.roundNearest(y), s[4], fadedColors[s[5]]]);
            }
        }

        _projectedStars = stars;
        _projectionKey  = key;
    }

    function drawProjectedStars(dc) {
        for (var i = 0; i < _projectedStars.size(); i += 1) {
            var s = _projectedStars[i] as Lang.Array;
            Drawing.drawProjectedStar(dc, s[0], s[1], s[2], s[3]);
        }
    }

    // ── Catalog management ───────────────────────────────────────────────────

    function ensureStarCatalog(skyRadiusPx, latDeg, starCount) {
        if (_starCatalog == null
            || MathUtil.abs(skyRadiusPx - _catalogSkyRadiusPx) > 0.5
            || MathUtil.abs(latDeg - _catalogLatDeg) > 0.25
            || starCount != _catalogStarCount) {

            _starCatalog        = buildStarCatalog(skyRadiusPx, latDeg, starCount);
            _catalogSkyRadiusPx = skyRadiusPx;
            _catalogLatDeg      = latDeg;
            _catalogStarCount   = starCount;
        }
    }

    function buildStarCatalog(skyRadiusPx, latDeg, starCount) {
        var stars = [];

        var pole       = polePoint(0.0, 0.0, skyRadiusPx, latDeg) as Lang.Array;
        var px         = pole[0];
        var py         = pole[1];
        var poleDist   = Math.sqrt(px * px + py * py);
        var centerAngle = Math.atan2(-py, -px);

        for (var i = 0; i < starCount; i += 1) {
            var w  = 0.5;
            var N  = 7;
            var u  = (1 - w) * rand01(i, 0) + w * rand01(i % N, 0);
            var r  = skyRadiusPx * Math.sqrt(u);
            var a  = 2.0 * Math.PI * ((1 - w) * rand01(i, 1) + w * rand01(i % N, 1));

            var dx = r * Math.cos(a) - px;
            var dy = r * Math.sin(a) - py;

            var pathRadius = Math.sqrt(dx * dx + dy * dy);
            var starAngle  = Math.atan2(dy, dx);
            var path       = visiblePath(pathRadius, starAngle, poleDist, centerAngle, skyRadiusPx) as Lang.Array;

            stars.add([pathRadius, path[0], path[1], path[2], starSize(i), starColorBin(i)]);
        }

        for (var i = stars.size() - 1; i > 0; i -= 1) {
            var j   = Math.floor(rand01(i, 99) * (i + 1)).toNumber();
            var tmp = stars[i];
            stars[i] = stars[j];
            stars[j] = tmp;
        }

        return stars;
    }

    function visiblePath(pathRadius, starAngle, poleDist, centerAngle, skyRadiusPx) {
        var fullCircle = [0.0, 2.0 * Math.PI, MathUtil.frac(starAngle / (2.0 * Math.PI))];

        if (pathRadius <= 0.001 || poleDist <= 0.001 || pathRadius + poleDist <= skyRadiusPx) {
            return fullCircle;
        }

        var c = (pathRadius * pathRadius + poleDist * poleDist - skyRadiusPx * skyRadiusPx)
                / (2.0 * pathRadius * poleDist);

        if (c <= -1.0) { return fullCircle; }
        if (c > 1.0)   { c = 1.0; }

        var halfArc   = Math.acos(c);
        var arcStart  = centerAngle - halfArc;
        var arcLength = 2.0 * halfArc;
        if (arcLength < 0.001) { arcLength = 0.001; }

        return [arcStart, arcLength, MathUtil.frac((starAngle - arcStart) / arcLength)];
    }

    // ── Visibility test ──────────────────────────────────────────────────────

    function starIsVisible(x, y, cx, cy, skyR2, sunX, sunY, solarHaloR2, moonX, moonY, moonRadiusPx, moonR2) {
        var dxSky = x - cx;
        var dySky = y - cy;
        if (dxSky * dxSky + dySky * dySky > skyR2) { return false; }

        var dxSun = x - sunX;
        var dySun = y - sunY;
        if (dxSun * dxSun + dySun * dySun <= solarHaloR2) { return false; }

        if (moonRadiusPx > 0.0) {
            var dxMoon = x - moonX;
            var dyMoon = y - moonY;
            if (dxMoon * dxMoon + dyMoon * dyMoon <= moonR2) { return false; }
        }

        return true;
    }

    // ── Star property helpers ────────────────────────────────────────────────

    function activeStarCount(nightScale, totalCount) {
        var n = Math.floor(nightScale * totalCount + 0.999).toNumber();
        if (n < 0)          { return 0; }
        if (n > totalCount) { return totalCount; }
        return n;
    }

    function starSize(i) {
        var u = rand01(i, 2);
        if (u < Drawing.SMALL_STAR_FRAC) { return Drawing.STAR_SMALL; }
        if (u < Drawing.SMALL_STAR_FRAC + Drawing.MEDIUM_STAR_FRAC) { return Drawing.STAR_MEDIUM; }
        if (u < Drawing.SMALL_STAR_FRAC + Drawing.MEDIUM_STAR_FRAC + Drawing.LARGE_STAR_FRAC) { return Drawing.STAR_LARGE; }
        return Drawing.STAR_XL;
    }

    function starColorBin(i) {
        var u = rand01(i, 3);
        if (u < Drawing.STAR_YELLOW_FRAC) { return Drawing.STAR_BIN_YELLOW; }
        var accum = Drawing.STAR_YELLOW_FRAC + Drawing.STAR_SOFT_YELLOW_FRAC;
        if (u < accum) { return Drawing.STAR_BIN_SOFT_YELLOW; }
        accum += Drawing.STAR_RED_FRAC;
        if (u < accum) { return Drawing.STAR_BIN_RED; }
        accum += Drawing.STAR_BLUE_FRAC;
        if (u < accum) { return Drawing.STAR_BIN_BLUE; }
        return Drawing.STAR_BIN_WHITE;
    }

    // ── Astronomy helpers ────────────────────────────────────────────────────

    function siderealAngleDeg(year, month, day, hour, min) {
        var dayIndex    = MathUtil.dayOfYear(year, month, day) - 1.0;
        var minuteOfDay = 60.0 * hour + min.toFloat();
        return MathUtil.wrap360(0.985647 * dayIndex + 360.985647 * (minuteOfDay / 1440.0));
    }

    function starNightScale(sunAltDeg) {
        return MathUtil.clamp(
            (NIGHT_START_ALT_DEG - sunAltDeg) / (NIGHT_START_ALT_DEG - FULL_NIGHT_ALT_DEG),
            0.0, 1.0
        );
    }

    function polePoint(cx, cy, skyRadiusPx, latDeg) {
        var altDeg = MathUtil.abs(latDeg);
        if (altDeg > 90.0) { altDeg = 90.0; }
        var rho   = skyRadiusPx * (1.0 - altDeg / 90.0);
        var azDeg = (latDeg >= 0.0) ? 0.0 : 180.0;
        var az    = MathUtil.deg2rad(azDeg);
        return [cx + rho * Math.sin(az), cy - rho * Math.cos(az)];
    }

    // ── Math helpers ─────────────────────────────────────────────────────────

    function rand01(i, channel) {
        var x = Math.sin(
            (i.toFloat() + 1.0) * 12.9898
            + (channel.toFloat() + 1.0) * 78.233
            + STAR_SEED * 0.12345
        ) * 43758.5453;
        return MathUtil.frac(x);
    }

}
