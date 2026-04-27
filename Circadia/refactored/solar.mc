using Toybox.Graphics;
using Toybox.Math;

module Solar {

    const YELLOW = 0xFFFF00;
    const ORANGE = 0xFFAA00;
    const RED    = 0xFF0000;
    const PURPLE = 0xFF55FF;
    const BLUE   = 0x0000FF;
    const GREY   = 0x8C939C;
    const BLACK  = 0x000000;
    const WHITE  = 0xFFFFFF;

    const MIP_SUN_BRIGHT    = 0xFFFF00;
    const MIP_SUN_MEDIUM    = 0xAAAA00;
    const MIP_SUN_DARK      = 0x555500;
    const MIP_RED_BRIGHT    = 0xFF5555;
    const MIP_RED_MEDIUM    = 0xAA0000;
    const MIP_RED_DARK      = 0x550000;
    const MIP_BLUE_BRIGHT   = 0x5555FF;
    const MIP_BLUE_MEDIUM   = 0x0000AA;
    const MIP_BLUE_DARK     = 0x000055;
    const MIP_PURPLE_BRIGHT = 0xFF55FF;
    const MIP_PURPLE_MEDIUM = 0xAA00AA;
    const MIP_PURPLE_DARK   = 0x550055;
    const MIP_ORANGE_BRIGHT = 0xFFAA00;
    const MIP_ORANGE_MEDIUM = 0xAA5500;
    const MIP_ORANGE_DARK   = 0x553000;

    const SUNSET_ACCENT_COLOR   = 0xFF8A00;
    const SUNSET_ACCENT_ALT_DEG = 1.5;
    const MONTH_OFFSETS = [0.0, 31.0, 59.0, 90.0, 120.0, 151.0, 181.0, 212.0, 243.0, 273.0, 304.0, 334.0];

    function solarAltAzApprox(year, month, day, clockHour, offsetSec, latDeg, lonDeg) {
        var doy     = dayOfYear(year, month, day);
        var yearLen = isLeapYear(year) ? 366.0 : 365.0;

        var lat    = deg2rad(latDeg);
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
        var H             = deg2rad(15.0 * (solarHours - 12.0));

        var sinDec = Math.sin(dec);
        var cosDec = Math.cos(dec);
        var cosH   = Math.cos(H);

        var sinAlt = clamp(sinLat * sinDec + cosLat * cosDec * cosH, -1.0, 1.0);
        var alt    = Math.asin(sinAlt);
        var altDeg = rad2deg(alt) + refractionDeg(rad2deg(alt));

        if (90.0 - altDeg < 0.1) { return [altDeg, 0.0]; }

        var cosAlt = Math.cos(alt);
        if (abs(cosAlt) < 1e-6) { cosAlt = (cosAlt < 0.0) ? -1e-6 : 1e-6; }

        var cosAz = clamp((sinDec - sinAlt * sinLat) / (cosAlt * cosLat), -1.0, 1.0);
        var az    = Math.acos(cosAz);
        if (Math.sin(H) > 0.0) { az = 2.0 * Math.PI - az; }

        return [altDeg, rad2deg(az)];
    }

    function refractionDeg(altDeg) {
        if (altDeg < -4.0) { return 0.0; }
        return 1.02 / (60.0 * Math.tan(deg2rad(altDeg + 10.3 / (altDeg + 5.11))));
    }

    function projectAltAz(altDeg, azDeg, cx, cy, R) {
        var rho = clamp(R * (1.0 - altDeg / 90.0), 0.0, R * 2.0);
        var az  = deg2rad(azDeg);
        return [cx + rho * Math.sin(az), cy - rho * Math.cos(az)];
    }

    function mipSunColorsForAlt(altDeg) {
        if (altDeg >= 6.0)  { return [MIP_SUN_BRIGHT,    MIP_SUN_MEDIUM,    MIP_SUN_DARK]; }
        if (altDeg >= 0.0)  { return [MIP_ORANGE_BRIGHT, MIP_ORANGE_MEDIUM, MIP_ORANGE_DARK]; }
        if (altDeg >= -6.0) { return [MIP_RED_BRIGHT,    MIP_RED_MEDIUM,    MIP_RED_DARK]; }
        if (altDeg >= -12.0){ return [MIP_PURPLE_BRIGHT, MIP_PURPLE_MEDIUM, MIP_PURPLE_DARK]; }
        return [MIP_BLUE_BRIGHT, MIP_BLUE_MEDIUM, MIP_BLUE_DARK];
    }

    function mipBrightSunColorForAlt(altDeg) {
        return mipSunColorsForAlt(altDeg)[0];
    }

    // AMOLED: returns a blended colour representing the sun's colour at altitude
    function sunColorForAlt(altDeg) {
        if (altDeg >= 12.0)  { return YELLOW; }
        if (altDeg >= 6.0)   { return blendColor(YELLOW, ORANGE, (12.0 - altDeg) / 6.0); }
        if (altDeg >= 0.0)   { return blendColor(ORANGE, RED,    (6.0  - altDeg) / 6.0); }
        if (altDeg >= -6.0)  { return blendColor(RED,    PURPLE, (-altDeg)        / 6.0); }
        if (altDeg >= -12.0) { return blendColor(PURPLE, BLUE,   (-6.0 - altDeg)  / 6.0); }
        return BLUE;
    }

    function brightSunColor(sunColor, saturation) {
        return blendColor(WHITE, sunColor, clamp(saturation, 0.0, 1.0));
    }

    function sunsetAccentScale(sunAltDeg) {
        return clamp(1.0 - abs(sunAltDeg) / SUNSET_ACCENT_ALT_DEG, 0.0, 1.0);
    }

    function blendColor(c0, c1, t) {
        t = clamp(t, 0.0, 1.0);
        var r = ((c0 / 65536) % 256 + ((c1 / 65536) % 256 - (c0 / 65536) % 256) * t).toNumber();
        var g = ((c0 / 256)   % 256 + ((c1 / 256)   % 256 - (c0 / 256)   % 256) * t).toNumber();
        var b = ( c0          % 256 + ( c1           % 256 -  c0          % 256) * t).toNumber();
        return r * 65536 + g * 256 + b;
    }

    function scaleColor(color, s) {
        s = clamp(s, 0.0, 1.0);
        var r = (((color / 65536) % 256) * s).toNumber();
        var g = (((color / 256)   % 256) * s).toNumber();
        var b = ( (color          % 256) * s).toNumber();
        return r * 65536 + g * 256 + b;
    }

    function dayOfYear(year, month, day) {
        var doy = MONTH_OFFSETS[month - 1] + day.toFloat();
        if (month > 2 && isLeapYear(year)) { doy += 1.0; }
        return doy;
    }

    function isLeapYear(year) {
        if ((year % 400) == 0) { return true; }
        if ((year % 100) == 0) { return false; }
        return ((year % 4) == 0);
    }

    function clamp(x, lo, hi) {
        if (x < lo) { return lo; }
        if (x > hi) { return hi; }
        return x;
    }

    function abs(x) {
        return (x < 0.0) ? -x : x;
    }

    function deg2rad(x) { return x * Math.PI / 180.0; }
    function rad2deg(x) { return x * 180.0 / Math.PI; }
}
