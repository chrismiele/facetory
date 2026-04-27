using Toybox.Activity;
using Toybox.Application;
using Toybox.Position;
using Toybox.Time;
using Toybox.Weather;

module LocationService {

    const CACHE_LAT_KEY = "trusted_lat_deg";
    const CACHE_LON_KEY = "trusted_lon_deg";
    const CACHE_TIME_KEY = "trusted_location_time";
    const MAX_CACHE_AGE_SEC = 30 * 24 * 60 * 60;

    function getBest() {
        var fallback = [config.latDeg(), config.lonDeg()];

        if (!config.useGps()) {
            return fallback;
        }

        var pos = getPositionLocation();
        if (pos != null) {
            return useAndCache(pos);
        }

        var act = getActivityLocation();
        if (act != null) {
            return useAndCache(act);
        }

        var cached = getCachedLocation();
        if (cached != null) {
            return cached;
        }

        var weather = getWeatherLocation();
        if (weather != null) {
            return weather;
        }

        return fallback;
    }

    function getPositionLocation() {
        var info = Position.getInfo();
        if (info == null || info.position == null) {
            return null;
        }

        return degreesIfValid(info.position);
    }

    function getActivityLocation() {
        var info = Activity.getActivityInfo();
        if (info == null || info.currentLocation == null) {
            return null;
        }

        return degreesIfValid(info.currentLocation);
    }

    function getWeatherLocation() {
        var cc = Weather.getCurrentConditions();
        if (cc == null || cc.observationLocationPosition == null) {
            return null;
        }

        return degreesIfValid(cc.observationLocationPosition);
    }

    function useAndCache(loc) {
        Application.Storage.setValue(CACHE_LAT_KEY, loc[0]);
        Application.Storage.setValue(CACHE_LON_KEY, loc[1]);
        Application.Storage.setValue(CACHE_TIME_KEY, Time.now().value());
        return loc;
    }

    function getCachedLocation() {
        var lat = Application.Storage.getValue(CACHE_LAT_KEY);
        var lon = Application.Storage.getValue(CACHE_LON_KEY);
        var t = Application.Storage.getValue(CACHE_TIME_KEY);

        if (lat == null || lon == null || t == null) {
            return null;
        }

        if (Time.now().value() - t > MAX_CACHE_AGE_SEC) {
            return null;
        }

        var latF = lat.toFloat();
        var lonF = lon.toFloat();

        if (!isValidLatLon(latF, lonF)) {
            return null;
        }

        return [latF, lonF];
    }

    function degreesIfValid(position) {
        var deg = position.toDegrees();
        if (deg == null || deg.size() < 2) {
            return null;
        }

        var lat = deg[0].toFloat();
        var lon = deg[1].toFloat();

        if (!isValidLatLon(lat, lon)) {
            return null;
        }

        return [lat, lon];
    }

    function isValidLatLon(lat, lon) {
        if (lat == null || lon == null) {
            return false;
        }

        if (lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0) {
            return false;
        }

        if (lat == 0.0 && lon == 0.0) {
            return false;
        }

        return true;
    }
}
