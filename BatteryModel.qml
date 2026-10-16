pragma Singleton
import QtQuick
import Quickshell.Io
import "Display.js" as Display

Item {
    id: model
    property var sample: ({batteries: [], aggregate: null, batctl: {}, power: {profiles: []}})
    property string selectedId: ""
    property bool busy: false
    property string message: ""
    property bool messageOk: true
    property int openPanels: 0
    property int clients: 0
    property bool workerParsed: false
    property double now: Date.now() / 1000
    readonly property var preferences: Object.assign({display_mode: "full"}, sample.preferences || {})
    readonly property string displayMode: Display.modes.indexOf(preferences.display_mode) >= 0 ? preferences.display_mode : "full"
    readonly property string executable: decodeURIComponent(String(Qt.resolvedUrl("bin/powerkit")).replace(/^file:\/\//, ""))
    readonly property var battery: {
        var list = sample.batteries || []
        for (var i = 0; i < list.length; ++i)
            if (list[i].id === selectedId) return list[i]
        return list.length ? list[0] : sample.aggregate
    }
    readonly property bool stale: !sample.ts || now - sample.ts > 65
    function send(request) { if (collector.running) collector.write(JSON.stringify(request) + "\n") }
    function setPreference(key, value) {
        var changes = {}; changes[key] = value
        send({op: "preferences", changes: changes})
    }
    function cycleDisplay() { setPreference("display_mode", Display.nextMode(displayMode)) }
    function registerClient() { clients++; if (!collector.running) collector.running = true }
    function unregisterClient() {
        clients = Math.max(0, clients - 1)
        if (!clients) { reconnect.stop(); collector.running = false; openPanels = 0 }
    }
    function panelVisible(value) {
        openPanels = Math.max(0, openPanels + (value ? 1 : -1))
        send({op: "visible", value: openPanels > 0})
    }
    function refresh() { send({op: "refresh"}) }
    function selectBattery(id) { selectedId = id }
    function action(op, args) {
        if (busy) return
        busy = true; message = ""; workerParsed = false
        worker.command = [executable, "action", JSON.stringify({op: op, args: args || []})]
        worker.running = true
    }
    function receive(line) {
        try {
            var data = JSON.parse(line)
            if (data.type === "sample") sample = data
            else if (data.type === "preferences") sample = Object.assign({}, sample, {preferences: data.preferences})
            else { message = data.message || ""; messageOk = data.type !== "error" }
        } catch (error) { message = "Invalid collector response."; messageOk = false }
    }
    Process {
        id: collector
        command: [model.executable, "monitor"]
        stdinEnabled: true
        stdout: SplitParser { onRead: function(data) { model.receive(data) } }
        stderr: SplitParser { onRead: function(data) { console.warn("PowerKit: " + data) } }
        onStarted: model.send({op: "visible", value: model.openPanels > 0})
        onExited: {
            if (model.clients > 0) {
                model.message = "Collector unavailable. Check the installation."
                model.messageOk = false; reconnect.start()
            }
        }
    }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    model.workerParsed = true
                    model.messageOk = result.ok === true
                    model.message = result.ok ? "Setting applied." : result.message
                } catch (error) { model.messageOk = false }
            }
        }
        onExited: {
            model.busy = false
            if (!model.workerParsed) {
                model.message = "Operation interrupted or authentication cancelled."
                model.messageOk = false
            }
            model.refresh()
        }
    }
    Timer { id: reconnect; interval: 5000; onTriggered: if (model.clients > 0) collector.running = true }
    Timer { interval: 10000; running: model.clients > 0; repeat: true; onTriggered: model.now = Date.now() / 1000 }
}
