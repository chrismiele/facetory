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
// On AMOLED the flare is a glow like the corona: nested crescents, each a
// little shallower and brighter than the last, all tapering to the same two
// points on the rim. On MIP it is two bands hugging the rim, in the corona's
// two ring colours.
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
    const FLARE_MAX_FILL      = 0.8;           // AMOLED crescent: fraction of the deepest circle possible
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
    // (AMOLED only needs to know whether there is a flare.)
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

    // AMOLED: glow level k of `levels`, in one colour: a crescent between
    // the rim and a slightly larger circle set back from the sun's bearing,
    // so it is deepest at the bearing and tapers to a point at each end of
    // the flare. Level 0 is the deepest; each level after it is shallower
    // (1 - k/levels of the depth), shares the same tips, and is painted
    // brighter on top. Each level is a single thick arc around that circle's
    // centre, from the circle out past the rim.
    //
    // A circle through both tips can only be so deep: as deep as a straight
    // chord between them, R(1 - cos span). The flare is kept to
    // FLARE_MAX_FILL of that, which only matters for a very young or very
    // old flare, when it is short.
    function drawFlareCrescent(dc, cx, cy, R, k, levels, color) {
        var span  = MathUtil.deg2rad(_flareSpan);
        var cosS  = Math.cos(span);
        var room  = R * (1.0 - cosS);
        var depth = _flareDepthPx;
        if (depth > FLARE_MAX_FILL * room) { depth = FLARE_MAX_FILL * room; }
        depth = depth * (1.0 - k.toFloat() / levels);
        if (depth < 0.5) { return; }

        // The inner circle: centre e behind the screen centre (away from the
        // sun), radius rho, passing through both tips and `depth` in from
        // the rim at the bearing.
        var e   = depth * (2.0 * R - depth) / (2.0 * (room - depth));
        var rho = R - depth + e;
        var th  = MathUtil.deg2rad(_flareTheta);
        var ex  = cx - e * Math.cos(th);
        var ey  = cy + e * Math.sin(th);

        // The tips, as seen from that centre. Rounded outward: past the tips
        // the arc only lies beyond the rim.
        var beta  = MathUtil.rad2deg(Math.atan2(R * Math.sin(span), R * cosS + e));
        var start = Math.floor(_flareTheta - beta).toNumber();
        var end   = Math.ceil(_flareTheta + beta).toNumber();

        // From the circle out past the rim (rim + e at the bearing).
        var pen = (depth + RIM_OVERDRAW_PX + 1.0).toNumber();

        dc.setColor(color, BLACK);
        dc.setPenWidth(pen);
        dc.drawArc(
            MathUtil.roundNearest(ex), MathUtil.roundNearest(ey),
            MathUtil.roundNearest(rho + 0.5 * pen),
            Graphics.ARC_COUNTER_CLOCKWISE,
            wrapDegrees(start), wrapDegrees(end)
        );
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
