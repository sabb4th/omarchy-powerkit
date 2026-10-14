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
    implicitWidth: 22
    implicitHeight: 14
    Rectangle {
        id: body
        x: 0
        y: glyph.height * 0.13
        width: glyph.width * 0.88
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
            opacity: glyph.charging ? 0.6 : 1
            Behavior on width { NumberAnimation { duration: 140 } }
        }
    }
    Rectangle {
        x: glyph.width * 0.91
        y: glyph.height * 0.36
        width: glyph.width * 0.09
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
        anchors.fill: body
        visible: glyph.charging
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = glyph.foreground
            ctx.beginPath()
            ctx.moveTo(width * 0.55, height * 0.07)
            ctx.lineTo(width * 0.32, height * 0.55)
            ctx.lineTo(width * 0.49, height * 0.55)
            ctx.lineTo(width * 0.42, height * 0.94)
            ctx.lineTo(width * 0.71, height * 0.41)
            ctx.lineTo(width * 0.54, height * 0.41)
            ctx.closePath()
            ctx.fill()
        }
    }
    onForegroundChanged: bolt.requestPaint()
    onWidthChanged: bolt.requestPaint()
    onHeightChanged: bolt.requestPaint()
}
