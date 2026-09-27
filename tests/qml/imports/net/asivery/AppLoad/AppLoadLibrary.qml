import QtQml 2.15

QtObject {
    property var applications: []
    signal pidDied(int pid)

    function terminateExternal(pid) {}
    function launchExternal(id, qtfbKey, args, env) { return 1234 }
    function isFrontendRunningFor(id) { return false }
    function reloadList() {}
}
