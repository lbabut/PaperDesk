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
    // Handle real touch points directly: mouse synthesis drops a second finger
    // while another key is still held. Mouse input remains available on desktop.
    MultiPointTouchArea {
        anchors.fill:parent
        minimumTouchPoints:1
        maximumTouchPoints:5
        mouseEnabled:false
        touchPoints:[TouchPoint {},TouchPoint {},TouchPoint {},TouchPoint {},TouchPoint {}]
        onPressed:function(points) { for(var i=0;i<points.length;i++)key.tapped(); }
    }
    TapHandler {
        acceptedDevices:PointerDevice.Mouse|PointerDevice.Stylus|PointerDevice.Airbrush
        onPressedChanged:if(pressed)key.tapped()
    }
}
