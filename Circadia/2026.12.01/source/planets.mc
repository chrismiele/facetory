using Toybox.Lang;
using Toybox.Math;

// The bright planets: Venus, Mars, Jupiter and Saturn, where they are right
// now for the watch's location, shown with the stars.
//
// Where. Positions follow Paul Schlyter's "How to compute planetary
// positions" (the method the moon uses): mean orbital elements of the date,
// Kepler's equation, and the largest Jupiter-Saturn perturbations. Against
// a full ephemeris this is within about 0.03 deg for these four, a tenth of
// a pixel. Computed once a minute, with the moon and sun (CircadiaView).
//
// When. A planet appears once it is bright enough to see: its magnitude
// (from its distances and phase, and for Saturn the tilt of its rings),
// dimmed near the horizon as the stars are, against the stars' naked-eye
// limit (Stellar.LIMIT_*), with one more step at sunset (SUNSET_MAG) so the
// brightest planets show before any star: Venus just after sunset, Jupiter
// a few minutes later.
//
// How. A small round disc (5 px, a pixel wider than the largest stars), as
// bright as the stars, in the planet's own colour (AmoledArt and
// MiPArt PLANET_COLORS). Saturn wears a small ring at a fixed tilt, for
// recognition rather than its true angle. Planets are drawn over the sun's
// glow (Drawing.drawSky). When figure lines are on screen, each planet
// clears a dark margin first, so lines stop short of it as they do at stars.
module Planets {

    const VENUS   = 0;
    const MARS    = 1;
    const JUPITER = 2;
    const SATURN  = 3;

    // Orbital elements of the Sun (the Earth's orbit seen from the Sun's
    // side), Venus, Mars, Jupiter and Saturn, 11 numbers each: N (2), i (2),
    // w (2), a, e (2), M (2), as value at 2000 Jan 0.0 and change per day.
    const ELEMENTS = [
          0.0,      0.0,         0.0,     0.0,        282.9404, 0.0000470935,  1.0,      0.016709, -0.000000001151, 356.0470, 0.9856002585,
         76.6799,   0.0000246590, 3.3946,  0.0000000275, 54.8910, 0.0000138374,  0.723330, 0.006773, -0.000000001302,  48.0052, 1.6021302244,
         49.5574,   0.0000211081, 1.8497, -0.0000000178, 286.5016, 0.0000292961, 1.523688, 0.093405,  0.000000002516,  18.6021, 0.5240207766,
        100.4542,   0.0000276854, 1.3030, -0.0000001557, 273.8777, 0.0000164505, 5.20256,  0.048498,  0.000000004469,  19.8950, 0.0830853001,
        113.6634,   0.0000238980, 2.4886, -0.0000001081, 339.3939, 0.0000297661, 9.55475,  0.055546, -0.000000009499, 316.9670, 0.0334442282
    ];

    // Magnitude at 1 AU from Sun and Earth, and per degree of phase angle.
    const MAG_ABS   = [-4.34, -1.51, -9.25, -9.0];
    const MAG_PHASE = [0.013, 0.016, 0.014, 0.044];

    // Limiting magnitude at sunset, the step before the stars' table
    // (Stellar.LIMIT_*), which starts at 3 deg below the horizon.
    const SUNSET_MAG = -4.5;

    // Saturn's ring, one pixel per entry around the disc's centre:
    //   bits 0-3 dx + 8, bits 4-7 dy + 8, bits 8-9 strength (1-3: a third,
    //   two thirds, all of the ring colour), bit 10 on the near side (drawn
    //   over the disc), bit 11 over the disc.
    // A 1 px ellipse, 5.5 by 2.2 px, its long axis rising 20 deg to the right,
    // its near side below. Made by tools/ring_table.py: AMOLED anti-aliased,
    // MIP plain pixels.
    const RING_AMOLED = [643, 915, 675, 372, 900, 885, 344, 601, 602, 859, 363, 604, 364, 349, 877,
                         1955, 1459, 1444, 1716, 1445, 1973, 3494, 1718, 3495, 1719, 3752, 1464,
                         4009, 3738, 3754, 1947, 1932, 1436, 1645, 1917, 1677];
    const RING_MIP    = [899, 915, 931, 884, 900, 885, 870, 857, 858, 859, 860, 861, 877, 1955,
                         1971, 1972, 1973, 1974, 4007, 1975, 4008, 4009, 3994, 1962, 1947, 1932,
                         1948, 1901, 1917, 1933];

    // Dark margin radius when figure lines are on screen, by planet.
    const MARGIN_PX = [4, 4, 4, 7];

    // Shown planets, one integer each: bits 0-10 x, bits 11-21 y (pixels),
    // bits 22-23 planet.
    var _planets    = [];
    var _colorsMip  = null;    // the display type the colours below are for
    var _colors     = null;    // disc colour, by planet
    var _corners    = null;    // AMOLED: dim corner colour, by planet; MIP: null
    var _ringColors = null;    // by (over the disc) * 3 + strength - 1
    var _ring       = null;    // RING_AMOLED or RING_MIP

    // layout = [cx, cy, skyRadiusPx]; datetime = [year, month, day, hour, min]
    // (local clock); offsetSec = the local time zone's offset from UTC.
    function update(layout, datetime, latDeg, lonDeg, offsetSec, sunAltDeg, mipMode) {
        _planets = [];
        var limit = limitingMagnitude(sunAltDeg);
        if (limit < SUNSET_MAG) { return; }      // daylight
        setColors(mipMode);

        var utc = MathUtil.utcFromLocal(datetime[0], datetime[1], datetime[2],
                                        datetime[3] + datetime[4] / 60.0, offsetSec) as Lang.Array;
        var d      = MathUtil.daysSince2000Jan0(utc[0], utc[1], utc[2], utc[3]);
        var lst    = Stellar.localSiderealDeg(utc, lonDeg);
        var sinLat = MathUtil.sinDeg(latDeg);
        var cosLat = MathUtil.cosDeg(latDeg);
        var eps    = 23.4393 - 0.0000003563 * d;     // obliquity of the ecliptic
        var sinEps = MathUtil.sinDeg(eps);
        var cosEps = MathUtil.cosDeg(eps);

        var sun = orbit(0, d);                       // the Sun from the Earth: the Earth from the Sun, reversed
        var xs  = sun[0];
        var ys  = sun[1];
        var rs  = sun[3];
        var Mj  = MathUtil.wrap360(ELEMENTS[3 * 11 + 9] + ELEMENTS[3 * 11 + 10] * d);
        var Ms  = MathUtil.wrap360(ELEMENTS[4 * 11 + 9] + ELEMENTS[4 * 11 + 10] * d);

        for (var p = VENUS; p <= SATURN; p += 1) {
            var h = orbit(p + 1, d);
            if (p >= JUPITER) { h = perturbed(p, h, Mj, Ms); }
            var r  = h[3];

            // Geocentric, ecliptic then equatorial.
            var xg = h[0] + xs;
            var yg = h[1] + ys;
            var zg = h[2];
            var xe = xg;
            var ye = yg * cosEps - zg * sinEps;
            var ze = yg * sinEps + zg * cosEps;
            var rg = Math.sqrt(xg * xg + yg * yg + zg * zg);
            var ra  = MathUtil.rad2deg(Math.atan2(ye, xe));
            var dec = Math.atan2(ze, Math.sqrt(xe * xe + ye * ye));

            // Above the horizon?
            var sinDec = Math.sin(dec);
            var cosDec = Math.cos(dec);
            var ha     = MathUtil.deg2rad(lst - ra);
            var cosH   = Math.cos(ha);
            var sinAlt = sinLat * sinDec + cosLat * cosDec * cosH;
            if (sinAlt <= 0.0) { continue; }

            // Bright enough?
            var mag = magnitude(p, r, rg, rs, xg, yg, zg, d);
            if (mag + Stellar.EXTINCTION_PER_AIRMASS * (1.0 / (sinAlt + 0.025) - 1.0) > limit) { continue; }

            // On the face, as Stellar.screenPoint places stars.
            var altDeg = MathUtil.rad2deg(Math.asin(MathUtil.clamp(sinAlt, -1.0, 1.0)));
            altDeg += MathUtil.refractionDeg(altDeg);
            var east  = -cosDec * Math.sin(ha);
            var north = sinDec * cosLat - cosDec * cosH * sinLat;
            var len   = Math.sqrt(east * east + north * north);
            var rho   = MathUtil.clamp(layout[2] * (1.0 - altDeg / 90.0), 0.0, layout[2]);
            var x = layout[0];
            var y = layout[1];
            if (len > 1e-6) {
                x += rho * east  / len;
                y -= rho * north / len;
            }
            _planets.add((MathUtil.roundNearest(x) & 0x7FF) | ((MathUtil.roundNearest(y) & 0x7FF) << 11) | (p << 22));
        }
    }

    // The faintest magnitude a planet can be seen at, by the sun's altitude:
    // SUNSET_MAG at sunset, rising evenly to the stars' first step, then the
    // stars' limit. Below SUNSET_MAG (nothing) in daylight.
    function limitingMagnitude(sunAltDeg) {
        if (sunAltDeg >= 0.0) { return SUNSET_MAG - 1.0; }
        var a0 = Stellar.LIMIT_ALT_DEG[0];
        if (sunAltDeg >= a0) {
            return SUNSET_MAG + (Stellar.LIMIT_MAG[0] - SUNSET_MAG) * (sunAltDeg / a0);
        }
        return Stellar.limitingMagnitude(sunAltDeg);
    }

    // Heliocentric ecliptic position of body b (0 the Sun's orbit, 1-4 the
    // planets) at day d: [x, y, z, r] in AU.
    function orbit(b, d) {
        var k = b * 11;
        var N = ELEMENTS[k]     + ELEMENTS[k + 1] * d;
        var i = ELEMENTS[k + 2] + ELEMENTS[k + 3] * d;
        var w = ELEMENTS[k + 4] + ELEMENTS[k + 5] * d;
        var a = ELEMENTS[k + 6];
        var e = ELEMENTS[k + 7] + ELEMENTS[k + 8] * d;
        var M = MathUtil.wrap360(ELEMENTS[k + 9] + ELEMENTS[k + 10] * d);

        // Kepler's equation, in degrees.
        var E = M + MathUtil.rad2deg(e * MathUtil.sinDeg(M) * (1.0 + e * MathUtil.cosDeg(M)));
        for (var n = 0; n < 4; n += 1) {
            E = E - (E - MathUtil.rad2deg(e * MathUtil.sinDeg(E)) - M) / (1.0 - e * MathUtil.cosDeg(E));
        }
        var xv = a * (MathUtil.cosDeg(E) - e);
        var yv = a * Math.sqrt(1.0 - e * e) * MathUtil.sinDeg(E);
        var v  = MathUtil.rad2deg(Math.atan2(yv, xv));
        var r  = Math.sqrt(xv * xv + yv * yv);

        var sinN  = MathUtil.sinDeg(N);
        var cosN  = MathUtil.cosDeg(N);
        var sinVw = MathUtil.sinDeg(v + w);
        var cosVw = MathUtil.cosDeg(v + w);
        var cosI  = MathUtil.cosDeg(i);
        return [r * (cosN * cosVw - sinN * sinVw * cosI),
                r * (sinN * cosVw + cosN * sinVw * cosI),
                r * sinVw * MathUtil.sinDeg(i),
                r];
    }

    // Jupiter and Saturn pull on each other: the largest terms, in degrees of
    // heliocentric longitude (and latitude, for Saturn), from their mean
    // anomalies Mj and Ms.
    function perturbed(p, h, Mj, Ms) {
        var r   = h[3];
        var lon = MathUtil.rad2deg(Math.atan2(h[1], h[0]));
        var lat = MathUtil.rad2deg(Math.atan2(h[2], Math.sqrt(h[0] * h[0] + h[1] * h[1])));
        if (p == JUPITER) {
            lon += -0.332 * MathUtil.sinDeg(2.0 * Mj - 5.0 * Ms - 67.6)
                   - 0.056 * MathUtil.sinDeg(2.0 * Mj - 2.0 * Ms + 21.0)
                   + 0.042 * MathUtil.sinDeg(3.0 * Mj - 5.0 * Ms + 21.0)
                   - 0.036 * MathUtil.sinDeg(Mj - 2.0 * Ms)
                   + 0.022 * MathUtil.cosDeg(Mj - Ms)
                   + 0.023 * MathUtil.sinDeg(2.0 * Mj - 3.0 * Ms + 52.0)
                   - 0.016 * MathUtil.sinDeg(Mj - 5.0 * Ms - 69.0);
        } else {
            lon +=  0.812 * MathUtil.sinDeg(2.0 * Mj - 5.0 * Ms - 67.6)
                   - 0.229 * MathUtil.cosDeg(2.0 * Mj - 4.0 * Ms - 2.0)
                   + 0.119 * MathUtil.sinDeg(Mj - 2.0 * Ms - 3.0)
                   + 0.046 * MathUtil.sinDeg(2.0 * Mj - 6.0 * Ms - 69.0)
                   + 0.014 * MathUtil.sinDeg(Mj - 3.0 * Ms + 32.0);
            lat += -0.020 * MathUtil.cosDeg(2.0 * Mj - 4.0 * Ms - 2.0)
                   + 0.018 * MathUtil.sinDeg(2.0 * Mj - 6.0 * Ms - 49.0);
        }
        var cosLat = MathUtil.cosDeg(lat);
        return [r * MathUtil.cosDeg(lon) * cosLat, r * MathUtil.sinDeg(lon) * cosLat, r * MathUtil.sinDeg(lat), r];
    }

    // Visual magnitude, from the distances to the Sun (r) and Earth (rg), the
    // Earth-Sun distance (rs) and the phase angle. Saturn adds its rings,
    // brighter the more they are open to us; (xg, yg, zg) is Saturn from the
    // Earth, ecliptic, for the ring tilt.
    function magnitude(p, r, rg, rs, xg, yg, zg, d) {
        var phase = MathUtil.rad2deg(Math.acos(MathUtil.clamp((r * r + rg * rg - rs * rs) / (2.0 * r * rg), -1.0, 1.0)));
        var mag   = MAG_ABS[p] + 5.0 * Math.log(r * rg, 10) + MAG_PHASE[p] * phase;
        if (p == VENUS) {
            mag += 0.00000042 * phase * phase * phase;
        } else if (p == SATURN) {
            var los  = MathUtil.rad2deg(Math.atan2(yg, xg));
            var las  = MathUtil.rad2deg(Math.atan2(zg, Math.sqrt(xg * xg + yg * yg)));
            var ir   = 28.06;                        // ring plane to the ecliptic
            var Nr   = 169.51 + 0.0000382 * d;       // its ascending node
            var sinB = MathUtil.sinDeg(las) * MathUtil.cosDeg(ir)
                     - MathUtil.cosDeg(las) * MathUtil.sinDeg(ir) * MathUtil.sinDeg(los - Nr);
            mag += -2.6 * MathUtil.abs(sinB) + 1.2 * sinB * sinB;
        }
        return mag;
    }

    function setColors(mipMode) {
        if (_colors != null && _colorsMip == mipMode) { return; }
        _colorsMip = mipMode;
        var ring;
        if (mipMode) {
            _colors  = MiPArt.PLANET_COLORS;
            _corners = null;
            _ring    = RING_MIP;
            ring     = MiPArt.SATURN_RING;
        } else {
            _colors  = AmoledArt.PLANET_COLORS;
            _corners = new [4];
            for (var p = 0; p < 4; p += 1) {
                _corners[p] = MathUtil.scaleColor(_colors[p], AmoledArt.STAR_CORNER);
            }
            _ring = RING_AMOLED;
            ring  = AmoledArt.SATURN_RING;
        }
        _ringColors = new [6];
        for (var k = 0; k < 3; k += 1) {
            _ringColors[k]     = MathUtil.blendColor(Drawing.BLACK, ring, (k + 1) / 3.0);
            _ringColors[3 + k] = MathUtil.blendColor(_colors[SATURN], ring, (k + 1) / 3.0);
        }
    }

    function draw(dc) {
        var n = _planets.size();
        if (n == 0) { return; }
        var b      = Drawing.regionBounds(8);
        var margin = Stellar.hasLines();
        for (var i = 0; i < n; i += 1) {
            var v = _planets[i];
            var x = v & 0x7FF;
            var y = (v >> 11) & 0x7FF;
            var p = (v >> 22) & 0x3;
            if (b != null && (x < b[0] || x > b[2] || y < b[1] || y > b[3])) { continue; }

            if (margin) {
                dc.setColor(Drawing.BLACK, Drawing.BLACK);
                dc.fillCircle(x, y, MARGIN_PX[p]);
            }
            if (p == SATURN) { drawRing(dc, x, y, false); }

            // 5x5 with the corners cut; on AMOLED the corners are dim instead.
            if (_corners != null) {
                dc.setColor(_corners[p], Drawing.BLACK);
                dc.fillRectangle(x - 2, y - 2, 5, 5);
            }
            dc.setColor(_colors[p], Drawing.BLACK);
            dc.fillRectangle(x - 2, y - 1, 5, 3);
            dc.fillRectangle(x - 1, y - 2, 3, 5);

            if (p == SATURN) { drawRing(dc, x, y, true); }
        }
    }

    // The far side of Saturn's ring (before the disc) or the near side (after).
    function drawRing(dc, x, y, near) {
        for (var k = 0; k < _ring.size(); k += 1) {
            var e = _ring[k];
            if ((((e >> 10) & 1) == 1) != near) { continue; }
            dc.setColor(_ringColors[((e >> 11) & 1) * 3 + ((e >> 8) & 3) - 1], Drawing.BLACK);
            dc.drawPoint(x + (e & 0xF) - 8, y + ((e >> 4) & 0xF) - 8);
        }
    }

}
