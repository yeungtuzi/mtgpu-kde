import QtQuick 2.15

Item {
    id: root

    property int frameIndex: 0

    function frameSource(i) {
        return "images/frame-0" + i + ".png"
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Image {
        source: root.frameSource(root.frameIndex)
        width: Math.round(root.width * 0.125)
        height: width
        anchors.centerIn: parent
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }

    Timer {
        interval: 700
        running: true
        repeat: true
        onTriggered: root.frameIndex = (root.frameIndex + 1) % 4
    }
}
