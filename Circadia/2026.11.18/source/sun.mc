using Toybox.Graphics;
using Toybox.Math;

// SunArt — the sun's geometry and timing, shared by both display types. The
// colours and the number of steps are display-specific and live in AmoledArt
// and MiPArt.
//
// The sun is a white disc with a coloured rim (together, the core) inside a
// corona.
//
// Sizes. On this face one degree of sun altitude is one degree of distance
// from the rim, so a circle of radius N degrees around the sun has left the
// screen when the sun is N degrees below the horizon. Each edge is sized to
// one twilight boundary, so the sun leaves the sky in three steps (and comes
// back in the same three at dawn):
//
//   white disc    6 deg radius   gone at -6, the end of civil twilight.
//                                12 deg across, exactly the largest moon
//                                setting: a large new moon in front of the
//                                sun covers the white disc and nothing more.
//   core         12 deg radius   gone at -12, the end of nautical twilight.
//                                The white disc plus the rim where white gives
//                                way to the sun's colour.
//   corona       18 deg radius   gone at -18, the end of astronomical
//                                twilight: full night, and the moment the
//                                stars reach full count.
//
// MIP draws a more compact sun: the white disc and two thin rings, the outer
// one 12 deg (see MiPArt), so it is gone at the end of nautical twilight.
//
// Timing. Each 6-degree stage has one change:
//
//   above +12     day                    white-hot centre, yellow rim
//   +12 to  +6    low sun                the white centre fades to flat yellow
//    +6 to   0    golden hour            yellow to orange; the sun starts to flatten
//     0 to  -6    civil twilight         orange to red; the white disc sets
//    -6 to -12    nautical twilight      red to purple; the core sets
//   -12 to -18    astronomical twilight  purple to blue; the corona sets
//   below -18     night                  no sun; the minute digits stay blue
//
// Horizon glow (the "Horizon glow at twilight" setting, off by default).
//
//   AMOLED: the sun itself spreads along the horizon. Every layer of the sun
//   (each step of the core and each corona ring) keeps its top edge exactly
//   where it is, at altitude h + r above the horizon on the sun's bearing,
//   while its curvature blends from its own (a circle around the sun) toward
//   that of a band of constant height through the same top point:
//
//       curvature = (1 - s) / r  -  s / (90 - (h + r))        (per degree)
//
//   s = 0 is the round sun, s = 1 a band right around the horizon. s rises
//   from 0 at +6 (end of golden hour), reaches the value at which the
//   corona's outer edge is exactly straight at -3, and SPREAD_MAX by the end
//   of nautical twilight. A larger circle needs less change to go straight,
//   so the outer corona flattens first while the white disc stays a dome
//   until it sets. Past straight, a layer curves the other way and hugs the
//   rim. Since every top edge stays put, every edge still leaves the sky at
//   its twilight boundary.
//
//   MIP: two crescents on the rim in the corona's two ring colours, starting
//   as a point just before sunset (+1.5), largest at the end of civil
//   twilight (-6) and back to a point at full night (-18). See
//   drawFlareCrescent().
module SunArt {

    const BLACK = 0x000000;

    // ── Calibrated sizes (degrees) ───────────────────────────────────────────
    const WHITE_DISC_DEG = 6.0;     // end of civil twilight; keep equal to half of config's largest moon diameter
    const CORE_DEG       = 12.0;    // end of nautical twilight; white disc plus its coloured rim
    const OUTER_DEG      = 18.0;    // end of astronomical twilight; keep equal to -Stellar.FULL_NIGHT_ALT_DEG

    // ── AMOLED: the sun spreads along the horizon ───────────────────────────
    const SPREAD_START_ALT_DEG = 6.0;     // end of golden hour: the sun starts to flatten
    const SPREAD_FLAT_ALT_DEG  = -3.0;    // the corona's outer edge is exactly straight
    const SPREAD_FULL_ALT_DEG  = -12.0;   // end of nautical twilight: as far as it goes
    const SPREAD_MAX           = 0.88;    // share of the way to a band right around the horizon
    const STRAIGHT_RADIUS_PX   = 20000.0; // flatter than this, a layer is drawn with a straight edge

    // ── MIP: edge flare ──────────────────────────────────────────────────────
    const FLARE_START_ALT_DEG = 1.5;           // keep equal to Solar.SUNSET_ACCENT_ALT_DEG (hour digits start to turn orange)
    const FLARE_PEAK_ALT_DEG  = -6.0;          // end of civil twilight
    const FLARE_END_ALT_DEG   = -OUTER_DEG;    // full night
    const FLARE_MAX_SPAN_DEG  = 65.0;          // bearing to each side of the sun, at the peak
    const FLARE_MAX_DEPTH_DEG = 10.0;          // thickness at the sun's bearing, at the peak
    const FLARE_MAX_FILL      = 0.8;           // crescent depth: fraction of the deepest circle possible
    const RIM_OVERDRAW_PX     = 3.0;           // the sky disc stops 2px short of the screen edge

    // ── White-hot core ───────────────────────────────────────────────────────
    // The white disc is pure white while the sun is high and fades to the sun's
    // own colour, leaving a flat yellow core, between +12 and +6.
    const WHITE_HOT_FULL_ALT_DEG = 12.0;
    const WHITE_HOT_GONE_ALT_DEG = 6.0;

    // Spread geometry for the frame being drawn; set by prepareSpread().
    var _spread = 0.0;    // s in the header formula; 0 = the round sun
    var _alt    = 0.0;    // sun altitude
    var _sx     = 0.0;    // sun position
    var _sy     = 0.0;
    var _cx     = 0.0;    // screen centre
    var _cy     = 0.0;
    var _R      = 0.0;    // sky radius
    var _ux     = 1.0;    // unit vector from the screen centre toward the sun
    var _uy     = 0.0;

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

    // MIP flare: 0 = no flare, 1 = full size. Rises from 0 at +1.5 to 1 at
    // the end of civil twilight, then falls back to 0 at full night.
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

    // ── AMOLED: spreading layers ─────────────────────────────────────────────

    // How far the sun has spread toward a band along the horizon (s in the
    // header formula). 0 above +6 and whenever the setting is off.
    function spreadAmount(altDeg) {
        if (!config.horizonFlare() || altDeg >= SPREAD_START_ALT_DEG) { return 0.0; }

        // The s at which the corona's outer edge (height t) is straight.
        var t     = SPREAD_FLAT_ALT_DEG + OUTER_DEG;
        var sFlat = (90.0 - t) / (90.0 - t + OUTER_DEG);

        if (altDeg >= SPREAD_FLAT_ALT_DEG) {
            return sFlat * (SPREAD_START_ALT_DEG - altDeg) / (SPREAD_START_ALT_DEG - SPREAD_FLAT_ALT_DEG);
        }
        if (altDeg > SPREAD_FULL_ALT_DEG) {
            return sFlat + (SPREAD_MAX - sFlat) * (SPREAD_FLAT_ALT_DEG - altDeg) / (SPREAD_FLAT_ALT_DEG - SPREAD_FULL_ALT_DEG);
        }
        return SPREAD_MAX;
    }

    // Remember this frame's sun for drawLayer().
    function prepareSpread(cx, cy, R, sx, sy, altDeg) {
        _cx  = cx;
        _cy  = cy;
        _R   = R;
        _sx  = sx;
        _sy  = sy;
        _alt = altDeg;

        var dx = sx - cx;
        var dy = sy - cy;
        var d  = Math.sqrt(dx * dx + dy * dy);
        if (d < 1.0) {
            _spread = 0.0;      // sun at the zenith: nothing to spread toward
            return;
        }
        _ux     = dx / d;
        _uy     = dy / d;
        _spread = spreadAmount(altDeg);
    }

    // One layer of the sun, of true radius rDeg, in the current spread (see
    // the header): a circle around the sun, a dome, a straight-edged band or a
    // band hugging the rim. Call prepareSpread() first.
    function drawLayer(dc, rDeg, color) {
        var top = _alt + rDeg;                 // height of the top edge above the horizon
        if (top <= 0.0) { return; }

        var deg = _R / 90.0;
        dc.setColor(color, BLACK);

        if (_spread <= 0.0) {
            dc.fillCircle(MathUtil.roundNearest(_sx), MathUtil.roundNearest(_sy),
                          MathUtil.roundNearest(rDeg * deg));
            return;
        }

        var k = (1.0 - _spread) / rDeg - _spread / (90.0 - top);    // curvature, per degree
        var rhoPx = (k == 0.0) ? STRAIGHT_RADIUS_PX * 2.0 : MathUtil.abs(1.0 / k) * deg;
        var topPx = (90.0 - top) * deg;        // the top edge's distance from the screen centre

        if (rhoPx >= STRAIGHT_RADIUS_PX) {
            fillBeyondLine(dc, topPx);
        } else if (k > 0.0) {
            // A dome: a circle whose centre lies rhoPx beyond the top edge.
            var dist = topPx + rhoPx;
            dc.fillCircle(MathUtil.roundNearest(_cx + dist * _ux), MathUtil.roundNearest(_cy + dist * _uy),
                          MathUtil.roundNearest(rhoPx));
        } else {
            // Hugging the rim: everything outside a circle whose centre lies
            // rhoPx back from the top edge, past the screen centre.
            fillOutsideCircle(dc, rhoPx - topPx, rhoPx);
        }
    }

    // Everything beyond a straight line square to the sun's bearing, topPx
    // from the screen centre.
    function fillBeyondLine(dc, topPx) {
        var far  = _R + 20.0;
        var vx   = -_uy;
        var vy   = _ux;
        dc.fillPolygon([
            [MathUtil.roundNearest(_cx + topPx * _ux + far * vx), MathUtil.roundNearest(_cy + topPx * _uy + far * vy)],
            [MathUtil.roundNearest(_cx + topPx * _ux - far * vx), MathUtil.roundNearest(_cy + topPx * _uy - far * vy)],
            [MathUtil.roundNearest(_cx + far * _ux - far * vx),   MathUtil.roundNearest(_cy + far * _uy - far * vy)],
            [MathUtil.roundNearest(_cx + far * _ux + far * vx),   MathUtil.roundNearest(_cy + far * _uy + far * vy)]
        ]);
    }

    // Everything inside the rim but outside the circle of radius rPx whose
    // centre is gPx from the screen centre, directly away from the sun. Drawn
    // as one thick arc around that centre, from the circle out past the rim,
    // between the two points where the circle meets the rim.
    function fillOutsideCircle(dc, gPx, rPx) {
        if (rPx >= gPx + _R) { return; }       // the circle covers the whole sky

        var beta = 180.0;                      // half-angle of the arc, seen from the circle's centre
        if (gPx >= 0.5) {
            var c = (gPx * gPx + rPx * rPx - _R * _R) / (2.0 * gPx * rPx);
            beta = MathUtil.rad2deg(Math.acos(MathUtil.clamp(c, -1.0, 1.0)));
        }

        var theta = MathUtil.rad2deg(Math.atan2(-_uy, _ux));     // the sun's bearing, as drawArc measures angles
        var start = Math.floor(theta - beta).toNumber();
        var end   = Math.ceil(theta + beta).toNumber();
        var pen   = (gPx + _R - rPx + RIM_OVERDRAW_PX + 1.0).toNumber();

        dc.setPenWidth(pen);
        dc.drawArc(
            MathUtil.roundNearest(_cx - gPx * _ux), MathUtil.roundNearest(_cy - gPx * _uy),
            MathUtil.roundNearest(rPx + 0.5 * pen),
            Graphics.ARC_COUNTER_CLOCKWISE,
            wrapDegrees(start), wrapDegrees(end)
        );
        dc.setPenWidth(1);
    }

    // ── MIP: edge flare ──────────────────────────────────────────────────────

    // Work out this frame's flare. Returns false if there is none.
    function prepareFlare(cx, cy, R, sx, sy, altDeg) {
        if (!config.horizonFlare()) { return false; }
        var f = flareStrength(altDeg);
        if (f <= 0.0) { return false; }
        _flareDepthPx = FLARE_MAX_DEPTH_DEG * f * (R / 90.0);
        if (_flareDepthPx < 1.0) { return false; }
        _flareSpan  = FLARE_MAX_SPAN_DEG * f;
        _flareTheta = MathUtil.rad2deg(Math.atan2(cy - sy, sx - cx));
        return true;
    }

    // Glow level k of `levels`, in one colour: a crescent between
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

        var e   = depth * (2.0 * R - depth) / (2.0 * (room - depth));
        var rho = R - depth + e;
        var th  = MathUtil.deg2rad(_flareTheta);
        var ex  = cx - e * Math.cos(th);
        var ey  = cy + e * Math.sin(th);

        var beta  = MathUtil.rad2deg(Math.atan2(R * Math.sin(span), R * cosS + e));
        var start = Math.floor(_flareTheta - beta).toNumber();
        var end   = Math.ceil(_flareTheta + beta).toNumber();

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

    // Whole degrees into 0..359.
    function wrapDegrees(a) {
        a = a % 360;
        if (a < 0) { a += 360; }
        return a;
    }

}
