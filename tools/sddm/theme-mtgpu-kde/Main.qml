import QtQuick 2.15
import QtQuick.Window 2.15

Item {
    id: root

    readonly property color accent: "#3daee9"
    readonly property color fg: "#eff0f1"
    readonly property color dim: "#9aa0a6"
    property int sessionIndex: 0
    property string message: ""
    property bool messageIsError: false
    property var frames: ["frame-00.png", "frame-01.png", "frame-02.png", "frame-03.png"]
    property int frameIndex: 0

    Rectangle { anchors.fill: parent; color: "black" }

    Image {
        id: rabbit
        source: root.frames[root.frameIndex]
        width: root.width * 0.125
        height: width
        fillMode: Image.PreserveAspectFit
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        smooth: true
        mipmap: true
    }

    Timer {
        interval: 700
        running: true
        repeat: true
        onTriggered: root.frameIndex = (root.frameIndex + 1) % 4
    }

    Text {
        id: clock
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 34
        color: root.dim
        font.pixelSize: 15
        text: Qt.formatDateTime(new Date(), "HH:mm")
    }
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: clock.text = Qt.formatDateTime(new Date(), "HH:mm")
    }

    Rectangle {
        id: card
        width: 340
        height: 164
        radius: 12
        color: "#c814171c"
        border.width: 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: rabbit.bottom
        anchors.topMargin: 90

        Column {
            id: fields
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 16
            spacing: 8

            Rectangle {
                width: parent.width
                height: 34
                radius: 6
                color: "#14ffffff"
                border.width: 1
                border.color: userInput.activeFocus ? root.accent : "#2affffff"
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{1F464}"
                    color: root.dim
                    font.pixelSize: 15
                }
                TextInput {
                    id: userInput
                    anchors.left: parent.left
                    anchors.leftMargin: 38
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: userModel.lastUser
                    color: root.fg
                    font.pixelSize: 15
                    selectionColor: root.accent
                    clip: true
                    onAccepted: pwInput.forceActiveFocus()
                }
            }

            Rectangle {
                width: parent.width
                height: 34
                radius: 6
                color: "#14ffffff"
                border.width: 1
                border.color: pwInput.activeFocus ? root.accent : "#2affffff"
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{1F512}"
                    color: root.dim
                    font.pixelSize: 15
                }
                TextInput {
                    id: pwInput
                    anchors.left: parent.left
                    anchors.leftMargin: 38
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    echoMode: TextInput.Password
                    color: root.fg
                    font.pixelSize: 15
                    selectionColor: root.accent
                    clip: true
                    onAccepted: root.doLogin()
                    Component.onCompleted: if (userInput.text.length > 0) forceActiveFocus()
                }
            }

            Row {
                width: parent.width
                height: 26
                spacing: 8
                Text {
                    text: "会话"
                    color: root.dim
                    font.pixelSize: 13
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    id: sessionPill
                    width: 186
                    height: 26
                    radius: 6
                    color: "#10ffffff"
                    border.width: 1
                    border.color: sessionPopup.visible ? root.accent : "#22ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                    ListView {
                        id: sessions
                        anchors.fill: parent
                        anchors.margins: 1
                        anchors.rightMargin: 22
                        model: sessionModel
                        orientation: ListView.Horizontal
                        clip: true
                        interactive: false
                        currentIndex: root.sessionIndex
                        delegate: Item {
                            width: sessions.width
                            height: sessions.height
                            visible: ListView.isCurrentItem
                            Component.onCompleted: {
                                if (root.sessionIndex === 0 && String(model.name).indexOf("kde6-mtgpu") >= 0)
                                    root.sessionIndex = index
                            }
                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 12
                                text: model.name
                                color: root.fg
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u25BE"
                        color: root.dim
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: sessionPopup.visible = !sessionPopup.visible
                    }
                }
            }
        }


    Rectangle {
        id: sessionPopup
        visible: false
        z: 10
        width: 250
        height: Math.min(240, sessions.count * 28 + 8)
        radius: 6
        color: "#f01a1d22"
        border.width: 1
        border.color: "#33ffffff"
        x: 54
        y: 130
        ListView {
            anchors.fill: parent
            anchors.margins: 4
            model: sessionModel
            clip: true
            interactive: sessions.count > 7
            delegate: Rectangle {
                width: ListView.view.width
                height: 28
                radius: 4
                color: index === root.sessionIndex ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25) : (sessionMouse.containsMouse ? "#18ffffff" : "transparent")
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: model.name
                    color: root.fg
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                MouseArea {
                    id: sessionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.sessionIndex = index
                        sessionPopup.visible = false
                    }
                }
            }
        }
    }

        Rectangle {
            id: loginButton
            width: 42
            height: 42
            radius: 21
            color: loginArea.pressed ? "#2a9fd4" : root.accent
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 22
            Text {
                anchors.centerIn: parent
                text: "\u2192"
                color: "#ffffff"
                font.pixelSize: 22
            }
            MouseArea {
                id: loginArea
                anchors.fill: parent
                onClicked: root.doLogin()
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            text: root.message
            color: root.messageIsError ? "#ff6b6b" : root.dim
            font.pixelSize: 12
        }
    }

    function doLogin() {
        root.message = ""
        sddm.login(userInput.text, pwInput.text, root.sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.message = "密码错误，请重试"
            root.messageIsError = true
            pwInput.text = ""
            pwInput.forceActiveFocus()
        }
        function onInformationMessage(message) {
            root.message = message
            root.messageIsError = false
        }
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 26
        spacing: 20
        Repeater {
            model: [
                { glyph: "\u23FB", action: "powerOff" },
                { glyph: "\u27F3", action: "reboot" },
                { glyph: "\u263E", action: "suspend" }
            ]
            delegate: Text {
                text: modelData.glyph
                color: "#66ffffff"
                font.pixelSize: 20
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    onClicked: {
                        if (modelData.action === "powerOff") sddm.powerOff()
                        else if (modelData.action === "reboot") sddm.reboot()
                        else sddm.suspend()
                    }
                }
            }
        }
    }

}