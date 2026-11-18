using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;

// CircadiaView — the watch face's update loop.
//
// The system calls onUpdate once a second while the watch is awake and once a
// minute in low power. MIP watches also get onPartialUpdate once a second in
// low power. This class decides what needs recomputing on each call and hands
// the drawing to Drawing; the data fields live in DataFields and the moon in
// MoonArt.
//
// Two caches keep the per-frame work small:
//   astronomy  sun and moon positions and colours, recomputed when the minute
//              (or the display type) changes
//   sky        screen positions of sun, moon and stars, rebuilt from the
//              astronomy when it changes or the screen size changes
class CircadiaView extends WatchUi.WatchFace {

    var _latDeg;
    var _lonDeg;

    var _isSleeping = false;

    // From this second of each minute, next minute's star sky is built ahead.
    const PREBUILD_SEC = 40;
    var _aheadMin = -1;

    // ── Astronomy cache (per minute) ─────────────────────────────────────────
    var _cacheYear  = -1;
    var _cacheMonth = -1;
    var _cacheDay   = -1;
    var _cacheHour  = -1;
    var _cacheMin   = -1;
    var _cacheMipMode = false;

    var _sunColor              = AmoledArt.WHITE;
    var _cachedSunAltAz        = [0.0, 0.0];
    var _cachedSunsetAccent    = 0.0;
    var _cachedMoonAltAz       = [0.0, 0.0];
    var _cachedMoonDiameterDeg = 12.0;
    var _cachedMoonPhaseAngle  = 0.0;
    var _cachedMoonPhaseBin    = Lunar.PHASE_NEW;

    // ── Sky cache (screen positions) ─────────────────────────────────────────
    var _cachedLayoutW = -1.0;
    var _cachedLayoutH = -1.0;
    var _layoutCache   = [0.0, 0.0, 0.0];
    var _skyCache      = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Lunar.PHASE_NEW];
    var _skyStale      = true;   // astronomy or layout changed since _skyCache was built

    // True when the data fields have not been refreshed for the current
    // minute. They are only fetched while they are on screen.
    var _fieldsStale = true;

    // [hour, min, sec] of the last full paint; reused by region repaints so the
    // clock digits match what is on screen.
    var _sceneTime = [0, 0, 0];

    function initialize() {
        WatchFace.initialize();
        _latDeg = config.latDeg();
        _lonDeg = config.lonDeg();
    }

    function onLayout(dc) {}
    function onHide() {}

    function onShow() {
        updateLocation();
    }

    // Repaint straight away on either transition so the face switches between
    // its awake and low-power layouts without waiting for the next minute.
    function onExitSleep() {
        _isSleeping = false;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() {
        _isSleeping = true;
        WatchUi.requestUpdate();
    }

    function onSettingsChanged() {
        _cacheMin = -1;
        DataFields.onSettingsChanged();
        updateLocation();
    }

    function updateLocation() {
        var loc = LocationService.getBest();
        _latDeg = loc[0];
        _lonDeg = loc[1];
    }

    // ── Full update ──────────────────────────────────────────────────────────

    function onUpdate(dc) {
        updateLayoutCache(dc);

        var now = Time.now();
        var g = Gregorian.info(now, Time.FORMAT_SHORT);
        var t = System.getClockTime();

        var showSky    = config.showSky(_isSleeping);
        var showFace   = config.showFace(_isSleeping);
        var showFields = config.showFields(_isSleeping);
        var mipMode    = config.mipMode();

        if (g.year != _cacheYear || g.month != _cacheMonth || g.day != _cacheDay ||
            t.hour != _cacheHour || t.min != _cacheMin || mipMode != _cacheMipMode) {

            updateAstronomy(g, t, mipMode);
            _skyStale    = true;
            _fieldsStale = true;

            _cacheYear    = g.year;
            _cacheMonth   = g.month;
            _cacheDay     = g.day;
            _cacheHour    = t.hour;
            _cacheMin     = t.min;
            _cacheMipMode = mipMode;
        }

        if (showFields) {
            if (_fieldsStale) {
                DataFields.refreshMinute(now, g, _latDeg, _lonDeg);
                _fieldsStale = false;
            } else {
                DataFields.refreshLive();
            }
        }

        Stellar.setLowPower(_isSleeping);
        if (showSky && _skyStale) {
            updateSkyCache(g, t);
            _skyStale = false;
        }

        // The star sky is built a bounded step per update (see Stellar), so
        // no single update runs long enough to trip the watchdog. Skies are
        // built ahead so each is ready the moment its minute starts: while
        // awake, next minute's from late in this minute; in low power (an
        // update a minute), the one a few minutes on.
        if (showSky && config.showStars()) {
            if (_isSleeping) {
                prepareNextSky(now, t, Stellar.leadMinutes());
            } else if (t.sec >= PREBUILD_SEC && t.min != _aheadMin) {
                _aheadMin = t.min;
                prepareNextSky(now, t, 1);
            }
            Stellar.continueWork();
        }

        _sceneTime = [t.hour, t.min, t.sec];

        if (showSky) {
            Drawing.drawSky(
                dc, _skyCache,
                config.showSun(), config.showMoon(), config.showStars(),
                mipMode
            );
        } else {
            Drawing.clearScreen(dc);
        }

        if (showFace) {
            Drawing.drawFace(
                dc, _layoutCache,
                _sceneTime,
                config.showSeconds() && showFields, _cachedSunsetAccent, _sunColor,
                showFields ? DataFields.texts() : [null, null, null],
                mipMode
            );
        }
    }

    // ── Per-second update in low power (MIP only) ────────────────────────────

    // AMOLED watches never get partial updates. The minute's full frame is
    // already on screen; this adds the new second tick and repaints any fast
    // field whose text actually changed. Everything else is left untouched to
    // stay inside the system's power budget for partial updates.
    function onPartialUpdate(dc) {
        if (!config.showFace(_isSleeping) || !config.showFields(_isSleeping)) { return; }

        var showSeconds = config.showSeconds();
        var anyFast     = DataFields.anyFast();

        if (!anyFast && !showSeconds) { return; }

        updateLayoutCache(dc);

        if (showSeconds) {
            Drawing.drawSecondTickClipped(dc, _layoutCache, System.getClockTime().sec);
        }

        if (!anyFast) { return; }

        var oldTop   = DataFields.text(Drawing.FIELD_SLOT_TOP);
        var oldLeft  = DataFields.text(Drawing.FIELD_SLOT_LEFT);
        var oldRight = DataFields.text(Drawing.FIELD_SLOT_RIGHT);

        DataFields.refreshLive();

        var mipMode = config.mipMode();
        repaintFieldIfChanged(dc, Drawing.FIELD_SLOT_TOP,   oldTop,   mipMode);
        repaintFieldIfChanged(dc, Drawing.FIELD_SLOT_LEFT,  oldLeft,  mipMode);
        repaintFieldIfChanged(dc, Drawing.FIELD_SLOT_RIGHT, oldRight, mipMode);
    }

    function sameText(a, b) {
        if (a == null || b == null) { return a == b; }
        return a.equals(b);
    }

    // Repaint one field's rectangle if its text changed: sky first, then the
    // clock digits and the field text, all clipped to the rectangle. This
    // erases the old text and restores whatever sky was behind it.
    function repaintFieldIfChanged(dc, slot, oldText, mipMode) {
        var newText = DataFields.text(slot);
        if (sameText(oldText, newText)) { return; }

        var r = Drawing.fieldRect(dc, _layoutCache, slot, oldText, newText);

        Drawing.beginRegion(dc, r[0], r[1], r[2], r[3]);
        Drawing.drawSky(
            dc, _skyCache,
            config.showSun(), config.showMoon(), config.showStars(),
            mipMode
        );
        Drawing.drawFaceInRegion(
            dc, _layoutCache, _sceneTime,
            _cachedSunsetAccent, _sunColor,
            slot, newText, mipMode
        );
        Drawing.endRegion(dc);
    }

    // ── Caches ───────────────────────────────────────────────────────────────

    function updateLayoutCache(dc) {
        var w = dc.getWidth().toFloat();
        var h = dc.getHeight().toFloat();
        if (w != _cachedLayoutW || h != _cachedLayoutH) {
            _layoutCache   = Drawing.layout(w, h);
            _cachedLayoutW = w;
            _cachedLayoutH = h;
            _skyStale      = true;
        }
    }

    // Sun and moon for the current minute.
    function updateAstronomy(g, t, mipMode) {
        updateLocation();

        var clockHour = t.hour + t.min / 60.0;
        var offsetSec = t.timeZoneOffset;

        _cachedMoonPhaseAngle = Lunar.lunarPhaseAngle(
            g.year, g.month, g.day, clockHour, offsetSec
        );
        _cachedMoonPhaseBin = Lunar.lunarPhaseBinFromAngle(_cachedMoonPhaseAngle);
        _cachedMoonDiameterDeg = config.moonDiameterDeg();   // same size at every phase

        _cachedSunAltAz = Solar.solarAltAzApprox(
            g.year, g.month, g.day, clockHour, offsetSec,
            _latDeg, _lonDeg
        );
        _cachedSunsetAccent = AmoledArt.sunsetAccentScale(_cachedSunAltAz[0]);
        // Colour of the minute digits, before the saturation setting.
        _sunColor = mipMode
            ? MiPArt.minuteColorForAlt(_cachedSunAltAz[0])
            : AmoledArt.sunColorForAlt(_cachedSunAltAz[0]);

        _cachedMoonAltAz = [0.0, 0.0];
        if (config.showMoon()) {
            _cachedMoonAltAz = Lunar.lunarAltAzApprox(
                g.year, g.month, g.day, clockHour, offsetSec,
                _latDeg, _lonDeg
            );
        }
    }

    // Ask Stellar to build the star sky for `minutes` from now, with the sun
    // where it will be then (the same calculation updateAstronomy will make
    // at that minute, so the two match exactly and the sky built ahead is
    // used).
    function prepareNextSky(now, t, minutes) {
        var n      = Gregorian.info(now.add(new Time.Duration(60 * minutes)), Time.FORMAT_SHORT);
        var sunAlt = Solar.solarAltAzApprox(
            n.year, n.month, n.day, n.hour + n.min / 60.0, t.timeZoneOffset,
            _latDeg, _lonDeg
        )[0];
        Stellar.prepareNextMinute(
            [_layoutCache[0], _layoutCache[1], _layoutCache[2]],
            [n.year, n.month, n.day, n.hour, n.min],
            _latDeg,
            _lonDeg,
            t.timeZoneOffset,
            sunAlt,
            config.starCount(),
            config.starMode(),
            config.mipMode()
        );
    }

    // Screen positions of sun, moon and stars, from the astronomy cache.
    function updateSkyCache(g, t) {
        var cx = _layoutCache[0];
        var cy = _layoutCache[1];
        var R  = _layoutCache[2];

        var sp = Drawing.projectBody(_cachedSunAltAz, cx, cy, R);
        var mp = [0.0, 0.0];
        var moonDiameter = Drawing.moonDiameterPx(_cachedMoonDiameterDeg, R);
        var moonRadius   = 0.0;

        if (config.showMoon()) {
            mp         = Drawing.projectBody(_cachedMoonAltAz, cx, cy, R);
            moonRadius = Drawing.moonRadiusPx(_cachedMoonDiameterDeg, R);
        }

        _skyCache = [
            cx, cy, R,
            _cachedSunAltAz[0],
            sp[0], sp[1],
            mp[0], mp[1],
            moonDiameter, moonRadius,
            _cachedMoonPhaseAngle, _cachedMoonPhaseBin
        ];

        if (config.showStars()) {
            Stellar.updateProjectedStars(
                [cx, cy, R],
                [g.year, g.month, g.day, t.hour, t.min],
                _latDeg,
                _lonDeg,
                t.timeZoneOffset,
                _cachedSunAltAz[0],
                config.starCount(),
                config.starMode(),
                config.mipMode()
            );
        }
    }

}
