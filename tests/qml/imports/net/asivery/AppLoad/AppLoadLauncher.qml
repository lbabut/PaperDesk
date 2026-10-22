pragma Singleton
import QtQml 2.15

QtObject {
    property string lastApplicationId: ""
    property var lastArgs: []
    property int launchCount: 0
    signal requestLaunch(string id, var args, var env, bool windowed)

    function reset() {
        lastApplicationId = ""
        lastArgs = []
        launchCount = 0
    }

    function launchApplication(applicationId, args, env, windowed) {
        lastApplicationId = applicationId
        lastArgs = args
        launchCount += 1
    }
}
