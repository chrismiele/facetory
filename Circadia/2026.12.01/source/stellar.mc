using Toybox.Lang;
using Toybox.Math;
using Toybox.WatchUi;

// The real night sky: the brightest stars of the Yale Bright Star Catalogue,
// placed where they are right now for the watch's location.
//
// Which stars. The "Number of stars" setting (100 or 200) is how many are
// shown at full night: the first that many stars, in the order of the star
// table, that are above the horizon at this moment. "Which stars" picks the
// table (resources/jsonData, built by tools/build_stars.py):
//   Brightest       the brightest stars of the whole sky, brightest first.
//   Constellations  the stars of about 30 well-known constellation figures
//                   (and the Pleiades) first, a figure's fainter stars ranked
//                   together so the figure comes in whole, then other figure
//                   stars, then the rest. The preference is soft: a very
//                   bright star outside the figures still makes the cut.
//   Zodiac          the stars of the twelve zodiac figures and the very
//                   brightest stars first, then the brightest, to fill the
//                   sky to the same count.
// Each table is long enough for the busiest sky at any latitude for either
// setting. Positions are for the 2027.0 equinox, with proper motion applied;
// they drift about 0.014 deg a year, well under a pixel for decades.
//
// When they appear. Each star appears once it is bright enough to see
// against the twilight sky: when its apparent magnitude is no fainter than
// the naked-eye limit for the sun's altitude (LIMIT_*). That limit is tied
// to the twilight boundaries: nothing until 3 deg after sunset, the
// brightest stars (to magnitude 1) by the end of civil twilight, magnitude
// 4.5 at the end of nautical twilight, magnitude 6 at full night. A star's
// apparent magnitude includes the dimming of the air near the horizon, so
// low stars appear later than overhead ones, and the faintest low ones only
// near full night. Stars pop in one by one, brightest first, as the sun sinks,
// and leave in reverse order at dawn.
//
// How they look. Each star keeps one size and one colour all night: size
// from its catalogue magnitude (*_MAG thresholds), colour from its B-V colour
// index, binned when the table was built (Drawing.STAR_BIN_*). The dimming
// near the horizon only decides when a star appears.
//
// Figure lines (Constellations: the well-known figures; Zodiac: the twelve
// zodiac figures). At full night (sun at -18 deg or lower) faint lines join
// the figures' stars, drawn under the stars and stopping just short of them.
// They all come out together when full night begins and all go when it ends.
// Every figure is drawn complete: a line from a star above the horizon to
// one below it runs on to the edge of the sky, so a figure low in the sky is
// cut off by the horizon, as in a planetarium. Figure stars above the horizon
// are always shown, even beyond the "Number of stars" or when the haze near
// the horizon would hide them, so a figure never has a gap.
module Stellar {

    const FULL_NIGHT_ALT_DEG = -18.0;    // end of astronomical twilight; keep equal to -SunArt.OUTER_DEG

    // Naked-eye limiting magnitude against the sky, by the sun's altitude.
    // Between these points it changes evenly.
    const LIMIT_ALT_DEG = [-3.0, -6.0, -12.0, -18.0];
    const LIMIT_MAG     = [-1.5,  1.0,   4.5,   6.0];

    // Dimming by the atmosphere: magnitudes per extra airmass beyond the
    // zenith (a typical clear sky in visible light).
    const EXTINCTION_PER_AIRMASS = 0.25;

    // Catalogue magnitude at or brighter than which a star is drawn XL,
    // large or medium; fainter stars are a single pixel.
    const XL_MAG     = 0.5;
    const LARGE_MAG  = 1.5;
    const MEDIUM_MAG = 2.5;

    // Each catalogue entry is one integer:
    //   bits 20-30  right ascension, in steps of 360/2048 deg
    //   bits 10-19  declination + 90, in steps of 180/1023 deg
    //   bits  3-9   V magnitude, as (V - MAG_ZERO) / MAG_STEP
    //   bits  0-2   colour bin (Drawing.STAR_BIN_*)
    const RA_STEP_DEG  = 0.17578125;       // 360 / 2048
    const DEC_STEP_DEG = 0.17595307918;    // 180 / 1023
    const MAG_ZERO     = -1.5;
    const MAG_STEP     = 0.1;

    const MODE_BRIGHTEST      = 0;
    const MODE_CONSTELLATIONS = 1;
    const MODE_ZODIAC         = 2;

    // Lines stop this many pixels short of a star's centre, by star size
    // (Drawing.STAR_*), and are left out if nothing would remain.
    const LINE_GAP_PX = [3, 4, 4, 5];

    // Each line is one integer: bits 0-8 and 9-17 are the star table indices
    // of its ends, bits 18-24 the figure. Lines are grouped by figure.
    const LINE_FIGURE_SHIFT = 18;

    // Shown stars, one integer each:
    //   bits 0-10 x, bits 11-21 y (pixels), bits 22-23 size (Drawing.STAR_*),
    //   bits 24-26 colour bin (Drawing.STAR_BIN_*).
    // Figure star positions (line modes, at full night), one integer per
    // star table entry, 0 when not placed this minute:
    //   bits 0-10 x + 1024, bits 11-21 y + 1024 (below-horizon stars can lie
    //   past the screen), bit 22 above the horizon, bit 23 in the shown stars,
    //   bit 24 placed.
    // Lines, two integers each: x0 | y0 << 11, then x1 | y1 << 11.
    const POS_OFFSET = 1024;
    const POS_UP     = 0x400000;
    const POS_SHOWN  = 0x800000;
    const POS_PLACED = 0x1000000;

    var _catalog        = null;
    var _catalogMode    = -1;
    var _lineTable      = null;
    var _lineMode       = -1;
    var _figureStar     = null;    // per star table entry: 1 if in a figure's lines
    var _lastFigureStar = -1;      // highest such entry
    var _figurePos      = null;    // reused each minute; see POS_*
    var _projectedStars = [];
    var _projectedLines = [];
    var _starColorBins  = null;    // AMOLED star colours, or null for MIP
    var _lineColor      = 0;
    var _lineAntiAlias  = false;
    var _projectionKey  = null;

    function keysEqual(a, b) {
        if (a.size() != b.size()) { return false; }
        for (var i = 0; i < a.size(); i += 1) {
            if (a[i] != b[i]) { return false; }
        }
        return true;
    }

    // The packed star table for this mode, loaded on first use. Only one
    // table is in memory at a time.
    function catalog(mode) {
        if (_catalog == null || mode != _catalogMode) {
            _catalog = null;
            if (mode == MODE_CONSTELLATIONS) {
                _catalog = WatchUi.loadResource(Rez.JsonData.StarsConstellations) as Lang.Array;
            } else if (mode == MODE_ZODIAC) {
                _catalog = WatchUi.loadResource(Rez.JsonData.StarsZodiac) as Lang.Array;
            } else {
                _catalog = WatchUi.loadResource(Rez.JsonData.StarsBrightest) as Lang.Array;
            }
            _catalogMode = mode;
        }
        return _catalog;
    }

    // The figure lines for this mode (Constellations or Zodiac), and which
    // star table entries they use. Loaded on first use, one mode at a time.
    function lineTable(mode) {
        if (_lineTable == null || mode != _lineMode) {
            _lineTable  = null;
            _figureStar = null;
            _figurePos  = null;
            _lineTable  = WatchUi.loadResource(mode == MODE_ZODIAC
                              ? Rez.JsonData.ZodiacLines
                              : Rez.JsonData.StarLines) as Lang.Array;
            _lastFigureStar = -1;
            for (var k = 0; k < _lineTable.size(); k += 1) {
                var a = _lineTable[k] & 0x1FF;
                var b = (_lineTable[k] >> 9) & 0x1FF;
                if (a > _lastFigureStar) { _lastFigureStar = a; }
                if (b > _lastFigureStar) { _lastFigureStar = b; }
            }
            _figureStar = new [_lastFigureStar + 1]b;
            for (var k = 0; k < _lineTable.size(); k += 1) {
                _figureStar[_lineTable[k] & 0x1FF] = 1;
                _figureStar[(_lineTable[k] >> 9) & 0x1FF] = 1;
            }
            _figurePos = new [_lastFigureStar + 1];
            _lineMode  = mode;
        }
        return _lineTable;
    }

    // Drop what only the line modes need.
    function releaseLines() {
        _lineTable  = null;
        _figureStar = null;
        _figurePos  = null;
        _lineMode   = -1;
    }

    // layout = [cx, cy, skyRadiusPx]; datetime = [year, month, day, hour, min]
    // (local clock); offsetSec = the local time zone's offset from UTC.
    //
    // Stars are only placed here, once a minute. They are drawn first in the
    // sky, so the sun and moon, painted over them, hide the ones behind them.
    function updateProjectedStars(layout, datetime, latDeg, lonDeg, offsetSec, sunAltDeg, starCount, starMode, mipMode) {
        var limitMag = limitingMagnitude(sunAltDeg);
        if (limitMag <= LIMIT_MAG[0] || starCount <= 0) {
            _projectedStars = [];
            _projectedLines = [];
            _projectionKey  = null;
            return;
        }

        var cx          = layout[0];
        var cy          = layout[1];
        var skyRadiusPx = layout[2];

        var key = [
            cx.toNumber(), cy.toNumber(), skyRadiusPx.toNumber(),
            datetime[0], datetime[1], datetime[2], datetime[3], datetime[4],
            (latDeg    * 100.0).toNumber(),
            (lonDeg    * 100.0).toNumber(),
            offsetSec,
            (sunAltDeg * 100.0).toNumber(),
            starCount, starMode, mipMode
        ];
        if (_projectionKey != null && keysEqual(key, _projectionKey)) {
            return;
        }

        // Let last minute's sky go before building this one.
        _projectedStars = [];
        _projectedLines = [];

        var utc = MathUtil.utcFromLocal(datetime[0], datetime[1], datetime[2],
                                        datetime[3] + datetime[4] / 60.0, offsetSec) as Lang.Array;
        var lstDeg = localSiderealDeg(utc, lonDeg);

        var lat    = MathUtil.deg2rad(latDeg);
        var sinLat = Math.sin(lat);
        var cosLat = Math.cos(lat);

        var cat   = catalog(starMode) as Lang.Array;
        var above = 0;              // catalogue stars found above the horizon so far
        var stars = [];

        // Lines: only at full night, in Constellations and Zodiac. Figure stars
        // that are not shown are still placed (in _figurePos): up but beyond
        // the starCount or too faint near the horizon, or below the horizon,
        // so the lines to them can be drawn.
        var withLines = (starMode != MODE_BRIGHTEST) && (sunAltDeg <= FULL_NIGHT_ALT_DEG);
        var lines     = null;
        var figPos    = null;
        if (withLines) {
            lines  = lineTable(starMode);
            figPos = _figurePos;
        } else if (starMode == MODE_BRIGHTEST) {
            releaseLines();
        }

        for (var i = 0; i < cat.size(); i += 1) {
            var isFigure = withLines && i <= _lastFigureStar && _figureStar[i] != 0;
            if (withLines && i <= _lastFigureStar) { figPos[i] = 0; }

            var v      = cat[i] as Lang.Number;
            var decDeg = ((v >> 10) & 0x3FF) * DEC_STEP_DEG - 90.0;

            // Never rises at this latitude.
            if (!isFigure && (latDeg >= 0.0 ? (decDeg < latDeg - 90.0) : (decDeg > latDeg + 90.0))) { continue; }

            var h      = MathUtil.deg2rad(lstDeg - ((v >> 20) & 0x7FF) * RA_STEP_DEG);   // hour angle
            var dec    = MathUtil.deg2rad(decDeg);
            var sinDec = Math.sin(dec);
            var cosDec = Math.cos(dec);
            var cosH   = Math.cos(h);
            var sinAlt = sinLat * sinDec + cosLat * cosDec * cosH;
            var up     = (sinAlt > 0.0);
            if (!up && !isFigure) { continue; }

            var mag     = MAG_ZERO + ((v >> 3) & 0x7F) * MAG_STEP;
            var visible = false;
            if (up) {
                // The first starCount stars above the horizon make up the sky.
                // With lines, figure stars beyond them are still placed.
                above += 1;
                var extra = (above > starCount);
                if (extra) {
                    if (!withLines || i > _lastFigureStar) { break; }
                    if (!isFigure) { continue; }
                }

                // Not visible yet: too faint for the twilight sky at its height.
                var airmass  = 1.0 / (sinAlt + 0.025);
                var apparent = mag + EXTINCTION_PER_AIRMASS * (airmass - 1.0);
                visible = !extra && (apparent <= limitMag);
                if (!visible && !isFigure) { continue; }
            }

            var altDeg = MathUtil.rad2deg(Math.asin(MathUtil.clamp(sinAlt, -1.0, 1.0)));
            if (up) { altDeg += MathUtil.refractionDeg(altDeg); }

            // Direction on the face: east and north components of the star's
            // bearing, from the zenith. 12 o'clock is north. Below the horizon
            // (figure stars only) the same projection runs on past the rim.
            var east  = -cosDec * Math.sin(h);
            var north = sinDec * cosLat - cosDec * cosH * sinLat;
            var len   = Math.sqrt(east * east + north * north);
            var rho   = skyRadiusPx * (1.0 - altDeg / 90.0);
            if (up) { rho = MathUtil.clamp(rho, 0.0, skyRadiusPx); }
            var x     = cx;
            var y     = cy;
            if (len > 1e-6) {
                x += rho * east  / len;
                y -= rho * north / len;
            }
            var xi = MathUtil.roundNearest(x);
            var yi = MathUtil.roundNearest(y);

            if (visible) {
                stars.add(packStar(xi, yi, starSizeForMag(mag), v & 0x7));
            }
            if (isFigure) {
                var p = POS_PLACED | ((xi + POS_OFFSET) & 0x7FF) | (((yi + POS_OFFSET) & 0x7FF) << 11);
                if (up)      { p |= POS_UP; }
                if (visible) { p |= POS_SHOWN; }
                figPos[i] = p;
            }
        }

        if (withLines) {
            _projectedLines = projectLines(lines, cat, stars, figPos, cx, cy, skyRadiusPx);
        }
        _projectedStars = stars;
        _starColorBins  = mipMode ? null : AmoledArt.starColors();
        _lineColor      = mipMode ? MiPArt.CONSTELLATION_LINE : AmoledArt.CONSTELLATION_LINE;
        _lineAntiAlias  = !mipMode;
        _projectionKey  = key;
    }

    function packStar(x, y, size, colorBin) {
        return (x & 0x7FF) | ((y & 0x7FF) << 11) | (size << 22) | (colorBin << 24);
    }

    // Every figure line with at least one star above the horizon, cut at the
    // edge of the sky. Figure stars it reaches that are up but not yet shown
    // join the shown stars.
    function projectLines(lines, cat, stars, figPos, cx, cy, skyR) {
        var out = [];
        for (var k = 0; k < lines.size(); k += 1) {
            var ia = lines[k] & 0x1FF;
            var ib = (lines[k] >> 9) & 0x1FF;
            var pa = figPos[ia];
            var pb = figPos[ib];
            if (pa == null || pb == null || pa == 0 || pb == 0) { continue; }
            var aUp = (pa & POS_UP) != 0;
            var bUp = (pb & POS_UP) != 0;
            if (!aUp && !bUp) { continue; }
            if (aUp && (pa & POS_SHOWN) == 0) { pa = reveal(ia, pa, cat, stars, figPos); }
            if (bUp && (pb & POS_SHOWN) == 0) { pb = reveal(ib, pb, cat, stars, figPos); }
            var gapA = aUp ? LINE_GAP_PX[starSizeForMag(MAG_ZERO + ((cat[ia] >> 3) & 0x7F) * MAG_STEP)] : 0;
            var gapB = bUp ? LINE_GAP_PX[starSizeForMag(MAG_ZERO + ((cat[ib] >> 3) & 0x7F) * MAG_STEP)] : 0;
            addLine(out, (pa & 0x7FF) - POS_OFFSET, ((pa >> 11) & 0x7FF) - POS_OFFSET, gapA,
                         (pb & 0x7FF) - POS_OFFSET, ((pb >> 11) & 0x7FF) - POS_OFFSET, gapB, cx, cy, skyR);
        }
        return out;
    }

    // Show a figure star that is up: add it to the shown stars.
    function reveal(t, p, cat, stars, figPos) {
        var v = cat[t] as Lang.Number;
        stars.add(packStar((p & 0x7FF) - POS_OFFSET, ((p >> 11) & 0x7FF) - POS_OFFSET,
                           starSizeForMag(MAG_ZERO + ((v >> 3) & 0x7F) * MAG_STEP), v & 0x7));
        p |= POS_SHOWN;
        figPos[t] = p;
        return p;
    }

    // A line from (ax, ay) to (bx, by), cut to the sky disc (centre cx, cy,
    // radius skyR) and kept gapA and gapB pixels clear of its ends.
    function addLine(out, ax, ay, gapA, bx, by, gapB, cx, cy, skyR) {
        var dx   = (bx - ax).toFloat();
        var dy   = (by - ay).toFloat();
        var len2 = dx * dx + dy * dy;
        if (len2 < 1.0) { return; }
        var len = Math.sqrt(len2);

        // Where the line is inside the sky: t from lo to hi along a -> b.
        var fx   = ax - cx;
        var fy   = ay - cy;
        var bq   = fx * dx + fy * dy;
        var cq   = fx * fx + fy * fy - skyR * skyR;
        var disc = bq * bq - len2 * cq;
        if (disc <= 0.0) { return; }
        var root = Math.sqrt(disc);
        var lo   = (-bq - root) / len2;
        var hi   = (-bq + root) / len2;
        if (lo < gapA / len)       { lo = gapA / len; }
        if (hi > 1.0 - gapB / len) { hi = 1.0 - gapB / len; }
        if ((hi - lo) * len < 1.0) { return; }

        var x0 = MathUtil.roundNearest(ax + dx * lo);
        var y0 = MathUtil.roundNearest(ay + dy * lo);
        var x1 = MathUtil.roundNearest(ax + dx * hi);
        var y1 = MathUtil.roundNearest(ay + dy * hi);
        out.add((x0 & 0x7FF) | ((y0 & 0x7FF) << 11));
        out.add((x1 & 0x7FF) | ((y1 & 0x7FF) << 11));
    }

    function drawProjectedStars(dc) {
        // During a region repaint only the lines and stars inside the region
        // are drawn.
        var b = Drawing.regionBounds(3);

        if (_projectedLines.size() > 0) {
            var aa = _lineAntiAlias && (dc has :setAntiAlias);
            if (aa) { dc.setAntiAlias(true); }
            dc.setColor(_lineColor, Drawing.BLACK);
            for (var i = 0; i < _projectedLines.size(); i += 2) {
                var p0 = _projectedLines[i];
                var p1 = _projectedLines[i + 1];
                var x0 = p0 & 0x7FF;
                var y0 = (p0 >> 11) & 0x7FF;
                var x1 = p1 & 0x7FF;
                var y1 = (p1 >> 11) & 0x7FF;
                if (b != null && ((x0 < b[0] && x1 < b[0]) || (x0 > b[2] && x1 > b[2])
                               || (y0 < b[1] && y1 < b[1]) || (y0 > b[3] && y1 > b[3]))) {
                    continue;
                }
                dc.drawLine(x0, y0, x1, y1);
            }
            if (aa) { dc.setAntiAlias(false); }
        }

        for (var i = 0; i < _projectedStars.size(); i += 1) {
            var s  = _projectedStars[i];
            var x  = s & 0x7FF;
            var y  = (s >> 11) & 0x7FF;
            if (b != null && (x < b[0] || x > b[2] || y < b[1] || y > b[3])) {
                continue;
            }
            var size = (s >> 22) & 0x3;
            var bin  = (s >> 24) & 0x7;
            var color = (_starColorBins == null) ? MiPArt.starColor(size, bin) : _starColorBins[bin];
            Drawing.drawProjectedStar(dc, x, y, size, color);
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    // The faintest magnitude visible against the sky at this sun altitude.
    function limitingMagnitude(sunAltDeg) {
        if (sunAltDeg >= LIMIT_ALT_DEG[0]) { return LIMIT_MAG[0]; }
        for (var i = 1; i < LIMIT_ALT_DEG.size(); i += 1) {
            if (sunAltDeg >= LIMIT_ALT_DEG[i]) {
                var t = (LIMIT_ALT_DEG[i - 1] - sunAltDeg) / (LIMIT_ALT_DEG[i - 1] - LIMIT_ALT_DEG[i]);
                return LIMIT_MAG[i - 1] + t * (LIMIT_MAG[i] - LIMIT_MAG[i - 1]);
            }
        }
        return LIMIT_MAG[LIMIT_MAG.size() - 1];
    }

    function starSizeForMag(mag) {
        if (mag <= XL_MAG)     { return Drawing.STAR_XL; }
        if (mag <= LARGE_MAG)  { return Drawing.STAR_LARGE; }
        if (mag <= MEDIUM_MAG) { return Drawing.STAR_MEDIUM; }
        return Drawing.STAR_SMALL;
    }

    // Local sidereal time in degrees. utc = [year, month, day, utcHour].
    // Greenwich mean sidereal time is 280.46061837 + 360.98564736629 D for D
    // days from J2000.0 (2000 Jan 1, 12h UT). Whole turns are dropped before
    // multiplying, so 32-bit floats keep it to about a thousandth of a degree:
    // with D = d0 - 1.5 + utcHour / 24, where d0 counts whole days from
    // 2000 Jan 0.0, 360 D is 360 d0 - 540 + 15 utcHour, and 360 d0 is whole
    // turns.
    function localSiderealDeg(utc, lonDeg) {
        var d0 = MathUtil.daysSince2000Jan0(utc[0], utc[1], utc[2], 0.0);
        return MathUtil.wrap360(280.46061837 - 540.0
                                + 0.98564736629 * (d0 - 1.5)
                                + 15.0410686 * utc[3]
                                + lonDeg);
    }

}
