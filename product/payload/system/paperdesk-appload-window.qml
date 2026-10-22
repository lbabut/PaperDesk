import QtQuick 2.15
import QtQuick.Window 2.2
import QtQuick.Controls 2.5
import Qt.labs.settings 1.1
import net.asivery.AppLoad 1.0
import net.asivery.Framebuffer 1.0

FocusScope {
    id: root
    Drag.active: topbarDragHandle.drag.active && !fullscreen
    width: root.globalWidth / 3
    height: _height + topbar.height
    z: 100

    property int globalWidth: 0
    property int globalHeight: 0
    property int minWidth: 400
    property int minHeight: 700
    property int scaledContentWidth: 0
    property int scaledContentHeight: 0
    property bool disablesWindowedMode: false
    implicitWidth: 0
    implicitHeight: 0


    property alias appName: _appName.text
    property bool supportsScaling: false
    property var qtfbKey: -1
    property int appPid: -1
    property bool minimized: false
    property bool fullscreen: false
    property bool forceTopBarVisible: false
    property bool closing: false
    property bool framebufferWasActive: false
    property bool systemKeyboardActive: false
    property bool systemKeyboardClearing: false
    property bool rdpShortcutsOpen: false
    readonly property bool paperdeskRdp: appName === "PaperDesk RDP Engine"
    property bool rdpLandscape: false
    readonly property bool rdpKeyboardVisible: systemKeyboardActive || Qt.inputMethod.visible
    // The raster, toolbar and shortcuts must keep the SAME coordinate space,
    // including while the native input panel appears or dismisses on PRESS.
    readonly property bool rdpChromeLandscape: rdpLandscape
    property var rdpNativeKeyboardPanel: null
    readonly property bool rdpOwnsLandscapeKeyboard: paperdeskRdp && rdpLandscape &&
        systemKeyboardActive && enabled && visible && !closing
    onRdpOwnsLandscapeKeyboardChanged: updateRdpKeyboardLayout()

    function findRdpNativeKeyboardPanel(item, depth) {
        if(!item || depth > 32) return null;
        // Use the firmware's explicit view identity, not a generated Qt class
        // name. Never rotate AppLoad's custom keyboard or another TextInput.
        if(item.objectName === "virtualkeyboard/window/main" && item.contentItem &&
                item.contentItem.virtualKeyboard !== undefined &&
                item.contentItem.portrait !== undefined &&
                item.contentItem.keyPopup !== undefined)
            return item.contentItem;
        const children = item.children || [];
        for(let i = 0; i < children.length; ++i) {
            const found = findRdpNativeKeyboardPanel(children[i], depth + 1);
            if(found) return found;
        }
        return null;
    }
    function updateRdpKeyboardLayout() {
        if(!rdpOwnsLandscapeKeyboard) {
            nativeKeyboardLayoutProbe.stop();
            return;
        }
        if(!rdpNativeKeyboardPanel && root.Window.window)
            rdpNativeKeyboardPanel = findRdpNativeKeyboardPanel(root.Window.window.contentItem, 0);
        if(!rdpNativeKeyboardPanel && !nativeKeyboardLayoutProbe.running) {
            // Firmware creates the panel lazily. Bound discovery to one second;
            // no polling or scene-tree traversal continues while typing.
            nativeKeyboardLayoutProbe.attempts = 0;
            nativeKeyboardLayoutProbe.start();
        }
    }
    Timer {
        id: nativeKeyboardLayoutProbe
        objectName: "paperdeskRdpNativeKeyboardProbe"
        property int attempts: 0
        interval: 50; repeat: true
        onTriggered: {
            if(root.Window.window)
                root.rdpNativeKeyboardPanel = root.findRdpNativeKeyboardPanel(root.Window.window.contentItem, 0);
            if(root.rdpNativeKeyboardPanel || ++attempts >= 20) {
                stop();
                console.log("PaperDesk RDP landscape native keyboard", root.rdpNativeKeyboardPanel ? "ready" : "unavailable");
            }
        }
    }
    StateGroup {
        id: nativeKeyboardLayoutState
        // PropertyChanges restores the ORIGINAL bindings and geometry on hide,
        // loss of foreground ownership or destruction. Do not reparent the
        // firmware panel: its lifetime belongs to Xochitl, not this RDP window.
        states: State {
            name: "rdpLandscapeKeyboard"
            when: root.rdpOwnsLandscapeKeyboard && root.rdpNativeKeyboardPanel !== null
            PropertyChanges {
                target: root.rdpNativeKeyboardPanel
                x: root.width
                y: 0
                width: root.height
                height: root.width
                rotation: 90
                transformOrigin: Item.TopLeft
                portrait: false
            }
            StateChangeScript {
                script: nativeKeyboardLayoutSettled.restart()
            }
        }
    }
    Timer {
        id: nativeKeyboardLayoutSettled
        interval: 0
        onTriggered: {
            // Control geometry settles after the state transition completes.
            if(root.rdpOwnsLandscapeKeyboard && root.rdpNativeKeyboardPanel)
                console.log("PaperDesk RDP native keyboard layout",
                            root.rdpNativeKeyboardPanel.rotation,
                            Math.round(root.rdpNativeKeyboardPanel.width),
                            Math.round(root.rdpNativeKeyboardPanel.height));
        }
    }
    Settings {
        id: rdpTestSettings
        category: "PaperDeskE2E"
        property bool traceTouches: false
    }
    Timer {
        interval: 700; repeat: true
        running: root.paperdeskRdp && rdpTestSettings.traceTouches && !root.closing
        onTriggered: {
            console.log("PaperDesk RDP chrome", root.rdpLandscape, root.rdpChromeLandscape,
                        root.systemKeyboardActive, Qt.inputMethod.visible, root.forceTopBarVisible);
            if(root.rdpNativeKeyboardPanel) {
                const panel = root.rdpNativeKeyboardPanel;
                console.log("PaperDesk RDP keyboard layout", panel.rotation,
                            Math.round(panel.width), Math.round(panel.height), panel.portrait);
            }
            const targets = [rdpOverlayCloseButton, rdpOverlayKeyboardButton,
                             rdpOverlayShortcutsButton, rdpShortcutsBackButton];
            if(rdpShortcutsRepeater.count > 7) targets.push(rdpShortcutsRepeater.itemAt(7));
            for(var i=0;i<targets.length;++i) {
                const item=targets[i];
                if(!item.visible) continue;
                const p=item.mapToItem(root,item.width/2,item.height/2);
                console.log("PaperDesk RDP chrome target",item.objectName,Math.round(p.x),Math.round(p.y));
            }
        }
    }
    // This is defined like that so as it doesn't interfere with minimization
    property var _height: root.globalHeight / 3
    property var beforeFullscreenData: null

    // Keyboard handling:
    property var virtualKeyboardLayout: null
    property var virtualKeyboardRef: null
    property var keyboardConfig: ({
        enableStickyness: true,
        keyUp: code => windowCanvas.virtualKeyboardKeyUp(code),
        keyDown: code => windowCanvas.virtualKeyboardKeyDown(code),
    })

    // External I/O from this component:
    signal closed
    function deactivateVirtualKeyboard() {
        if(root.virtualKeyboardRef && root.virtualKeyboardRef.active &&
                root.virtualKeyboardRef.config === root.keyboardConfig) {
            root.virtualKeyboardRef.active = false;
        }
    }
    function toggleVirtualKeyboard() {
        if(!root.virtualKeyboardRef || root.virtualKeyboardLayout === null) return;
        if(root.virtualKeyboardRef.active &&
                root.virtualKeyboardRef.config === root.keyboardConfig) {
            root.virtualKeyboardRef.active = false;
        } else {
            root.virtualKeyboardRef.config = root.keyboardConfig;
            root.virtualKeyboardRef.layout = root.virtualKeyboardLayout;
            root.virtualKeyboardRef.active = false;
            root.virtualKeyboardRef.active = true;
        }
    }
    function hideSystemKeyboard() {
        systemKeyboardActive = false;
        paperdeskSystemKeyboardInput.focus = false;
        Qt.inputMethod.hide();
        if(paperdeskRdp) console.log("PaperDesk RDP native keyboard hidden");
    }
    function systemKeyboardVisibilityChanged(visible) {
        if(paperdeskRdp) console.log("PaperDesk RDP native keyboard visible", visible);
        if(visible) {
            nativeKeyboardHiddenGuard.stop();
            updateRdpKeyboardLayout();
        }
        else nativeKeyboardHiddenGuard.restart();
    }
    Timer {
        id: nativeKeyboardHiddenGuard
        interval: 180
        onTriggered: {
            if(!Qt.inputMethod.visible) root.systemKeyboardActive = false;
        }
    }
    function toggleKeyboardInput() {
        if(!paperdeskRdp) {
            toggleVirtualKeyboard();
            return;
        }
        if(rdpKeyboardVisible) {
            hideSystemKeyboard();
            return;
        }
        deactivateVirtualKeyboard();
        paperdeskSystemKeyboardInput.forceActiveFocus();
        Qt.inputMethod.show();
        systemKeyboardActive = true;
        console.log("PaperDesk RDP native keyboard shown");
    }
    function sendRdpShortcut(index) {
        // Reserved QTFB key range handled by PaperDesk RDP.  Keeping shortcut
        // composition in the engine guarantees correct press/release order.
        windowCanvas.virtualKeyboardKeyDown(0x02ff0000 | index);
        windowCanvas.virtualKeyboardKeyUp(0x02ff0000 | index);
        rdpShortcutsOpen = false;
        console.log("PaperDesk RDP shortcut", index);
    }
    function completeClose() {
        if(root.closing) return;
        root.closing = true;
        deactivateVirtualKeyboard();
        hideSystemKeyboard();
        rdpShortcutsOpen = false;
        // Remove the window from both rendering and hit testing immediately.
        // Resource unloading may finish one event-loop turn later, and leaving
        // this FocusScope alive for that turn produced the orphaned "X" overlay.
        root.enabled = false;
        root.visible = false;
        root.z = -1;
        console.log("PaperDesk AppLoad window hidden before close", root.appName,
                    root.appPid, root.qtfbKey);
        root.closed();
    }

    Component.onDestruction: {
        // Restore borrowed panel geometry even on unexpected destruction, but
        // never re-enter Qt's global input context while Xochitl is tearing down.
        nativeKeyboardLayoutState.state = "";
        console.log("PaperDesk AppLoad window destroyed", root.appName,
                    root.appPid, root.qtfbKey);
    }
    function requestClose(terminate) {
        deactivateVirtualKeyboard();
        if(terminate) coord.terminate();
        else coord.close();
        stopUnderlying();
        // External QTFB applications do not unload an AppLoad QML frontend.
        if(appPid != -1) completeClose();
    }
    function loadApplication(appId) {
        coord.loadApplication(appId);
    }
    function notifyGainedFocus() {
        const applicationItem = supportsScaling ? loader.item : loaderScaled.item;
        if(applicationItem && applicationItem.gainedFocus)
            applicationItem.gainedFocus();
    }
    function maximize() {
        if(fullscreen) {
            // Is it already maximized?
            // Restore the previous config, and bring the window back.
            root.fullscreen = false;
            root.x = beforeFullscreenData.x
            root.y = beforeFullscreenData.y
            root.width = Math.max(minWidth, beforeFullscreenData.width)
            root._height = Math.max(minHeight, beforeFullscreenData.height)
            root.minimized = beforeFullscreenData.minimized;
            root.beforeFullscreenData = null;
        } else {
            // Bring the window to fullscreen.
            root.beforeFullscreenData = {
                x: root.x,
                y: root.y,
                width: root.width,
                height: root._height,
                minimized: root.minimized
            };
            root.x = 0;
            root.y = 0;
            root.width = Qt.binding(function() { return root.globalWidth; });
            root._height = Qt.binding(function() { return root.globalHeight; });
            root.minimized = false;
            root.fullscreen = true;
        }
    }

    AppLoadLibrary {
        id: library
        onPidDied: (pid) => {
            if(pid == appPid) {
                coord.close();
                completeClose();
            }
        }
    }

    function stopUnderlying() {
        if(appPid != -1) {
            library.terminateExternal(appPid);
        }
    }

    states: [
        State {
            name: "minimized"
            when: minimized
            PropertyChanges {
                target: root
                implicitHeight: topbar.height
                height: topbar.height
            }

            PropertyChanges {
                target: mainWindowView
                visible: false
            }
        },
        State {
            name: "maximized"
            when: fullscreen

            // Do not make the window's contents "jump" when topbar reveals itself.
            PropertyChanges {
                target: mainWindowView
                height: root.globalHeight
                anchors.top: parent.top
            }
        }
    ]

    // Swiping from the top will activate the topbar in fullscreen, and do nothing in any other case
    Timer {
        id: topBarHideTimer
        interval: 3000
        repeat: false
        onTriggered: () => forceTopBarVisible = false
    }
    function swipeFromTheTop() {
        if(fullscreen && !forceTopBarVisible) {
            forceTopBarVisible = true;
            topBarHideTimer.start();
        }
    }

    MouseArea {
        id: resizeHandle
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 100
        height: 100
        cursorShape: Qt.SizeFDiagCursor
        enabled: !fullscreen && !minimized
        z: 10001

        property real startX: 0
        property real startY: 0

        onPressed: {
            startX = mouse.x
            startY = mouse.y
        }

        onReleased: {
            let deltaX = mouse.x - startX
            let deltaY = mouse.y - startY

            let width = Math.max(minWidth, root.width + deltaX)
            let height = Math.max(minHeight, root.height + deltaY)
            startX = mouse.x
            startY = mouse.y

            if(!supportsScaling) {
                let scale = Math.min(height / root.globalHeight, width / root.globalWidth);

                width = root.globalWidth * scale
                height = root.globalHeight * scale + topbar.height
            }

            root.width = width;
            root._height = height;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 2
        border.color: "black"
        z: 101
        visible: !topbarDragHandle.drag.active
    }

    Rectangle {
        id: topbar
        visible: !fullscreen || forceTopBarVisible
        width: parent.width
        height: visible ? 75 : 0
        color: "white"
        z: 2001

        border.width: 2
        border.color: "black"

        Text {
            id: _appName
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pointSize: 20
            text: "<AppLoad Window>"
        }

        MouseArea {
            id: topbarDragHandle
            anchors.fill: parent
            drag.target: root
            enabled: !fullscreen

            onClicked: () => {
                root.forceActiveFocus();
            }
        }

        Rectangle {
            id: closeButton
            width: parent.height
            height: parent.height
            anchors.right: parent.right
            border.width: 2
            border.color: "black"
            color: parent.color

            Text {
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "X"
                font.pointSize: 20
            }

            MouseArea {
                anchors.fill: parent
                onClicked: () => {
                    requestClose(false);
                }

                onPressAndHold: () => {
                    requestClose(true);
                }
            }
        }
        Rectangle {
            id: maximizeButton
            width: parent.height
            height: parent.height
            anchors.right: closeButton.left
            border.width: 2
            border.color: "black"
            color: parent.color
            visible: !root.disablesWindowedMode

            Text {
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: fullscreen ? "▭" : "□"
                font.pointSize: 20
            }

            MouseArea {
                anchors.fill: parent
                onClicked: () => {
                    maximize()
                }
            }
        }
        Rectangle {
            id: minimizeButton
            width: parent.height
            height: parent.height
            anchors.right: maximizeButton.left
            border.width: 2
            border.color: "black"
            color: parent.color
            visible: !root.disablesWindowedMode

            Text {
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "_"
                font.pointSize: 20
            }

            MouseArea {
                anchors.fill: parent
                onClicked: () => {
                    if(fullscreen) maximize(); // Cannot have a full screen minimized app.
                    minimized = !minimized;
                }
            }
        }

        Rectangle {
            id: virtualKeyboardButton
            width: parent.height
            height: parent.height
            anchors.left: parent.left
            border.width: 2
            border.color: "black"
            color: parent.color
            visible: virtualKeyboardLayout !== null

            Image {
                source: "qrc:/appload/icons/keyboard"
                sourceSize.width: 120
                sourceSize.height: 120
                anchors.fill: parent
                anchors.margins: 10
            }

            MouseArea {
                anchors.fill: parent
                onClicked: () => {
                    toggleKeyboardInput();
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 2
            anchors.bottom: parent.bottom
            border.width: 2
            border.color: "black"
        }
    }
    Rectangle {
        id: mainWindowView
        anchors.top: topbar.bottom
        height: parent.height - topbar.height
        width: parent.width
        clip: true
        visible: !topbarDragHandle.drag.active

        MouseArea {
            id: qmldiffEventBlocker
            anchors.fill: parent
        }

        FBController {
            id: windowCanvas
            objectName: "paperdeskWindowCanvas"
            property var deviceAspectRatio: root.globalWidth / root.globalHeight
            property var contentAspectRatio: root.scaledContentWidth / root.scaledContentHeight
            states: [
                State {
                    name: "a"
                    when: windowCanvas.deviceAspectRatio == windowCanvas.contentAspectRatio
                    PropertyChanges {
                        target: windowCanvas
                        width: parent.width
                        height: parent.height
                    }
                },
                State {
                    name: "b"
                    when: windowCanvas.deviceAspectRatio > windowCanvas.contentAspectRatio

                    PropertyChanges {
                        target: windowCanvas
                        height: parent.height
                        width: windowCanvas.contentAspectRatio * parent.height
                    }
                },
                State {
                    name: "c"
                    when: windowCanvas.contentAspectRatio > windowCanvas.deviceAspectRatio

                    PropertyChanges {
                        target: windowCanvas
                        width: parent.width
                        height: parent.width / windowCanvas.contentAspectRatio
                    }
                }
            ]
            anchors.centerIn: parent

            visible: qtfbKey != -1
            allowScaling: true
            framebufferID: qtfbKey
            focus: qtfbKey != -1

            onActiveChanged: () => {
                if(windowCanvas.active) {
                    framebufferWasActive = true;
                } else if(qtfbKey != -1 && framebufferWasActive) {
                    // A real external framebuffer was active and has closed.
                    completeClose();
                }
            }

            onDragDown: () => {
                swipeFromTheTop();
            }
        }

        AppLoadCoordinator {
            id: coord

            onUnloading: () => {
                let unloadingFunction;
                if(supportsScaling) {
                    unloadingFunction = loader.item?.unloading;
                } else {
                    unloadingFunction = loaderScaled.item?.unloading;
                }
                if(unloadingFunction) unloadingFunction();
                completeClose();
            }
        }

        Loader {
            id: loaderScaled
            source: coord.applicationQMLRoot
            visible: !supportsScaling
            active: coord.loaded && !supportsScaling
            anchors.centerIn: parent

            width: root.scaledContentWidth
            height: root.scaledContentHeight

            transform: Scale {
                origin.x: loaderScaled.width / 2
                origin.y: loaderScaled.height / 2
                xScale: Math.min(root.width / loaderScaled.width, root.height / loaderScaled.height)
                yScale: Math.min(root.width / loaderScaled.width, root.height / loaderScaled.height)
            }

            Connections {
                target: loaderScaled.item
                function onClose() {
                    coord.close();
                }
            }
        }
        Loader {
            id: loader
            source: coord.applicationQMLRoot
            visible: supportsScaling
            active: coord.loaded && supportsScaling
            anchors.fill: parent

            Connections {
                target: loader.item
                function onClose() {
                    coord.close();
                }
            }
        }
    }

    Rectangle {
        id: qmldiffReplaceMeButton
        objectName: "paperdeskKeyboardButton"
        anchors.top: parent.top
        anchors.topMargin: 18
        anchors.horizontalCenter: parent.horizontalCenter
        width: 210
        height: 68
        radius: 8
        color: "white"
        border.color: "black"
        border.width: 2
        z: 100000
        visible: fullscreen && !forceTopBarVisible && virtualKeyboardLayout !== null && !root.paperdeskRdp

        Text {
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.virtualKeyboardRef && root.virtualKeyboardRef.active &&
                  root.virtualKeyboardRef.config === root.keyboardConfig ?
                  "HIDE KEYBOARD" : "KEYBOARD"
            font.pointSize: 16
            font.bold: true
            font.letterSpacing: 1
            color: "black"
        }

        MouseArea {
            objectName: "paperdeskKeyboardClickTarget"
            anchors.fill: parent
            preventStealing: true
            onPressed: (mouse) => mouse.accepted = true
            onClicked: {
                console.log("PaperDesk keyboard button clicked");
                toggleKeyboardInput();
            }
        }
    }

    TextInput {
        id: paperdeskSystemKeyboardInput
        objectName: "paperdeskRdpSystemKeyboardInput"
        x: 0
        y: 113
        width: 2
        height: 2
        opacity: 0.01
        visible: root.paperdeskRdp && root.fullscreen
        enabled: visible
        clip: true
        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData

        onTextChanged: {
            if(root.systemKeyboardClearing || text.length === 0)
                return;
            for(var i = 0; i < text.length; ++i) {
                var encoded = 0x02000000 | text.charCodeAt(i);
                windowCanvas.virtualKeyboardKeyDown(encoded);
                windowCanvas.virtualKeyboardKeyUp(encoded);
            }
            root.systemKeyboardClearing = true;
            text = "";
            root.systemKeyboardClearing = false;
        }

        Keys.onPressed: (event) => {
            var special = event.key === Qt.Key_Return ||
                          event.key === Qt.Key_Enter ||
                          event.key === Qt.Key_Backspace ||
                          event.key === Qt.Key_Delete ||
                          event.key === Qt.Key_Tab ||
                          event.key === Qt.Key_Escape ||
                          event.key === Qt.Key_Left ||
                          event.key === Qt.Key_Right ||
                          event.key === Qt.Key_Up ||
                          event.key === Qt.Key_Down;
            if(special) {
                windowCanvas.virtualKeyboardKeyDown(event.key);
                windowCanvas.virtualKeyboardKeyUp(event.key);
                event.accepted = true;
            }
        }
    }

    Connections {
        target: Qt.inputMethod
        function onVisibleChanged() {
            // Keep ownership through the native panel's outside-touch PRESS,
            // until RELEASE has reached the stationary toolbar button.
            root.systemKeyboardVisibilityChanged(Qt.inputMethod.visible);
        }
    }

    Item {
        id: rdpChrome
        objectName: "paperdeskRdpChrome"
        x: root.rdpChromeLandscape ? root.width : 0
        y: 0
        width: root.rdpChromeLandscape ? root.height : root.width
        height: root.rdpChromeLandscape ? root.width : root.height
        rotation: root.rdpChromeLandscape ? 90 : 0
        transformOrigin: Item.TopLeft
        z: 100000

    Rectangle {
        id: rdpToolbarOverlay
        objectName: "paperdeskRdpToolbar"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 112
        color: "black"
        z: 100001
        visible: root.paperdeskRdp && root.fullscreen && !root.forceTopBarVisible

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                text: "PAPERDESK  /  REMOTE ACCESS"
                color: "white"
                font.pointSize: 10
                font.bold: true
                font.letterSpacing: 2
            }
            Text {
                text: "Remote desktop"
                color: "white"
                font.pointSize: 25
                font.bold: true
            }
        }

        Rectangle {
            id: rdpOverlayCloseButton
            objectName: "paperdeskRdpCloseButton"
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 176
            height: 68
            radius: 8
            color: rdpCloseTap.pressed ? "black" : "white"
            border.color: "white"
            border.width: 2
            Text {
                objectName: "paperdeskRdpCloseLabel"
                anchors.centerIn: parent
                text: "Close"
                color: rdpCloseTap.pressed ? "white" : "black"
                font.pointSize: 16
                font.bold: true
            }
            TapHandler {
                id: rdpCloseTap
                objectName: "paperdeskRdpCloseTapHandler"
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: root.requestClose(true)
            }
        }

        Rectangle {
            id: rdpOverlayKeyboardButton
            objectName: "paperdeskRdpKeyboardButton"
            anchors.right: rdpOverlayCloseButton.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 202
            height: 68
            radius: 8
            color: rdpKeyboardTap.pressed ? "black" : "white"
            border.color: "white"
            border.width: 2
            Text {
                objectName: "paperdeskRdpKeyboardLabel"
                anchors.centerIn: parent
                text: root.rdpKeyboardVisible ? "Hide keyboard" : "Keyboard"
                color: rdpKeyboardTap.pressed ? "white" : "black"
                font.pointSize: 16
                font.bold: true
            }
            TapHandler {
                id: rdpKeyboardTap
                objectName: "paperdeskRdpKeyboardTapHandler"
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: root.toggleKeyboardInput()
            }
        }

        Rectangle {
            id: rdpOverlayShortcutsButton
            objectName: "paperdeskRdpShortcutsButton"
            anchors.right: rdpOverlayKeyboardButton.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 216
            height: 68
            radius: 8
            color: rdpShortcutsTap.pressed ? "black" : "white"
            border.color: "white"
            border.width: 2
            Text {
                objectName: "paperdeskRdpShortcutsLabel"
                anchors.centerIn: parent
                text: "Shortcuts"
                color: rdpShortcutsTap.pressed ? "white" : "black"
                font.pointSize: 16
                font.bold: true
            }
            TapHandler {
                id: rdpShortcutsTap
                objectName: "paperdeskRdpShortcutsTapHandler"
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: {
                    root.hideSystemKeyboard();
                    root.rdpShortcutsOpen = !root.rdpShortcutsOpen;
                    console.log("PaperDesk RDP shortcuts", root.rdpShortcutsOpen ? "opened" : "closed");
                }
            }
        }
    }

    Rectangle {
        id: rdpShortcutsPanel
        objectName: "paperdeskRdpShortcutsPanel"
        anchors.top: rdpToolbarOverlay.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        color: "white"
        z: 100000
        visible: rdpToolbarOverlay.visible && root.rdpShortcutsOpen
        TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: {} }

        Text {
            id: rdpShortcutsTitle
            anchors.top: parent.top
            anchors.topMargin: 48
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Keyboard shortcuts"
            color: "black"
            font.pointSize: 29
            font.bold: true
        }

        Grid {
            anchors.top: rdpShortcutsTitle.bottom
            anchors.topMargin: 42
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 3
            spacing: 22

            Repeater {
                id: rdpShortcutsRepeater
                model: ["Ctrl+C", "Ctrl+V", "Ctrl+X", "Ctrl+A", "Alt+Tab",
                        "Ctrl+Alt+Del", "Windows", "Escape", "Tab"]
                delegate: Rectangle {
                    objectName: "paperdeskRdpShortcut_" + index
                    width: 406
                    height: 145
                    radius: 8
                    color: shortcutTap.pressed ? "black" : "white"
                    border.color: "black"
                    border.width: 2
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: shortcutTap.pressed ? "white" : "black"
                        font.pointSize: 16
                        font.bold: true
                    }
                    TapHandler {
                        id: shortcutTap
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: root.sendRdpShortcut(index)
                    }
                }
            }
        }

        Rectangle {
            id: rdpShortcutsBackButton
            objectName: "paperdeskRdpShortcutsBackButton"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 90
            width: 310
            height: 68
            radius: 8
            color: shortcutsBackTap.pressed ? "white" : "black"
            border.color: "black"
            border.width: 2
            Text {
                anchors.centerIn: parent
                text: "Back"
                color: shortcutsBackTap.pressed ? "black" : "white"
                font.pointSize: 16
                font.bold: true
            }
            TapHandler {
                id: shortcutsBackTap
                objectName: "paperdeskRdpShortcutsBackTapHandler"
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: root.rdpShortcutsOpen = false
            }
        }
    }
    }
}
