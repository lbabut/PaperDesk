import QtQml 2.15

QtObject {
    property string applicationQMLRoot: ""
    property bool loaded: false
    signal unloading

    function loadApplication(id) { loaded = true }
    function close() {
        loaded = false
        unloading()
    }
    function terminate() { close() }
}
