using Toybox.Graphics;
using Toybox.Math;

// SunArt — the sun's geometry and timing, shared by both display types. The
// colours and the number of steps are display-specific and live in AmoledArt
// and MiPArt.
//
// The sun is a white disc with a coloured rim (together, the core) inside a
// corona, plus an edge flare after sunset.
//
// Sizes. On this face one degree of sun altitude is one degree of distance
// from the rim, so a circle of radius N degrees around the sun has left the
// screen when the sun is N degrees below the horizon.
//
//   white disc   8 deg radius   16 deg across, exactly the largest moon
//                               setting: a large new moon in front of the sun
//                               covers the white disc and nothing more.
//   core        10 deg radius   The white disc plus the rim where white gives
//                               way to the sun's colour.
//   corona      18 deg radius   The last trace leaves the screen at -18, the
//                               end of astronomical twilight: full night, and
//                               the moment the stars reach full count.
//
// MIP draws a more compact sun: the white disc and two thin rings (see
// MiPArt), gone from the screen by -12. Its flare still runs to -18.
//
// Timing. Each 6-degree stage has one change:
//
//   above +12     day                    white-hot centre, yellow rim
//   +12 to  +6    low sun                the white centre fades to flat yellow
//    +6 to   0    golden hour            yellow to orange
//     0 to  -6    civil twilight         orange to red; the flare grows
//    -6 to -12    nautical twilight      red to purple; the flare shrinks
//   -12 to -18    astronomical twilight  purple to blue; the flare shrinks to a point
//   below -18     night                  no sun; the minute digits stay blue
//
// Edge flare (the "Horizon glow at twilight" setting, off by default). A band
// of light on the rim, centred on the sun's bearing, in the sun's own colour.
// It starts as a point just before sunset, as the hour digits
// begin to turn orange (+1.5), reaches its full breadth and thickness at the
// end of civil twilight (-6), and shrinks back to a point at full night (-18).
// Breadth and thickness scale together, in a straight line with altitude.
//
// The flare is drawn as concentric arcs hugging the rim ("slices"). On AMOLED
// it is a glow like the corona: nested levels, each a little smaller and
// brighter than the last, so it fades both inward and toward its ends. On
// MIP it is two bands in the corona's two ring colours.
//
// Brightest wins. Corona rings and flare levels are painted dimmest first, so
// wherever they overlap the brighter one shows and neither cuts a gap in the
// other. The core always goes on top.
module SunArt {

    const BLACK = 0x000000;

    // ── Calibrated sizes (degrees) ───────────────────────────────────────────
    const WHITE_DISC_DEG = 8.0;     // keep equal to half of config's largest moon diameter
    const CORE_DEG       = 10.0;    // white disc plus its coloured rim
    const OUTER_DEG      = 18.0;    // keep equal to -Stellar.FULL_NIGHT_ALT_DEG

    // ── Edge flare ───────────────────────────────────────────────────────────
    const FLARE_START_ALT_DEG = 1.5;           // keep equal to Solar.SUNSET_ACCENT_ALT_DEG (hour digits start to turn orange)
    const FLARE_PEAK_ALT_DEG  = -6.0;          // end of civil twilight
    const FLARE_END_ALT_DEG   = -OUTER_DEG;    // full night
    const FLARE_MAX_SPAN_DEG  = 65.0;          // bearing to each side of the sun, at the peak
    const FLARE_MAX_DEPTH_DEG = 10.0;          // thickness at the sun's bearing, at the peak
    const RIM_OVERDRAW_PX     = 3.0;           // the sky disc stops 2px short of the screen edge

    // ── White-hot core ───────────────────────────────────────────────────────
    // The white disc is pure white while the sun is high and fades to the sun's
    // own colour, leaving a flat yellow core, between +12 and +6.
    const WHITE_HOT_FULL_ALT_DEG = 12.0;
    const WHITE_HOT_GONE_ALT_DEG = 6.0;

    // Flare geometry for the frame being drawn; set by prepareFlare().
    var _flareTheta   = 0.0;   // screen angle of the sun's bearing: 0 = 3 o'clock, counter-clockwise
    var _flareSpan    = 0.0;   // half-breadth at the rim, degrees
    var _flareDepthPx = 0.0;   // thickness at the sun's bearing, pixels

    // ── Entry point ──────────────────────────────────────────────────────────

    // (sx, sy) is the sun's projected position; it lies outside the sky disc
    // when the sun is below the horizon.
    function draw(dc, cx, cy, R, sx, sy, altDeg, mipMode) {
        if (mipMode) {
            MiPArt.drawSun(dc, cx, cy, R, sx, sy, altDeg);
        } else {
            AmoledArt.drawSun(dc, cx, cy, R, sx, sy, altDeg);
        }
    }

    // ── Calibration helpers ──────────────────────────────────────────────────

    function coronaVisible(altDeg) { return altDeg > -OUTER_DEG; }
    function coreVisible(altDeg)   { return altDeg > -CORE_DEG;  }

    // 0 = no flare, 1 = full size. Rises from 0 at +1.5 to 1 at the end of
    // civil twilight, then falls back to 0 at full night.
    function flareStrength(altDeg) {
        if (altDeg >= FLARE_START_ALT_DEG || altDeg <= FLARE_END_ALT_DEG) { return 0.0; }
        if (altDeg >= FLARE_PEAK_ALT_DEG) {
            return (FLARE_START_ALT_DEG - altDeg) / (FLARE_START_ALT_DEG - FLARE_PEAK_ALT_DEG);
        }
        return (altDeg - FLARE_END_ALT_DEG) / (FLARE_PEAK_ALT_DEG - FLARE_END_ALT_DEG);
    }

    // 1 = pure white disc, 0 = no white at all.
    function whiteHot(altDeg) {
        return MathUtil.clamp(
            (altDeg - WHITE_HOT_GONE_ALT_DEG) / (WHITE_HOT_FULL_ALT_DEG - WHITE_HOT_GONE_ALT_DEG),
            0.0, 1.0);
    }

    // ── Edge flare ───────────────────────────────────────────────────────────

    // Work out this frame's flare and return how many slices to draw it in
    // (0 = no flare). Slices are numbered from 0 at the rim inward, and each
    // is at least minSlicePx thick, so a small flare uses fewer of them.
    function prepareFlare(cx, cy, R, sx, sy, altDeg, minSlicePx, maxSlices) {
        if (!config.horizonFlare()) { return 0; }

        var f = flareStrength(altDeg);
        if (f <= 0.0) { return 0; }

        _flareDepthPx = FLARE_MAX_DEPTH_DEG * f * (R / 90.0);
        if (_flareDepthPx < 1.0) { return 0; }

        _flareSpan  = FLARE_MAX_SPAN_DEG * f;
        _flareTheta = MathUtil.rad2deg(Math.atan2(cy - sy, sx - cx));

        var slices = (_flareDepthPx / minSlicePx).toNumber();
        if (slices < 1)         { slices = 1; }
        if (slices > maxSlices) { slices = maxSlices; }
        return slices;
    }

    // MIP: band j of `bands`, one colour from the rim inward. Each band is a
    // little shorter than the one outside it, which rounds the ends off.
    function drawFlareBand(dc, cx, cy, R, j, bands, color) {
        var u = (j + 0.5) / bands;
        dc.setColor(color, BLACK);
        drawRimSlice(dc, cx, cy, R, j, bands, _flareSpan * Math.sqrt(1.0 - u * u));
        dc.setPenWidth(1);
    }

    // AMOLED: glow level k of `levels`, in one colour. Level 0 is the whole
    // flare; each level after it is smaller (1 - k/levels of the depth) and
    // is painted brighter on top. A level's outline is a half-ellipse in
    // (bearing, depth), built from the slices it reaches. Its length shrinks
    // more slowly than its depth (alongExp < 1), so the glow stays long and
    // thin and fades gently toward its ends.
    function drawFlareLevel(dc, cx, cy, R, k, levels, slices, alongExp, color) {
        var g    = 1.0 - k.toFloat() / levels;
        var span = _flareSpan * Math.pow(g, alongExp);
        dc.setColor(color, BLACK);
        for (var j = 0; j < slices; j += 1) {
            var t = (j + 0.5) / slices / g;     // depth of this slice, as a fraction of the level's
            if (t >= 1.0) { break; }
            drawRimSlice(dc, cx, cy, R, j, slices, span * Math.sqrt(1.0 - t * t));
        }
        dc.setPenWidth(1);
    }

    // Slice j of `slices`: an arc hugging the rim, `span` degrees to each side
    // of the sun's bearing, in the current colour.
    function drawRimSlice(dc, cx, cy, R, j, slices, span) {
        var start = MathUtil.roundNearest(_flareTheta - span);
        var end   = MathUtil.roundNearest(_flareTheta + span);
        if (end <= start) { return; }

        var inner = R - (j + 1) * _flareDepthPx / slices;
        var outer = R - j * _flareDepthPx / slices;
        if (j == 0) { outer = R + RIM_OVERDRAW_PX; }

        // One pixel of overlap so rounding never leaves a hairline between slices.
        var pen = (outer - inner + 1.5).toNumber();
        if (pen < 1) { pen = 1; }

        dc.setPenWidth(pen);
        dc.drawArc(
            MathUtil.roundNearest(cx), MathUtil.roundNearest(cy),
            MathUtil.roundNearest(0.5 * (inner + outer)),
            Graphics.ARC_COUNTER_CLOCKWISE,
            wrapDegrees(start), wrapDegrees(end)
        );
    }

    // Whole degrees into 0..359.
    function wrapDegrees(a) {
        a = a % 360;
        if (a < 0) { a += 360; }
        return a;
    }

}
