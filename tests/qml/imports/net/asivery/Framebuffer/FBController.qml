import QtQuick 2.15

Item {
    enum Rotation {
        Deg0,
        Deg90R,
        Deg180,
        Deg90L
    }
    enum FillMode {
        PreserveAspectFit
    }

    property bool allowScaling: false
    property bool active: true
    property int fillMode: FBController.PreserveAspectFit
    property var framebufferID: -1
    property int fbRotation: FBController.Deg0
    property int keyDownCount: 0
    property int keyUpCount: 0
    property int lastKeyDown: -1
    property int lastKeyUp: -1
    signal dragDown

    function virtualKeyboardKeyUp(code) {
        lastKeyUp = code
        keyUpCount += 1
    }
    function virtualKeyboardKeyDown(code) {
        lastKeyDown = code
        keyDownCount += 1
    }
}
