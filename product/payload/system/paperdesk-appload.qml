import QtQuick 2.5
import QtQuick.Window 2.2
import QtQuick.Controls 2.5
import Qt.labs.settings 1.1
import net.asivery.AppLoad 1.0
import net.asivery.Framebuffer 1.0

Rectangle {
    id: _appLoadView
    anchors.fill: parent
    color: "#f0f0f0"

    property var windowArchetype: Qt.createComponent("window.qml")
    property var absoluteRoot: _appLoadView
    property var virtualKeyboardRef: null
    property var paperdeskWindowStack: []

    signal requestClose

    // Dormant hardware-test hook. The E2E runner enables it for one Xochitl
    // start through QSettings; the flag is cleared before anything launches.
    Settings {
        id: paperDeskE2E
        category: "PaperDeskE2E"
        property bool autostart: false
        property string applicationId: "paperdesk"
    }
    Timer {
        interval: 1200
        running: paperDeskE2E.autostart
        repeat: false
        onTriggered: {
            const applicationId = paperDeskE2E.applicationId;
            paperDeskE2E.autostart = false;
            console.log("PaperDesk E2E autostart", applicationId);
            launchApplicationById(applicationId, [], {}, false, false);
        }
    }

    AppLoadLibrary {
        id: library
    }

    ListModel {
        id: launcherApplications
    }

    function isVisibleLauncherApplication(application) {
        if(!application || typeof application.id !== "string")
            return false;
        // PaperDesk is a legacy aggregate hub. The RDP engine and browser
        // downloader are internal workers launched by visible frontends.
        return application.id !== "paperdesk" &&
               application.id !== "external::paperrdp" &&
               application.id !== "external::paperrdp-profile" &&
               application.id !== "external::paperbooks-download" &&
               application.id !== "external::paperweb-download";
    }

    function rebuildLauncherApplications() {
        launcherApplications.clear();
        for(let application of library.applications) {
            if(!isVisibleLauncherApplication(application))
                continue;
            launcherApplications.append({
                applicationId: application.id,
                displayName: application.name,
                iconSource: String(application.icon || "")
            });
        }
    }

    Connections {
        target: library
        function onApplicationsChanged() {
            rebuildLauncherApplications();
        }
    }

    Component.onCompleted: rebuildLauncherApplications()
    function getMinResolutionFor(device) {
        switch(device) {
            case "original": return [400, 533];
            case "move": return [400, 688];
        }
    }
    function getResolutionOf(device) {
        switch(device) {
            case "original": return [1620, 2160];
            case "move": return [954, 1696];
        }
    }

    function snapshotApplication(modelData) {
        if(!modelData || typeof modelData.id !== "string" ||
                modelData.id.length === 0 || typeof modelData.name !== "string" ||
                modelData.name.length === 0) {
            return null;
        }
        // AppLoad's application objects belong to a resource list and become
        // invalid when an internal frontend unloads. Never retain such an
        // object while constructing a new window; copy its values first.
        return {
            id: modelData.id,
            name: modelData.name,
            externalType: modelData.externalType,
            supportsScaling: modelData.supportsScaling,
            virtualKeyboardLayout: modelData.virtualKeyboardLayout,
            disablesWindowedMode: modelData.disablesWindowedMode,
            aspectRatio: modelData.aspectRatio,
            canHaveMultipleFrontends: modelData.canHaveMultipleFrontends
        };
    }

    function registerPaperDeskWindow(win) {
        let next = [];
        for(let existing of paperdeskWindowStack) {
            if(existing && !existing.closing)
                next.push(existing);
        }
        if(next.length > 0) {
            const previous = next[next.length - 1];
            if(previous.deactivateVirtualKeyboard)
                previous.deactivateVirtualKeyboard();
            if(previous.hideSystemKeyboard)
                previous.hideSystemKeyboard();
            // A fullscreen AppLoad window remains rendered below the next one.
            // Disable it as well, otherwise passive pointer handlers in both
            // applications can react to one physical touch.
            previous.enabled = false;
        }
        next.push(win);
        paperdeskWindowStack = next;
    }

    function unregisterPaperDeskWindow(win) {
        let next = [];
        for(let existing of paperdeskWindowStack) {
            if(existing && existing !== win && !existing.closing)
                next.push(existing);
        }
        paperdeskWindowStack = next;
        if(next.length === 0)
            return;
        const previous = next[next.length - 1];
        previous.enabled = true;
        if(previous.notifyGainedFocus)
            previous.notifyGainedFocus();
        previous.forceActiveFocus();
    }

    function launchWindow(modelData, extraArgs, extraEnv) {
        const application = snapshotApplication(modelData);
        if(application === null) {
            console.log("PaperDesk refused stale AppLoad application entry");
            return null;
        }
        let qtfbKey = -1;
        let win;

        if(application.externalType === 2 /* EXTERNAL_QTFB */) {
            qtfbKey = Math.floor(Math.random() * 10000000);
        }
        if(application.externalType === 1 /* EXTERNAL_NOGUI */) {
            // Background helpers must not create an AppLoad window. Apart
            // from avoiding a useless shell, this prevents the stale "X"
            // overlay that older AppLoad releases leave after a short-lived
            // process exits.
            library.launchExternal(application.id, -1, extraArgs || [], extraEnv || {});
            return { externalNoGui: true };
        }
        if(application.externalType != 1 /* EXTERNAL_NOGUI */) {
            /* Create a new window*/
            if(library.isFrontendRunningFor(application.id) && !application.canHaveMultipleFrontends) {
                console.log("Cannot load multiple frontends for app. It doesn't support it.");
                return;
            }
            if(windowArchetype.status !== Component.Ready) {
                console.log("Window object not ready: " + windowArchetype.status);
                console.log(windowArchetype.errorString());
                return;
            }
            win = windowArchetype.createObject(absoluteRoot, { x: 100, y: 100 });
            if(win == null) {
                console.log("Failed to instantiate a window object!");
                return;
            }

            win.appName = application.name;
            // Rotate only the RDP chrome. The native engine rotates its own
            // raster and input coordinates, keeping old QTFB backends usable.
            const launchArgs = extraArgs || [];
            const orientationArg = launchArgs.indexOf("--orientation");
            win.rdpLandscape = application.id === "external::paperrdp" &&
                orientationArg >= 0 && launchArgs[orientationArg + 1] === "landscape";
            win.supportsScaling = application.supportsScaling;
            win.virtualKeyboardLayout = application.virtualKeyboardLayout;
            win.disablesWindowedMode = application.disablesWindowedMode;

            win.virtualKeyboardRef = _appLoadView.virtualKeyboardRef;

            win.globalWidth = Qt.binding(function() { return _appLoadView.width; })
            win.globalHeight = Qt.binding(function() { return _appLoadView.height; })
            const deviceAspectRatio = Math.min(_appLoadView.width, _appLoadView.height) /
                                      Math.max(_appLoadView.width, _appLoadView.height);
            let realAspectRatio = Number(application.aspectRatio);
            if(!isFinite(realAspectRatio) || realAspectRatio <= 0)
                realAspectRatio = deviceAspectRatio;
            const deviceWidth = Math.min(_appLoadView.height, _appLoadView.width);
            console.log(`Application starting with ${realAspectRatio} aspect ratio`);
            [win.minWidth, win.minHeight] = [win.implicitWidth, win.implicitHeight] =
                [400, Math.floor(400 / realAspectRatio)];
            [win.scaledContentWidth, win.scaledContentHeight] =
                [deviceWidth, Math.floor(deviceWidth / realAspectRatio)];

            win.qtfbKey = qtfbKey;

            win.closed.connect(() => {
                const closingWindow = win;
                const keyboardConfig = closingWindow.keyboardConfig;
                unregisterPaperDeskWindow(closingWindow);
                if(_appLoadView.virtualKeyboardRef &&
                        _appLoadView.virtualKeyboardRef.active &&
                        _appLoadView.virtualKeyboardRef.config === keyboardConfig) {
                    _appLoadView.virtualKeyboardRef.active = false;
                }
                // completeClose() already hides and disables the window. Defer
                // destruction so it cannot invalidate the signal stack while
                // AppLoad is still unloading the frontend.
                closingWindow.enabled = false;
                closingWindow.visible = false;
                closingWindow.z = -1;
                Qt.callLater(function() {
                    console.log("PaperDesk destroying closed AppLoad window",
                                closingWindow.appName);
                    closingWindow.destroy();
                    library.reloadList();
                });
            });
            registerPaperDeskWindow(win);

        }
        if(application.externalType == 0 /* INTERNAL */) {
            win.loadApplication(application.id);
        } else if(application.externalType == 2 /* EXTERNAL_QTFB */) {
            win.appPid = library.launchExternal(application.id, qtfbKey, extraArgs || [], extraEnv || {});
        }

        return win;
    }

    function launchApplicationById(id, args, env, windowed, retried) {
        for(let application of library.applications) {
            if(application && application.id === id) {
                const window = launchWindow(application, args, env);
                if(window) {
                    if(!window.externalNoGui &&
                            (application.disablesWindowedMode || !windowed))
                        window.maximize();
                    return window;
                }
                break;
            }
        }
        if(!retried) {
            console.log("PaperDesk refreshing stale AppLoad list before launching", id);
            library.reloadList();
            Qt.callLater(function() {
                launchApplicationById(id, args, env, windowed, true);
            });
        } else {
            console.log("No valid application installed with id: " + id);
        }
        return null;
    }


    Connections {
        target: AppLoadLauncher
        function onRequestLaunch(id, args, env, windowed) {
            console.log("Launching: " + id);
            launchApplicationById(id, args, env, windowed, false);
        }
    }

    Rectangle {
        anchors.fill: parent
        MouseArea {
            // Eat the events.
            anchors.fill: parent
        }

        Rectangle {
            id: header
            anchors.top: parent.top
            width: parent.width
            height: 100

            Rectangle {
                anchors.topMargin: 25
                anchors.leftMargin: 25
                anchors.top: parent.top
                anchors.left: parent.left
                height: 60
                width: 250

                MouseArea {
                    anchors.fill: parent
                    onClicked: () => {
                        _appLoadView.requestClose();
                    }
                }

                Image {
                    id: arrowBack
                    source: "qrc:/appload/icons/exit"
                    sourceSize.width: 60
                    sourceSize.height: 60
                    anchors.left: parent.left
                }
                Text {
                    anchors.left: arrowBack.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    font.pointSize: 24
                    text: qsTr("Back")
                }
            }

            Rectangle {
                id: refreshButton
                anchors.topMargin: 25
                anchors.rightMargin: 25
                anchors.top: parent.top
                anchors.right: parent.right
                height: 60
                width: 250
                property string reloadIconSource: "qrc:/appload/icons/reload"

                MouseArea {
                    anchors.fill: parent
                    onClicked: () => {
                        library.reloadList();
                        Qt.callLater(rebuildLauncherApplications);
                        refreshButton.reloadIconSource = "qrc:/appload/icons/check";
                        reloadIconSwitchBackTimer.start();
                    }
                }

                Timer {
                    id: reloadIconSwitchBackTimer
                    interval: 1000
                    onTriggered: () => refreshButton.reloadIconSource = "qrc:/appload/icons/reload"
                }

                Image {
                    id: reloadIcon
                    source: refreshButton.reloadIconSource
                    sourceSize.width: 60
                    sourceSize.height: 60
                    anchors.right: parent.right
                }
                Text {
                    anchors.right: reloadIcon.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    font.pointSize: 24
                    text: qsTr("Reload")
                }
            }

            Text {
                anchors.fill: parent
                text: "AppLoad"
                font.pointSize: 40
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
        GridView {
            anchors.top: header.bottom
            anchors.topMargin: 20
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.floor((parent.width - 20) / cellWidth) * cellWidth
            height: parent.height - 100
            id: gridView
            model: launcherApplications
            cellWidth: 200 + 20
            cellHeight: 200 + 20
            interactive: false

            delegate: Rectangle {
                id: appDelegate
                property string stableApplicationId: applicationId
                anchors.margins: 10
                width: gridView.cellWidth - 20
                height: gridView.cellHeight - 20

                Image {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.margins: 10
                    id: appIcon
                    source: iconSource
                    width: 150
                    height: 150
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: appIcon.bottom
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    anchors.topMargin: 5
                    text: displayName
                    font.pointSize: 24
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: () => {
                        launchApplicationById(appDelegate.stableApplicationId,
                                              [], {}, false, false);
                    }
                    onPressAndHold: () => {
                        launchApplicationById(appDelegate.stableApplicationId,
                                              [], {}, true, false);
                    }
                }
            }
        }
    }
}
