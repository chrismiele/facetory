module config {

    // ===== ENUMS =====

    const FIELD_NONE = -1;
    const FIELD_DATE = 0;
    const FIELD_BODY_BATTERY = 1;
    const FIELD_TEMPERATURE = 2;
    const FIELD_HEART_RATE = 3;
    const FIELD_STEPS = 4;

    const UNIT_AUTO = 0;
    const UNIT_METRIC = 1;
    const UNIT_IMPERIAL = 2;

    const DISPLAY_AMOLED = 0;
    const DISPLAY_MIP = 1;

    // ===== USER-EDITABLE CHOICES =====

    const TOP_FIELD = FIELD_DATE;
    const LEFT_FIELD = FIELD_TEMPERATURE;
    const RIGHT_FIELD = FIELD_BODY_BATTERY;
    const TEMP_UNITS = UNIT_AUTO;

    const SHOW_MOON = true;
    const SHOW_STARS = true;
    const SHOW_SUN = true;
    const SHOW_FACE = true;
    const SHOW_SECONDS = false;

    const USE_GPS = true;
    const LAT_DEG = 52.09;
    const LON_DEG = 5.12;

    const STAR_COUNT = 200;
    const MINUTE_SATURATION = 0.7;
    const MIP_MODE = false;
    const SLEEP_DISPLAY_MODE = DISPLAY_MIP;

    // ===== ACCESSORS =====

    function topField() {
        return TOP_FIELD;
    }

    function leftField() {
        return LEFT_FIELD;
    }

    function rightField() {
        return RIGHT_FIELD;
    }

    function tempUnits() {
        return TEMP_UNITS;
    }

    function showMoon() {
        return SHOW_MOON;
    }

    function showStars() {
        return SHOW_STARS;
    }

    function showSun() {
        return SHOW_SUN;
    }

    function showFace() {
        return SHOW_FACE;
    }

    function showSeconds() {
        return SHOW_SECONDS;
    }

    function useGps() {
        return USE_GPS;
    }

    function latDeg() {
        return LAT_DEG;
    }

    function lonDeg() {
        return LON_DEG;
    }

    function starCount() {
        return STAR_COUNT;
    }

    function minuteSaturation() {
        return MINUTE_SATURATION;
    }

    function mipMode() {
        return MIP_MODE;
    }

    function sleepMipMode() {
        return SLEEP_DISPLAY_MODE == DISPLAY_MIP;
    }
}