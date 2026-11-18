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
//   core         12 deg radius   gone at -12, the end of nautical twilight.
//                                A white disc (while the sun is high) with a
//                                thin rim where white gives way to the sun's
//                                colour.
//   white disc   10 deg radius   inside the core. 20 deg across, exactly the
//                                largest moon setting: a large new moon in
//                                front of the sun covers the white disc and
//                                nothing more. The white fades into the
//                                core's colour by +6, so this edge never
//                                shows at the horizon.
//   corona       18 deg radius   gone at -18, the end of astronomical
//                                twilight: full night, and the moment the
//                                stars reach full count.
//
// MIP draws a more compact sun: a ball the size of the white disc and two
// thin rings, to 12 and 14 deg (see MiPArt).
//
// Timing. Each 6-degree stage has one change:
//
//   above +12     day                    white-hot centre, yellow rim
//   +12 to  +6    low sun                the white centre fades to flat yellow
//    +6 to   0    golden hour            yellow to orange; the sun starts to spread
//     0 to  -6    civil twilight         orange to red
//    -6 to -12    nautical twilight      red to purple; the core sets
//   -12 to -18    astronomical twilight  purple to blue; the corona sets
//   below -18     night                  no sun; the minute digits stay blue
//
// Horizon glow. Around sunset the sun itself spreads along the horizon, on
// both display types. Every layer of
// the sun (each step of the AMOLED core and each corona ring; the MIP ball and
// both rings) keeps its top edge exactly where it is, at altitude h + r above
// the horizon on the sun's bearing, while its curvature blends from its own
// (a circle around the sun) toward that of a band of constant height through
// the same top point:
//
//       curvature = (1 - s) / r  -  s / (90 - (h + r))        (per degree)
//
// s = 0 is the round sun, s = 1 a band right around the horizon. s rises from
// 0 at +6 (end of golden hour), reaches the value at which the sun's outer
// edge (the AMOLED corona, the MIP outer ring) is exactly straight at -3,
// and SPREAD_MAX by the end of nautical twilight. A larger circle needs less
// change to go straight, so the outer layers flatten first while the white
// disc stays a dome until it sets. Past straight, a layer curves the other
// way and hugs the rim. Since every top edge stays put, every edge still
// leaves the sky when it would have as a circle.
module SunArt {

    const BLACK = 0x000000;

    // ── Calibrated sizes (degrees) ───────────────────────────────────────────
    const WHITE_DISC_DEG = 10.0;    // keep equal to half of config's largest moon diameter
    const CORE_DEG       = 12.0;    // end of nautical twilight; white disc plus its coloured rim
    const OUTER_DEG      = 18.0;    // end of astronomical twilight; keep equal to -Stellar.FULL_NIGHT_ALT_DEG

    // ── The sun spreads along the horizon ───────────────────────────────────
    const SPREAD_START_ALT_DEG = 6.0;     // end of golden hour: the sun starts to flatten
    const SPREAD_FLAT_ALT_DEG  = -3.0;    // the sun's outer edge is exactly straight
    const SPREAD_FULL_ALT_DEG  = -12.0;   // end of nautical twilight: as far as it goes
    const SPREAD_MAX           = 0.88;    // share of the way to a band right around the horizon
    const STRAIGHT_RADIUS_PX   = 20000.0; // flatter than this, a layer is drawn with a straight edge
    const RIM_OVERDRAW_PX      = 3.0;     // the sky disc stops 2px short of the screen edge

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

    // 1 = pure white disc, 0 = no white at all.
    function whiteHot(altDeg) {
        return MathUtil.clamp(
            (altDeg - WHITE_HOT_GONE_ALT_DEG) / (WHITE_HOT_FULL_ALT_DEG - WHITE_HOT_GONE_ALT_DEG),
            0.0, 1.0);
    }

    // ── Spreading layers ─────────────────────────────────────────────────────

    // How far the sun has spread toward a band along the horizon (s in the
    // header formula). 0 above +6. outerDeg is the radius of this display's
    // outermost layer.
    function spreadAmount(altDeg, outerDeg) {
        if (altDeg >= SPREAD_START_ALT_DEG) { return 0.0; }

        // The s at which the outermost layer's edge (height t) is straight.
        var t     = SPREAD_FLAT_ALT_DEG + outerDeg;
        var sFlat = (90.0 - t) / (90.0 - t + outerDeg);

        if (altDeg >= SPREAD_FLAT_ALT_DEG) {
            return sFlat * (SPREAD_START_ALT_DEG - altDeg) / (SPREAD_START_ALT_DEG - SPREAD_FLAT_ALT_DEG);
        }
        if (altDeg > SPREAD_FULL_ALT_DEG) {
            return sFlat + (SPREAD_MAX - sFlat) * (SPREAD_FLAT_ALT_DEG - altDeg) / (SPREAD_FLAT_ALT_DEG - SPREAD_FULL_ALT_DEG);
        }
        return SPREAD_MAX;
    }

    // Remember this frame's sun for drawLayer(). outerDeg: the radius of the
    // display's outermost layer (OUTER_DEG on AMOLED, MiPArt.OUTER_RING_DEG).
    function prepareSpread(cx, cy, R, sx, sy, altDeg, outerDeg) {
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
        _spread = spreadAmount(altDeg, outerDeg);
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

    // Whole degrees into 0..359.
    function wrapDegrees(a) {
        a = a % 360;
        if (a < 0) { a += 360; }
        return a;
    }

}
