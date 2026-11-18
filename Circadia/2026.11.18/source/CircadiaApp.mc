import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class CircadiaApp extends Application.AppBase {

    var _view;

    function initialize() {
        AppBase.initialize();
        config.refresh();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        _view = new CircadiaView();
        return [ _view ];
    }

    // Called when the user changes settings via Garmin Connect / Express.
    function onSettingsChanged() as Void {
        config.refresh();
        if (_view != null) {
            _view.onSettingsChanged();
        }
        WatchUi.requestUpdate();
    }
}
