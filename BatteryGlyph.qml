import QtQuick
import "Display.js" as Display

Item {
    id: glyph
    property var percent: null
    property bool charging: false
    property color foreground: "#d6d8de"
    property color background: "#14181c"
    property color urgent: "#d17f79"
    property bool alert: true
    readonly property int level: Display.level(percent)
    readonly property color fillColor: alert && level >= 0 && level <= 2 ? urgent : foreground
    readonly property real batteryLeft: charging ? height * 0.75 : 0
    readonly property real batteryWidth: Math.max(0, width - batteryLeft)
    implicitWidth: 22 + batteryLeft
    implicitHeight: 14
    Rectangle {
        id: body
        x: glyph.batteryLeft
        y: glyph.height * 0.13
        width: glyph.batteryWidth * 0.88
        height: glyph.height * 0.74
        radius: Math.max(1, glyph.height * 0.1)
        color: "transparent"
        border.width: Math.max(1, glyph.height * 0.08)
        border.color: glyph.foreground
        Rectangle {
            x: body.border.width + 1
            y: body.border.width + 1
            width: Math.max(0, (body.width - 2 * (body.border.width + 1)) * Math.max(0, glyph.level) / 10)
            height: Math.max(0, body.height - 2 * (body.border.width + 1))
            radius: Math.max(0, body.radius - 1)
            color: glyph.fillColor
            Behavior on width { NumberAnimation { duration: 140 } }
        }
    }
    Rectangle {
        x: glyph.batteryLeft + glyph.batteryWidth * 0.91
        y: glyph.height * 0.36
        width: glyph.batteryWidth * 0.09
        height: glyph.height * 0.28
        radius: 1
        color: glyph.foreground
    }
    Text {
        anchors.centerIn: body
        visible: glyph.level < 0
        text: "?"
        color: glyph.foreground
        font.pixelSize: Math.max(8, glyph.height * 0.55)
    }
    Canvas {
        id: bolt
        x: 0
        y: glyph.height * 0.1
        width: glyph.height * 0.5
        height: glyph.height * 0.8
        visible: glyph.charging
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = glyph.foreground
            ctx.strokeStyle = glyph.foreground
            ctx.lineWidth = Math.max(1, height * 0.08)
            ctx.lineJoin = "round"
            ctx.beginPath()
            ctx.moveTo(width * 0.64, 0)
            ctx.lineTo(width * 0.06, height * 0.56)
            ctx.lineTo(width * 0.44, height * 0.56)
            ctx.lineTo(width * 0.29, height)
            ctx.lineTo(width * 0.96, height * 0.39)
            ctx.lineTo(width * 0.57, height * 0.39)
            ctx.closePath()
            ctx.fill()
        }
    }
    onChargingChanged: bolt.requestPaint()
    onForegroundChanged: bolt.requestPaint()
    onBackgroundChanged: bolt.requestPaint()
    onWidthChanged: bolt.requestPaint()
    onHeightChanged: bolt.requestPaint()
}
