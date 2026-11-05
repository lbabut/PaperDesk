import QtQuick 2.15
Rectangle {
    id: key
    property string label: ""
    property bool active: false
    property int textSize: 28
    signal tapped
    color: active ? "black" : "white"
    border.color: "black"; border.width: 2; radius: 8
    Text { anchors.fill:parent;anchors.margins:6;text:key.label==="⌫"?"DEL":key.label;color:key.active?"white":"black";font.pixelSize:key.textSize;font.bold:true;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter;elide:Text.ElideRight }
    // Passive point handlers receive every contact, including a release and a
    // new press in the same frame. Siblings track distinct points on one key.
    PointHandler {acceptedDevices:PointerDevice.TouchScreen;onActiveChanged:if(active)key.tapped()}
    PointHandler {acceptedDevices:PointerDevice.TouchScreen;onActiveChanged:if(active)key.tapped()}
    PointHandler {acceptedDevices:PointerDevice.TouchScreen;onActiveChanged:if(active)key.tapped()}
    PointHandler {acceptedDevices:PointerDevice.TouchScreen;onActiveChanged:if(active)key.tapped()}
    PointHandler {acceptedDevices:PointerDevice.TouchScreen;onActiveChanged:if(active)key.tapped()}
    TapHandler {
        acceptedDevices:PointerDevice.Mouse|PointerDevice.Stylus|PointerDevice.Airbrush
        onPressedChanged:if(pressed)key.tapped()
    }
}
