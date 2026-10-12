import QtQuick

Item {
    id: chart
    property var dataset: ({points: [], from: 0, to: 0, gap: 180})
    property string metric: "percent"
    property color foreground: "#d6d8de"
    property color accent: "#8ba4b8"
    property color muted: "#80858d"
    property color background: "#14181c"
    property string fontFamily: "monospace"
    property real scaleFactor: 1
    property int hoveredIndex: -1
    readonly property var points: dataset.points || []
    readonly property real yMin: metric === "power" ? Math.min(0, extrema(false) - 2) :
                                 metric === "health" ? Math.max(0, extrema(false) - 2) : 0
    readonly property real yMax: metric === "percent" ? 100 :
                                 metric === "health" ? Math.max(yMin + 5, extrema(true) + 2) :
                                 Math.max(5, extrema(true) + 2)
    readonly property real leftPad: 42 * scaleFactor
    readonly property real rightPad: 8 * scaleFactor
    readonly property real topPad: 30 * scaleFactor
    readonly property real bottomPad: 25 * scaleFactor
    readonly property real plotWidth: Math.max(1, width - leftPad - rightPad)
    readonly property real plotHeight: Math.max(1, height - topPad - bottomPad)
    readonly property real start: dataset.from || (points.length ? points[0].ts : 0)
    readonly property real end: Math.max(start + 1, dataset.to || (points.length ? points[points.length-1].ts : 1))

    function extrema(maximum) {
        var values = []
        for (var i = 0; i < points.length; ++i) {
            var value = points[i][metric]
            if (value !== null && value !== undefined && isFinite(value)) values.push(value)
        }
        if (!values.length) return metric === "health" ? 100 : 0
        return maximum ? Math.max.apply(null, values) : Math.min.apply(null, values)
    }
    function xPos(ts) { return leftPad + (ts-start)/(end-start)*plotWidth }
    function yPos(value) { return topPad + (yMax-value)/(yMax-yMin)*plotHeight }
    function unit() { return metric === "power" ? " W" : "%" }
    function display(value) { return value === null || value === undefined ? "—" : value.toFixed(1) + unit() }
    function timestamp(ts, full) {
        var date = new Date(ts * 1000)
        return Qt.formatDateTime(date, full ? "dd/MM HH:mm" : end-start > 86400 ? "dd/MM" : "HH:mm")
    }
    onDatasetChanged: { hoveredIndex = -1; paint.requestPaint() }
    onMetricChanged: { hoveredIndex = -1; paint.requestPaint() }
    onAccentChanged: paint.requestPaint()
    onForegroundChanged: paint.requestPaint()
    onMutedChanged: paint.requestPaint()
    onWidthChanged: paint.requestPaint()
    onHeightChanged: paint.requestPaint()
    onHoveredIndexChanged: paint.requestPaint()
    onScaleFactorChanged: paint.requestPaint()

    Canvas {
        id: paint
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.font = (10 * chart.scaleFactor) + 'px "' + chart.fontFamily.replace(/"/g, "") + '"' 
            ctx.textBaseline = "middle"
            ctx.lineWidth = 1
            for (var i = 0; i < 5; ++i) {
                var value = chart.yMin + (chart.yMax-chart.yMin)*i/4
                var y = chart.yPos(value)
                ctx.strokeStyle = Qt.rgba(chart.muted.r, chart.muted.g, chart.muted.b, 0.17)
                ctx.beginPath(); ctx.moveTo(chart.leftPad, y); ctx.lineTo(width-chart.rightPad, y); ctx.stroke()
                ctx.fillStyle = chart.muted
                ctx.textAlign = "right"
                ctx.fillText(Math.round(value).toString(), chart.leftPad-8*chart.scaleFactor, y)
            }
            if (chart.metric === "power" && chart.yMin < 0) {
                ctx.strokeStyle = Qt.rgba(chart.muted.r, chart.muted.g, chart.muted.b, 0.55)
                ctx.beginPath(); ctx.moveTo(chart.leftPad, chart.yPos(0))
                ctx.lineTo(width-chart.rightPad, chart.yPos(0)); ctx.stroke()
            }
            ctx.strokeStyle = chart.accent
            ctx.lineWidth = 2.2*chart.scaleFactor
            var last = null
            ctx.beginPath()
            for (var j = 0; j < chart.points.length; ++j) {
                var p = chart.points[j], v = p[chart.metric]
                if (v === null || v === undefined) { last = null; continue }
                var x = chart.xPos(p.ts), yy = chart.yPos(v)
                if (!last || p.ts-last.ts > (chart.dataset.gap || 180)) ctx.moveTo(x, yy)
                else ctx.lineTo(x, yy)
                last = p
            }
            ctx.stroke()
            // A dot makes a real first sample visible without inventing a line.
            ctx.fillStyle = chart.accent
            for (var k = 0; k < chart.points.length; ++k) {
                var dot = chart.points[k]
                if (dot[chart.metric] === null || dot[chart.metric] === undefined) continue
                if (chart.points.length === 1 || k === chart.hoveredIndex) {
                    ctx.beginPath()
                    ctx.arc(chart.xPos(dot.ts), chart.yPos(dot[chart.metric]), 3.5*chart.scaleFactor, 0, Math.PI*2)
                    ctx.fill()
                }
            }
            ctx.fillStyle = chart.muted
            ctx.textAlign = "left"
            ctx.fillText(chart.timestamp(chart.start, false), chart.leftPad, height-8*chart.scaleFactor)
            ctx.textAlign = "center"
            ctx.fillText(chart.timestamp((chart.start+chart.end)/2, false), chart.leftPad+chart.plotWidth/2, height-8*chart.scaleFactor)
            ctx.textAlign = "right"
            ctx.fillText(chart.timestamp(chart.end, false), width-chart.rightPad, height-8*chart.scaleFactor)
            if (chart.hoveredIndex >= 0 && chart.hoveredIndex < chart.points.length) {
                var point = chart.points[chart.hoveredIndex]
                var xx = chart.xPos(point.ts)
                ctx.strokeStyle = Qt.rgba(chart.foreground.r, chart.foreground.g, chart.foreground.b, 0.25)
                ctx.lineWidth = 1
                ctx.beginPath(); ctx.moveTo(xx, chart.topPad); ctx.lineTo(xx, chart.topPad+chart.plotHeight); ctx.stroke()
            }
        }
    }
    Text {
        x: chart.leftPad
        y: 4*chart.scaleFactor
        width: chart.plotWidth
        text: chart.hoveredIndex >= 0 && chart.hoveredIndex < chart.points.length ?
              chart.timestamp(chart.points[chart.hoveredIndex].ts, true) + "  ·  " +
              chart.display(chart.points[chart.hoveredIndex][chart.metric]) :
              chart.metric === "power" ? "Descarga (+) · Carga (−)" :
              chart.metric === "health" ? "Capacidade atual / de fábrica" : "Carga da bateria"
        font.family: chart.fontFamily
        font.pixelSize: 11*chart.scaleFactor
        color: chart.foreground
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }
    Text {
        anchors.centerIn: parent
        text: chart.points.length ? "" : "O histórico começa com o uso do plugin."
        font.family: chart.fontFamily
        font.pixelSize: 12*chart.scaleFactor
        color: chart.muted
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onExited: chart.hoveredIndex = -1
        onPositionChanged: function(mouse) {
            var index = -1, distance = Infinity
            for (var i = 0; i < chart.points.length; ++i) {
                var d = Math.abs(chart.xPos(chart.points[i].ts)-mouse.x)
                if (d < distance) { distance = d; index = i }
            }
            chart.hoveredIndex = index
        }
    }
}
