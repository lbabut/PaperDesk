import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.settings 1.1
import net.asivery.AppLoad 1.0
import net.asivery.ApploadUtils

Rectangle {
    id: root
    anchors.fill: parent
    color: "white"
    signal close

    Settings {
        id: e2eSettings
        category: "PaperDeskE2E"
        property bool traceTouches: false
    }
    PointHandler {
        enabled: e2eSettings.traceTouches
        onActiveChanged: if (active)
            console.log("PaperDesk observed tablet tap", point.position.x, point.position.y)
    }

    function unloading() {}
    function openApplication(applicationId) {
        console.log("PaperDesk touch launching", applicationId)
        AppLoadLauncher.launchApplication(applicationId, [], {}, false)
    }

    component ProductCard: Rectangle {
        property string title: ""
        property string subtitle: ""
        property string mark: ""
        property string number: ""
        property string applicationId: ""

        color: cardTouch.pressed ? "black" : "white"
        border.color: "black"
        border.width: 2
        radius: 10

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: 28
            anchors.topMargin: 28
            width: 104
            height: 76
            radius: 6
            color: cardTouch.pressed ? "white" : "black"
            Text {
                anchors.centerIn: parent
                text: mark
                color: cardTouch.pressed ? "black" : "white"
                font.pointSize: 23
                font.bold: true
            }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 30
            anchors.top: parent.top
            anchors.topMargin: 32
            text: number
            color: cardTouch.pressed ? "white" : "black"
            font.pointSize: 14
            font.bold: true
            font.letterSpacing: 2
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 28
            anchors.rightMargin: 28
            anchors.topMargin: 124
            height: 2
            color: cardTouch.pressed ? "white" : "black"
        }
        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 158
            anchors.margins: 28
            text: title
            color: cardTouch.pressed ? "white" : "black"
            font.pointSize: 31
            font.bold: true
            wrapMode: Text.WordWrap
        }
        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 238
            anchors.margins: 28
            text: subtitle
            color: cardTouch.pressed ? "white" : "black"
            font.pointSize: 17
            lineHeight: 1.32
            wrapMode: Text.WordWrap
        }
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 28
            width: 128
            height: 54
            radius: 27
            color: "transparent"
            border.color: cardTouch.pressed ? "white" : "black"
            border.width: 2
            Text {
                anchors.centerIn: parent
                text: "OPEN  →"
                color: cardTouch.pressed ? "white" : "black"
                font.pointSize: 14
                font.bold: true
                font.letterSpacing: 1
            }
        }
        TapHandler {
            id: cardTouch
            onTapped: root.openApplication(applicationId)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 30
        spacing: 22

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 158
            color: "black"
            radius: 10
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 30
                anchors.rightMargin: 28
                spacing: 20
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        text: "PAPERDESK  /  E-INK WORKSPACE"
                        color: "white"
                        font.pointSize: 12
                        font.bold: true
                        font.letterSpacing: 2
                    }
                    Text {
                        text: "PaperDesk"
                        color: "white"
                        font.pointSize: 40
                        font.bold: true
                    }
                    Text {
                        text: "Five focused tools. One quiet workspace."
                        color: "white"
                        font.pointSize: 16
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 132
                    Layout.preferredHeight: 62
                    color: "transparent"
                    border.color: "white"
                    border.width: 2
                    radius: 31
                    Text {
                        anchors.centerIn: parent
                        text: "V 2.0.5"
                        color: "white"
                        font.pointSize: 13
                        font.bold: true
                        font.letterSpacing: 1
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 54
            spacing: 18
            Text {
                text: "CHOOSE A WORKSPACE"
                color: "black"
                font.pointSize: 14
                font.bold: true
                font.letterSpacing: 2
            }
            Rectangle {
                Layout.fillWidth: true
                height: 2
                color: "black"
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            rowSpacing: 20
            columnSpacing: 20

            ProductCard {
                objectName: "terminalButton"
                Layout.fillWidth: true
                Layout.fillHeight: true
                number: "01"
                mark: ">_"
                title: "PaperDesk SSH"
                subtitle: "Connect over SSH, use shortcuts and work with readable, zoomable text."
                applicationId: "literm"
            }
            ProductCard {
                objectName: "webButton"
                Layout.fillWidth: true
                Layout.fillHeight: true
                number: "02"
                mark: "WWW"
                title: "Web reader"
                subtitle: "Read lightweight pages without animation, clutter or distracting colour."
                applicationId: "paperweb"
            }
            ProductCard {
                objectName: "rdpButton"
                Layout.fillWidth: true
                Layout.fillHeight: true
                number: "03"
                mark: "RDP"
                title: "Remote desktop"
                subtitle: "Open a saved computer with touch, keyboard and the shortcuts you need."
                applicationId: "paperrdp-login"
            }
            ProductCard {
                objectName: "rssButton"
                Layout.fillWidth: true
                Layout.fillHeight: true
                number: "04"
                mark: "RSS"
                title: "Reading list"
                subtitle: "Keep feeds, favourites and full articles together, ready for offline reading."
                applicationId: "paperrss"
            }
            ProductCard {
                objectName: "booksButton"
                Layout.fillWidth: true
                Layout.fillHeight: true
                number: "05"
                mark: "BK"
                title: "Books"
                subtitle: "Find public-domain books and take your offline shelf anywhere."
                applicationId: "paperbooks"
            }
        }
    }

    DisplayMethodArea {
        anchors.fill: parent
        displayMethod: DisplayMethodArea.Fast
        z: -1
    }
}
