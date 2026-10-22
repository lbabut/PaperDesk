import QtQuick 2.15

// Layout/input mock only. Native PTY rendering is verified on the tablet.
Item {
    property font font
    property int dragMode: 0
    property bool allowGestures: true
    property Item contentItem
    onContentItemChanged: if (contentItem) contentItem.parent = this
    property Component cellDelegate
    property Component cellContentsDelegate
    property Component cursorDelegate
    property Component selectionDelegate
    property size cellSize: Qt.size(16, 32)
    property size terminalSize: Qt.size(80, 40)
    property string sentText: ""
    signal displayBufferChanged()
    signal terminalQuit()
    function redraw() {}
    function setBackgroundWhite(value) {}
    function putString(value) { sentText += value }
    function vkbKeyPress(key, modifiers) {}
    function mousePress(x, y) {}
    function mouseMove(x, y) {}
    function mouseRelease(x, y) {}
}
