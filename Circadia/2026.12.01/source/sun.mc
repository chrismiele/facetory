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
// screen when the sun is N degrees below the horizon. The full-size (Large)
// sun has each edge sized to a twilight boundary:
//
//   core         12 deg radius   gone at -12, the end of nautical twilight.
//                                A white disc (while the sun is high) with a
//                                thin rim where white gives way to the sun's
//                                colour.
//   white disc   10 deg radius   inside the core; 20 deg across, the size of
//                                the Large moon. The white has faded into the
//                                core's colour by sunset, so it never shows
//                                as an edge at the horizon.
//   corona       18 deg radius   gone at -18, the end of astronomical
//                                twilight: full night.
//
// "Sun and moon size" scales every edge by sizeScale(), so the white disc
// always matches the moon. A smaller sun would set before full night, so
// through twilight its outer edge widens to 18 deg (glowOuterDeg()): every
// size glows at the horizon until full night, and the stage of twilight is
// told by the sun's colour. The timing of the spread below stays tied to the
// full-size sun.
//
// MIP draws a more compact sun: flat bands of colour, 14 deg across by day
// at full size, that flow from yellow to blue as the sun goes down, in step
// with the AMOLED colours (see MiPArt).
//
// Timing. Each 6-degree stage has one change:
//
//   above  +6     day                    white-hot centre, yellow rim
//    +6 to   0    golden hour            the sun turns yellow to orange while its
//                                        white centre fades into it, ending orange
//                                        without a flat-yellow stage; from +3 the
//                                        sun starts to spread
//     0 to  -6    civil twilight         orange to red; the sun's outer edge
//                                        goes straight
//    -6 to -12    nautical twilight      red to purple; the core sets
//   -12 to -18    astronomical twilight  purple to blue; the corona sets
//   below -18     night                  no sun; the minute digits stay blue
//
// Horizon glow. Around sunset the sun itself spreads along the horizon, on
// both display types. Every layer of the sun (each step of the AMOLED core
// and each corona ring; each MIP band) keeps its top edge exactly where it is, at altitude h + r above
// the horizon on the sun's bearing, while its curvature blends from its own
// (a circle around the sun) toward that of a band of constant height through
// the same top point:
//
//       curvature = (1 - s) / r  -  s / (90 - (h + r))        (per degree)
//
// s = 0 is the round sun, s = 1 a band of even depth right around the
// horizon (the limit: past 1 the shape would wrap round to the far side). s
// rises from 0 at +3 (half way through golden hour, as the sun nears the
// horizon) to the value at which the sun's outer edge (the AMOLED corona, the
// outermost MIP band) is exactly straight at the end of civil twilight (-6). A
// larger circle needs less change to go straight, so the outer layers
// flatten first while the white disc stays a dome until it sets.
//
// Past straight, a layer curves the other way and hugs the rim. From there s
// is set by how far along the horizon the outer edge reaches: where it meets
// the rim, measured either side of the sun's bearing (on this face, the angle
// around the centre is the compass bearing, so this is degrees of azimuth).
// The reach widens from where the straight edge meets the rim at -6 (about
// +/-30 deg) to +/-60 deg at the end of nautical twilight and +/-90 deg, a
// whole half of the horizon, as the glow sets at full night: lower and wider
// as it fades. Inner layers take the same s and so curve less, which tapers
// the glow toward its ends. Since every top edge stays put, every edge still
// leaves the sky when it would have as a circle.
module SunArt {

    const BLACK = 0x000000;

    // ── Calibrated sizes (degrees) ───────────────────────────────────────────
    // Sizes of the Large sun ("Sun and moon size"); the smaller sizes scale
    // every edge by sizeScale(). The timing of twilight never scales: it is
    // tied to CORE_DEG (end of nautical twilight) and OUTER_DEG (full night).
    const WHITE_DISC_DEG = 10.0;    // keep equal to half of config's largest moon diameter
    const CORE_DEG       = 12.0;    // end of nautical twilight; white disc plus its coloured rim
    const OUTER_DEG      = 18.0;    // end of astronomical twilight; keep equal to -Stellar.LIMIT_ALT_DEG's last

    // ── The sun spreads along the horizon ───────────────────────────────────
    const SPREAD_START_ALT_DEG = 3.0;     // late golden hour: the sun starts to flatten
    const SPREAD_FLAT_ALT_DEG  = -6.0;    // end of civil twilight: the sun's outer edge is exactly straight
    // Past straight, how far either side of the sun's bearing the outer edge
    // meets the rim (degrees of azimuth): this much at the end of nautical
    // twilight (-CORE_DEG), and REACH_NIGHT_DEG as it sets at full night
    // (-OUTER_DEG).
    const REACH_NAUTICAL_DEG   = 60.0;
    const REACH_NIGHT_DEG      = 90.0;
    // A layer edge flatter than this many sky radii is drawn as a polygon,
    // not a circle or arc: near the end of civil twilight a nearly straight
    // edge would otherwise be a circle thousands of pixels across, which
    // some watches (the Forerunner 165) draw as a bar across the screen.
    // Kept to this, no circle or arc reaches past about 5 sky radii.
    const POLYGON_RADIUS_R     = 2.0;
    const POLYGON_ERROR_PX     = 0.4;     // the most a polygon edge strays from the true curve
    const RIM_OVERDRAW_PX      = 3.0;     // the sky disc stops 2px short of the screen edge
    const MAX_ARC_HALF_DEG     = 179.0;   // a band hugging the rim never closes into a full ring

    // ── White-hot core ───────────────────────────────────────────────────────
    // The white disc is pure white while the sun is high and fades into the
    // sun's own colour during golden hour, from +6 to sunset, in step with
    // that colour turning from yellow to orange.
    const WHITE_HOT_FULL_ALT_DEG = 6.0;
    const WHITE_HOT_GONE_ALT_DEG = 0.0;

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
        var scale = sizeScale();
        if (mipMode) {
            MiPArt.drawSun(dc, cx, cy, R, sx, sy, altDeg, scale);
        } else {
            AmoledArt.drawSun(dc, cx, cy, R, sx, sy, altDeg, scale);
        }
    }

    // ── Calibration helpers ──────────────────────────────────────────────────

    // The "Sun and moon size" setting as a share of the Large sun: the white
    // disc always matches the moon (Small 0.75, Medium 0.875, Large 1).
    function sizeScale() {
        return config.moonDiameterDeg() / (2.0 * WHITE_DISC_DEG);
    }

    // The sun's outer edge. A smaller sun's glow would set before full night,
    // so through twilight its edge widens evenly from baseDeg at sunset to
    // OUTER_DEG at full night: every size keeps glowing at the horizon until
    // full night begins, and the stage of twilight is told by its colour.
    // The Large sun (baseDeg = OUTER_DEG) never widens.
    function glowOuterDeg(baseDeg, altDeg) {
        return baseDeg + (OUTER_DEG - baseDeg) * MathUtil.clamp(-altDeg / OUTER_DEG, 0.0, 1.0);
    }

    // 1 = pure white disc, 0 = no white at all.
    function whiteHot(altDeg) {
        return MathUtil.clamp(
            (altDeg - WHITE_HOT_GONE_ALT_DEG) / (WHITE_HOT_FULL_ALT_DEG - WHITE_HOT_GONE_ALT_DEG),
            0.0, 1.0);
    }

    // ── Spreading layers ─────────────────────────────────────────────────────

    // How far the sun has spread toward a band along the horizon (s in the
    // header formula). 0 above +3. outerDeg is the radius of this display's
    // outermost layer.
    function spreadAmount(altDeg, outerDeg) {
        if (altDeg >= SPREAD_START_ALT_DEG) { return 0.0; }

        // Down to -6: s rises evenly to the value at which the outermost
        // layer's edge (top at height t) is straight.
        if (altDeg >= SPREAD_FLAT_ALT_DEG) {
            var t     = SPREAD_FLAT_ALT_DEG + outerDeg;
            var sFlat = (90.0 - t) / (90.0 - t + outerDeg);
            return sFlat * (SPREAD_START_ALT_DEG - altDeg) / (SPREAD_START_ALT_DEG - SPREAD_FLAT_ALT_DEG);
        }

        // Past straight: the s that makes the outermost edge meet the rim at
        // horizonReach() either side of the sun's bearing. That edge's top is
        // d from the centre (degrees; the rim is at 90). A circle through it,
        // curving back around the centre, that meets the rim at reach phi has
        // radius rho = (180 d cos phi - d^2 - 8100) / (180 cos phi - 2 d),
        // and the header formula gives curvature -1/rho at
        // s = (1/r + 1/rho) / (1/r + 1/d).
        var top = altDeg + outerDeg;
        if (top <= 0.0) { return 0.0; }        // the whole sun has set
        var d   = 90.0 - top;
        var c   = MathUtil.cosDeg(horizonReach(altDeg, outerDeg));
        var den = 180.0 * c - 2.0 * d;
        if (den >= 0.0) { return d / (d + outerDeg); }     // exactly straight
        var rho = (180.0 * d * c - d * d - 8100.0) / den;
        return (1.0 / outerDeg + 1.0 / rho) / (1.0 / outerDeg + 1.0 / d);
    }

    // Past -6, how far either side of the sun's bearing the outermost edge
    // meets the rim (degrees of azimuth): from where the straight edge meets
    // it at -6, evenly out to REACH_NAUTICAL_DEG at -12, then on to
    // REACH_NIGHT_DEG at -18.
    function horizonReach(altDeg, outerDeg) {
        var nautical = -CORE_DEG;
        if (altDeg >= nautical) {
            var t        = SPREAD_FLAT_ALT_DEG + outerDeg;
            var straight = MathUtil.rad2deg(Math.acos((90.0 - t) / 90.0));
            return straight + (REACH_NAUTICAL_DEG - straight)
                * (SPREAD_FLAT_ALT_DEG - altDeg) / (SPREAD_FLAT_ALT_DEG - nautical);
        }
        var u = MathUtil.clamp((nautical - altDeg) / (OUTER_DEG - CORE_DEG), 0.0, 1.0);
        return REACH_NAUTICAL_DEG + (REACH_NIGHT_DEG - REACH_NAUTICAL_DEG) * u;
    }

    // Remember this frame's sun for drawLayer(). outerDeg: the radius of the
    // display's outermost layer this frame (see glowOuterDeg()).
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
    // the header): a circle around the sun, a dome, a band with a nearly
    // straight edge (a polygon) or a band hugging the rim. Call
    // prepareSpread() first.
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

        var k     = (1.0 - _spread) / rDeg - _spread / (90.0 - top);    // curvature, per degree
        var kPx   = k / deg;                   // per pixel
        var topPx = (90.0 - top) * deg;        // the top edge's distance from the screen centre

        if (MathUtil.abs(kPx) * POLYGON_RADIUS_R * _R <= 1.0) {
            fillBeyondCurve(dc, topPx, kPx);
            return;
        }
        var rhoPx = MathUtil.abs(1.0 / kPx);
        if (k > 0.0) {
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

    // Everything beyond a gently curved edge square to the sun's bearing,
    // through the point topPx from the screen centre, with curvature kPx (per
    // pixel; above 0 it bows toward the sun, below 0 toward the centre, 0 is
    // straight). The edge is cut into as few straight pieces as keep it within
    // POLYGON_ERROR_PX of the curve, and each piece is filled out past the rim
    // as its own four-sided strip, so every polygon is convex. |kPx| is at
    // most 1 / (POLYGON_RADIUS_R * _R), so the edge never folds back within
    // the sky.
    function fillBeyondCurve(dc, topPx, kPx) {
        var far = _R + 20.0;                   // half-width covered across the bearing
        var out = 2.0 * _R + 20.0;             // the strips' far end, from the screen centre
        var vx  = -_uy;
        var vy  = _ux;
        var n   = Math.ceil(2.0 * far * Math.sqrt(MathUtil.abs(kPx) / (8.0 * POLYGON_ERROR_PX))).toNumber();
        if (n < 1) { n = 1; }
        var p0 = null;
        var q0 = null;
        for (var j = 0; j <= n; j += 1) {
            var v   = far * (2.0 * j / n - 1.0);
            var kv  = kPx * v;
            var sag = kv * v / (1.0 + Math.sqrt(1.0 - kv * kv));    // the curve's depth at v, either sign
            var p = [MathUtil.roundNearest(_cx + (topPx + sag) * _ux + v * vx),
                     MathUtil.roundNearest(_cy + (topPx + sag) * _uy + v * vy)];
            var q = [MathUtil.roundNearest(_cx + out * _ux + v * vx),
                     MathUtil.roundNearest(_cy + out * _uy + v * vy)];
            if (p0 != null) { dc.fillPolygon([p0, p, q, q0]); }
            p0 = p;
            q0 = q;
        }
    }

    // Everything inside the rim but outside the circle of radius rPx whose
    // centre is gPx from the screen centre, directly away from the sun. Drawn
    // as one thick arc around that centre, from the circle out past the rim,
    // between the two points where the circle meets the rim.
    function fillOutsideCircle(dc, gPx, rPx) {
        if (rPx >= gPx + _R) { return; }       // the circle covers the whole sky

        // Half-angle of the arc, seen from the circle's centre (law of cosines,
        // written so it stays accurate when that centre is a fraction of a
        // pixel from the screen centre, as it is just before full night).
        // Kept under 180 so the arc's ends never meet.
        var beta = MAX_ARC_HALF_DEG;
        if (gPx > 0.0) {
            var c = (gPx * gPx + (rPx - _R) * (rPx + _R)) / (2.0 * gPx * rPx);
            beta = MathUtil.rad2deg(Math.acos(MathUtil.clamp(c, -1.0, 1.0)));
            if (beta > MAX_ARC_HALF_DEG) { beta = MAX_ARC_HALF_DEG; }
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
