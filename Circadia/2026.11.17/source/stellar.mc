using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;

module Stellar {

    const STAR_SEED = 1.0;

    const NIGHT_START_ALT_DEG = -6.0;
    const FULL_NIGHT_ALT_DEG  = -18.0;
    const EARLY_PHASE_ALT_DEG = -12.0;
    const EARLY_PHASE_FRAC    = 0.06;

    var _starCatalog        = null;
    var _catalogSkyRadiusPx = -1.0;
    var _catalogLatDeg      = 999.0;
    var _catalogStarCount   = -1;

    var _projectedStars        = [];
    var _projectionKey         = null;

    function keysEqual(a, b) {
        if (a.size() != b.size()) { return false; }
        for (var i = 0; i < a.size(); i += 1) {
            if (a[i] != b[i]) { return false; }
        }
        return true;
    }

    // layout = [cx, cy, skyRadiusPx]; datetime = [year, month, day, hour, min]
    //
    // Stars are only placed here, once a minute. They are drawn first in the
    // sky, so the sun and moon, painted over them, hide the ones behind them.
    function updateProjectedStars(layout, datetime, latDeg, sunAltDeg, starCount, mipMode) {
        var cx           = layout[0];
        var cy           = layout[1];
        var skyRadiusPx  = layout[2];
        var year         = datetime[0];
        var month        = datetime[1];
        var day          = datetime[2];
        var hour         = datetime[3];
        var min          = datetime[4];

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
            starCount, mipMode
        ];

        if (_projectionKey != null && keysEqual(key, _projectionKey)) {
            return;
        }

        ensureStarCatalog(skyRadiusPx, latDeg, starCount);

        var amoledColors      = mipMode ? null : AmoledArt.starColors();
        var pole              = polePoint(cx, cy, skyRadiusPx, latDeg) as Lang.Array;
        var px                = pole[0];
        var py                = pole[1];
        var spin              = MathUtil.deg2rad(siderealAngleDeg(year, month, day, hour, min));
        if (latDeg < 0.0)     { spin = -spin; }

        var skyR2       = skyRadiusPx * skyRadiusPx;
        var activeCount = activeStarCount(nightScale, _starCatalog.size());
        var stars       = [];

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

            var dx = x - cx;
            var dy = y - cy;
            if (dx * dx + dy * dy <= skyR2) {
                var color = mipMode ? MiPArt.starColor(s[4], s[5]) : amoledColors[s[5]];
                stars.add([MathUtil.roundNearest(x), MathUtil.roundNearest(y), s[4], color]);
            }
        }

        _projectedStars = stars;
        _projectionKey  = key;
    }

    function drawProjectedStars(dc) {
        // During a region repaint only the stars inside the region are drawn.
        var b = Drawing.regionBounds(3);
        for (var i = 0; i < _projectedStars.size(); i += 1) {
            var s = _projectedStars[i] as Lang.Array;
            if (b != null && (s[0] < b[0] || s[0] > b[2] || s[1] < b[1] || s[1] > b[3])) {
                continue;
            }
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
            // Spread evenly over the sky disc.
            var r  = skyRadiusPx * Math.sqrt(rand01(i, 0));
            var a  = 2.0 * Math.PI * rand01(i, 1);

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

        // Stable-partition the shuffled catalog so the brightest earlyCount stars
        // sit at the front — the early-twilight popcorn-in renders only the first
        // activeCount entries, so the first few should be the most prominent.
        var earlyCount = Math.ceil(EARLY_PHASE_FRAC * stars.size().toFloat()).toNumber();

        var sizeCounts = [0, 0, 0, 0];
        for (var i = 0; i < stars.size(); i += 1) {
            var s = stars[i] as Lang.Array;
            sizeCounts[s[4]] += 1;
        }

        // Find the size threshold: descend from XL until we account for earlyCount.
        var cutSize  = 0;
        var cutExtra = earlyCount;
        for (var sz = 3; sz >= 0; sz -= 1) {
            if (cutExtra <= sizeCounts[sz]) { cutSize = sz; break; }
            cutExtra -= sizeCounts[sz];
        }

        var bright = [];
        var dim    = [];
        var atCut  = 0;
        for (var i = 0; i < stars.size(); i += 1) {
            var s  = stars[i] as Lang.Array;
            var sz = s[4];
            if (sz > cutSize) {
                bright.add(stars[i]);
            } else if (sz == cutSize && atCut < cutExtra) {
                bright.add(stars[i]);
                atCut += 1;
            } else {
                dim.add(stars[i]);
            }
        }
        for (var i = 0; i < dim.size(); i += 1) {
            bright.add(dim[i]);
        }
        stars = bright;

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
        if (sunAltDeg >= NIGHT_START_ALT_DEG) { return 0.0; }
        if (sunAltDeg >= EARLY_PHASE_ALT_DEG) {
            var early = (NIGHT_START_ALT_DEG - sunAltDeg) / (NIGHT_START_ALT_DEG - EARLY_PHASE_ALT_DEG);
            return early * EARLY_PHASE_FRAC;
        }
        if (sunAltDeg <= FULL_NIGHT_ALT_DEG) { return 1.0; }
        var late = (EARLY_PHASE_ALT_DEG - sunAltDeg) / (EARLY_PHASE_ALT_DEG - FULL_NIGHT_ALT_DEG);
        return EARLY_PHASE_FRAC + late * (1.0 - EARLY_PHASE_FRAC);
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
