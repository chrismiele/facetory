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
// Constellation lines (Constellations only). Faint lines join the stars of
// the well-known figures, drawn under the stars and stopping just short of
// them. A figure's lines appear only once every one of its stars is on
// screen, so a figure is drawn the moment its last star appears, and goes
// when its first star sets or fades. Each figure has two sets of lines
// (resources/jsonData/stars_lines.json): its core shape, such as Orion's
// hourglass or the Big Dipper, and its full figure, which also needs its
// fainter stars. The fullest complete set is drawn, so with "Lots" a figure
// first appears as its core shape and fills out later in twilight.
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

    // Lines stop this many pixels short of a star's centre, by star size
    // (Drawing.STAR_*), and are left out if nothing would remain.
    const LINE_GAP_PX = [3, 4, 4, 5];

    // Each line is one integer: bits 0-8 and 9-17 are the constellations
    // table indices of its ends, bits 18-24 the figure, bit 25 the set
    // (0 = core shape, 1 = full figure). Lines are grouped by figure, core
    // set first.
    const LINE_FIGURE_SHIFT = 18;
    const LINE_FULL_SHIFT   = 25;

    var _catalog        = null;
    var _catalogMode    = -1;
    var _lineTable      = null;
    var _projectedStars = [];
    var _projectedLines = [];      // x0, y0, x1, y1 for each line to draw
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
            _catalog     = null;
            _catalog     = WatchUi.loadResource(mode == MODE_CONSTELLATIONS
                               ? Rez.JsonData.StarsConstellations
                               : Rez.JsonData.StarsBrightest) as Lang.Array;
            _catalogMode = mode;
        }
        return _catalog;
    }

    function lineTable() {
        if (_lineTable == null) {
            _lineTable = WatchUi.loadResource(Rez.JsonData.StarLines) as Lang.Array;
        }
        return _lineTable;
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

        var utc = MathUtil.utcFromLocal(datetime[0], datetime[1], datetime[2],
                                        datetime[3] + datetime[4] / 60.0, offsetSec) as Lang.Array;
        var lstDeg = localSiderealDeg(utc, lonDeg);

        var lat    = MathUtil.deg2rad(latDeg);
        var sinLat = Math.sin(lat);
        var cosLat = Math.cos(lat);

        var amoledColors = mipMode ? null : AmoledArt.starColors();
        var cat          = catalog(starMode) as Lang.Array;
        var above        = 0;       // catalogue stars found above the horizon so far
        var stars        = [];

        // For lines: for each table entry, 1 + its place in stars (0 = not shown).
        var withLines = (starMode == MODE_CONSTELLATIONS);
        var shownAt   = withLines ? new [cat.size()]b : null;

        for (var i = 0; i < cat.size(); i += 1) {
            var v      = cat[i] as Lang.Number;
            var decDeg = ((v >> 10) & 0x3FF) * DEC_STEP_DEG - 90.0;

            // Never rises at this latitude.
            if (latDeg >= 0.0 ? (decDeg < latDeg - 90.0) : (decDeg > latDeg + 90.0)) { continue; }

            var h      = MathUtil.deg2rad(lstDeg - ((v >> 20) & 0x7FF) * RA_STEP_DEG);   // hour angle
            var dec    = MathUtil.deg2rad(decDeg);
            var sinDec = Math.sin(dec);
            var cosDec = Math.cos(dec);
            var cosH   = Math.cos(h);
            var sinAlt = sinLat * sinDec + cosLat * cosDec * cosH;
            if (sinAlt <= 0.0) { continue; }

            // The first starCount stars above the horizon make up the sky.
            above += 1;
            if (above > starCount) { break; }

            // Not visible yet: too faint for the twilight sky at its height.
            var mag      = MAG_ZERO + ((v >> 3) & 0x7F) * MAG_STEP;
            var airmass  = 1.0 / (sinAlt + 0.025);
            var apparent = mag + EXTINCTION_PER_AIRMASS * (airmass - 1.0);
            if (apparent > limitMag) { continue; }

            var altDeg = MathUtil.rad2deg(Math.asin(sinAlt));
            altDeg += MathUtil.refractionDeg(altDeg);

            // Direction on the face: east and north components of the star's
            // bearing, from the zenith. 12 o'clock is north.
            var east  = -cosDec * Math.sin(h);
            var north = sinDec * cosLat - cosDec * cosH * sinLat;
            var len   = Math.sqrt(east * east + north * north);
            var rho   = MathUtil.clamp(skyRadiusPx * (1.0 - altDeg / 90.0), 0.0, skyRadiusPx);
            var x     = cx;
            var y     = cy;
            if (len > 1e-6) {
                x += rho * east  / len;
                y -= rho * north / len;
            }

            var size     = starSizeForMag(mag);       // fixed per star, whatever its height
            var colorBin = v & 0x7;
            var color    = mipMode ? MiPArt.starColor(size, colorBin) : amoledColors[colorBin];
            stars.add([MathUtil.roundNearest(x), MathUtil.roundNearest(y), size, color]);
            if (withLines) { shownAt[i] = stars.size(); }
        }

        _projectedStars = stars;
        _projectedLines = withLines ? projectLines(stars, shownAt) : [];
        _lineColor      = mipMode ? MiPArt.CONSTELLATION_LINE : AmoledArt.CONSTELLATION_LINE;
        _lineAntiAlias  = !mipMode;
        _projectionKey  = key;
    }

    // The lines to draw: for each figure, its full set if every one of its
    // stars is shown, else its core set if that is complete, else none.
    function projectLines(stars, shownAt) {
        var lines = lineTable();
        var n     = lines.size();
        var out   = [];
        var i     = 0;
        while (i < n) {
            var figure  = (lines[i] >> LINE_FIGURE_SHIFT) & 0x7F;
            var fullAt  = -1;            // first line of the full set
            var coreOk  = true;
            var fullOk  = true;
            var j       = i;
            while (j < n && ((lines[j] >> LINE_FIGURE_SHIFT) & 0x7F) == figure) {
                var v    = lines[j];
                var both = shownAt[v & 0x1FF] != 0 && shownAt[(v >> 9) & 0x1FF] != 0;
                if (((v >> LINE_FULL_SHIFT) & 1) == 0) {
                    if (!both) { coreOk = false; }
                } else {
                    if (fullAt < 0) { fullAt = j; }
                    if (!both) { fullOk = false; }
                }
                j += 1;
            }
            if (fullAt >= 0 && fullOk) {
                addLines(out, lines, fullAt, j, stars, shownAt);
            } else if (coreOk && (fullAt < 0 ? j : fullAt) > i) {
                addLines(out, lines, i, (fullAt < 0) ? j : fullAt, stars, shownAt);
            }
            i = j;
        }
        return out;
    }

    // Lines from..to-1, each shortened at both ends to clear its stars.
    function addLines(out, lines, from, to, stars, shownAt) {
        for (var k = from; k < to; k += 1) {
            var v  = lines[k];
            var a  = stars[shownAt[v & 0x1FF] - 1] as Lang.Array;
            var b  = stars[shownAt[(v >> 9) & 0x1FF] - 1] as Lang.Array;
            var dx = (b[0] - a[0]).toFloat();
            var dy = (b[1] - a[1]).toFloat();
            var len  = Math.sqrt(dx * dx + dy * dy);
            var gapA = LINE_GAP_PX[a[2]];
            var gapB = LINE_GAP_PX[b[2]];
            if (len <= gapA + gapB + 1) { continue; }
            out.add(MathUtil.roundNearest(a[0] + dx * gapA / len));
            out.add(MathUtil.roundNearest(a[1] + dy * gapA / len));
            out.add(MathUtil.roundNearest(b[0] - dx * gapB / len));
            out.add(MathUtil.roundNearest(b[1] - dy * gapB / len));
        }
    }

    function drawProjectedStars(dc) {
        // During a region repaint only the lines and stars inside the region
        // are drawn.
        var b = Drawing.regionBounds(3);

        if (_projectedLines.size() > 0) {
            var aa = _lineAntiAlias && (dc has :setAntiAlias);
            if (aa) { dc.setAntiAlias(true); }
            dc.setColor(_lineColor, Drawing.BLACK);
            for (var i = 0; i < _projectedLines.size(); i += 4) {
                var x0 = _projectedLines[i];
                var y0 = _projectedLines[i + 1];
                var x1 = _projectedLines[i + 2];
                var y1 = _projectedLines[i + 3];
                if (b != null && ((x0 < b[0] && x1 < b[0]) || (x0 > b[2] && x1 > b[2])
                               || (y0 < b[1] && y1 < b[1]) || (y0 > b[3] && y1 > b[3]))) {
                    continue;
                }
                dc.drawLine(x0, y0, x1, y1);
            }
            if (aa) { dc.setAntiAlias(false); }
        }
        for (var i = 0; i < _projectedStars.size(); i += 1) {
            var s = _projectedStars[i] as Lang.Array;
            if (b != null && (s[0] < b[0] || s[0] > b[2] || s[1] < b[1] || s[1] > b[3])) {
                continue;
            }
            Drawing.drawProjectedStar(dc, s[0], s[1], s[2], s[3]);
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
