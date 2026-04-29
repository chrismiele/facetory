using Toybox.Lang;
using Toybox.Math;

module Solar {

    const SUNSET_ACCENT_ALT_DEG = 1.5;

    function solarAltAzApprox(year, month, day, clockHour, offsetSec, latDeg, lonDeg) {
        var doy     = MathUtil.dayOfYear(year, month, day);
        var yearLen = MathUtil.isLeapYear(year) ? 366.0 : 365.0;

        var lat    = MathUtil.deg2rad(latDeg);
        var sinLat = Math.sin(lat);
        var cosLat = Math.cos(lat);

        var gamma = 2.0 * Math.PI / yearLen * (doy - 1.0 + (clockHour - 12.0) / 24.0);
        var sg = Math.sin(gamma);
        var cg = Math.cos(gamma);
        var s2 = 2.0 * sg * cg;
        var c2 = 2.0 * cg * cg - 1.0;
        var s3 = s2 * cg + c2 * sg;
        var c3 = c2 * cg - s2 * sg;

        var eqtMin = 229.18 * (0.000075 + 0.001868 * cg
            - 0.032077 * sg - 0.014615 * c2 - 0.040849 * s2);

        var dec = 0.006918
            - 0.399912 * cg + 0.070257 * sg
            - 0.006758 * c2 + 0.000907 * s2
            - 0.002697 * c3 + 0.00148  * s3;

        var tzMeridianDeg = offsetSec / 240.0;
        var solarHours    = clockHour + (eqtMin + 4.0 * (lonDeg - tzMeridianDeg)) / 60.0;
        var H             = MathUtil.deg2rad(15.0 * (solarHours - 12.0));

        var sinDec = Math.sin(dec);
        var cosDec = Math.cos(dec);
        var cosH   = Math.cos(H);

        var sinAlt = MathUtil.clamp(sinLat * sinDec + cosLat * cosDec * cosH, -1.0, 1.0);
        var alt    = Math.asin(sinAlt);
        var altDeg = MathUtil.rad2deg(alt) + MathUtil.refractionDeg(MathUtil.rad2deg(alt));

        if (90.0 - altDeg < 0.1) { return [altDeg, 0.0]; }

        var cosAlt = Math.cos(alt);
        if (MathUtil.abs(cosAlt) < 1e-6) { cosAlt = (cosAlt < 0.0) ? -1e-6 : 1e-6; }

        var cosAz = MathUtil.clamp((sinDec - sinAlt * sinLat) / (cosAlt * cosLat), -1.0, 1.0);
        var az    = Math.acos(cosAz);
        if (Math.sin(H) > 0.0) { az = 2.0 * Math.PI - az; }

        return [altDeg, MathUtil.rad2deg(az)];
    }

    function projectAltAz(altDeg, azDeg, cx, cy, R) {
        var rho = MathUtil.clamp(R * (1.0 - altDeg / 90.0), 0.0, R * 2.0);
        var az  = MathUtil.deg2rad(azDeg);
        return [cx + rho * Math.sin(az), cy - rho * Math.cos(az)];
    }

    // Three MIP shades for the sun's halo at altitude, returned as
    // [OUTER, MIDDLE, CORE] in paint order (outer drawn first, core last).
    //
    // Daytime is a pure yellow dark→medium→bright ramp. Each transition
    // band uses two shades from itself (MEDIUM outer, BRIGHT middle) plus
    // a CORE carried over from the warmer phase, giving a "glowing ember"
    // centre that trails one band behind the surrounding atmosphere.
    function mipSunColorsForAlt(altDeg) {
        if (altDeg >= 6.0)   { return [Colours.MIP_SUN_DARK,      Colours.MIP_SUN_MEDIUM,    Colours.MIP_SUN_BRIGHT];     }
        if (altDeg >= 0.0)   { return [Colours.MIP_ORANGE_MEDIUM, Colours.MIP_ORANGE_BRIGHT, Colours.MIP_SUN_BRIGHT];     }
        if (altDeg >= -6.0)  { return [Colours.MIP_RED_MEDIUM,    Colours.MIP_RED_BRIGHT,    Colours.MIP_ORANGE_BRIGHT];  }
        if (altDeg >= -12.0) { return [Colours.MIP_PURPLE_MEDIUM, Colours.MIP_PURPLE_BRIGHT, Colours.MIP_RED_BRIGHT];     }
        return [Colours.MIP_BLUE_MEDIUM, Colours.MIP_BLUE_BRIGHT, Colours.MIP_PURPLE_BRIGHT];
    }

    // The band's BRIGHT shade — used as the MIP minute-text colour.
    // For daytime this is yellow (the core). For transition bands it's
    // the current band's middle ring (the dominant hue surrounding the
    // ember-coloured core).
    function mipBrightSunColorForAlt(altDeg) {
        if (altDeg >= 6.0)   { return Colours.MIP_SUN_BRIGHT;    }
        if (altDeg >= 0.0)   { return Colours.MIP_ORANGE_BRIGHT; }
        if (altDeg >= -6.0)  { return Colours.MIP_RED_BRIGHT;    }
        if (altDeg >= -12.0) { return Colours.MIP_PURPLE_BRIGHT; }
        return Colours.MIP_BLUE_BRIGHT;
    }

    // AMOLED: blended colour for the sun's body at altitude. Smooth gradient
    // between palette anchors; matches the minute-text colour after whitening.
    function sunColorForAlt(altDeg) {
        if (altDeg >= 12.0)  { return Colours.SUN_YELLOW; }
        if (altDeg >= 6.0)   { return MathUtil.blendColor(Colours.SUN_YELLOW, Colours.SUN_ORANGE, (12.0 - altDeg) / 6.0); }
        if (altDeg >= 0.0)   { return MathUtil.blendColor(Colours.SUN_ORANGE, Colours.SUN_RED,    (6.0  - altDeg) / 6.0); }
        if (altDeg >= -6.0)  { return MathUtil.blendColor(Colours.SUN_RED,    Colours.SUN_PURPLE, (-altDeg)        / 6.0); }
        if (altDeg >= -12.0) { return MathUtil.blendColor(Colours.SUN_PURPLE, Colours.SUN_BLUE,   (-6.0 - altDeg)  / 6.0); }
        return Colours.SUN_BLUE;
    }

    // Whiten sunColor by (1 - saturation) for the AMOLED minute text.
    function brightSunColor(sunColor, saturation) {
        return MathUtil.blendColor(Colours.WHITE, sunColor, MathUtil.clamp(saturation, 0.0, 1.0));
    }

    function sunsetAccentScale(sunAltDeg) {
        return MathUtil.clamp(1.0 - MathUtil.abs(sunAltDeg) / SUNSET_ACCENT_ALT_DEG, 0.0, 1.0);
    }

    function scaleColor(color, s) {
        s = MathUtil.clamp(s, 0.0, 1.0);
        var r = (((color / 65536) % 256) * s).toNumber();
        var g = (((color / 256)   % 256) * s).toNumber();
        var b = ( (color          % 256) * s).toNumber();
        return r * 65536 + g * 256 + b;
    }

}
