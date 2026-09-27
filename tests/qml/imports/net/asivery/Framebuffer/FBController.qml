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
    signal dragDown

    function virtualKeyboardKeyUp(code) {}
    function virtualKeyboardKeyDown(code) {}
}
