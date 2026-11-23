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

    // The system stops the face when the user opens its menus or an app and
    // starts it again on return: keep the star sky for then.
    function onStop(state as Dictionary?) as Void {
        Stellar.save();
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
