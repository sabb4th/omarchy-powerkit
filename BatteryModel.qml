pragma Singleton
import QtQuick
import Quickshell.Io

Item {
    id: model
    property var sample: ({ batteries: [], aggregate: null, tlp: {}, care: {}, cpu: {} })
    property var history: ({ points: [], events: [], samples: 0 })
    property string selectedId: ""
    property int historyHours: 24
    property bool busy: false
    property string message: ""
    property bool messageOk: true
    property int openPanels: 0
    property int clients: 0
    property double now: Date.now() / 1000
    property int historyBucket: -1
    property bool workerParsed: false
    readonly property string script: decodeURIComponent(String(Qt.resolvedUrl("scripts/backend.py")).replace(/^file:\/\//, ""))
    readonly property var battery: {
        if (selectedId === "__all__") return sample.aggregate
        var list = sample.batteries || []
        for (var i = 0; i < list.length; ++i)
            if (list[i].id === selectedId) return list[i]
        return sample.aggregate
    }
    readonly property bool stale: sample.ts ? now - sample.ts > 45 : true

    function send(request) {
        if (collector.running) collector.write(JSON.stringify(request) + "\n")
    }
    function registerClient() {
        clients += 1
        if (!collector.running) collector.running = true
    }
    function unregisterClient() {
        clients = Math.max(0, clients - 1)
        if (clients === 0) {
            reconnect.stop()
            collector.running = false
            openPanels = 0
        }
    }
    function panelVisible(value) {
        openPanels = Math.max(0, openPanels + (value ? 1 : -1))
        send({op: "visible", value: openPanels > 0})
        if (value) requestHistory()
    }
    function requestHistory() {
        if (battery) send({op: "history", battery: battery.id, hours: historyHours})
    }
    function refresh() { send({op: "refresh"}); requestHistory() }
    function selectBattery(id) {
        selectedId = id
        history = ({points: [], events: [], samples: 0})
        requestHistory()
    }
    function selectHistory(hours) {
        historyHours = hours
        history = ({points: [], events: [], samples: 0})
        requestHistory()
    }
    function setRetention(days) { send({op: "retention", days: days}) }
    function action(op, args) { startWorker("action", {op: op, args: args || []}) }
    function exportHistory() {
        if (battery) startWorker("export", {battery: battery.id, hours: historyHours})
    }
    function report() { startWorker("report", {}) }
    function startWorker(command, parameters) {
        if (busy) return
        busy = true
        message = ""
        workerParsed = false
        worker.command = ["python3", script, command, JSON.stringify(parameters)]
        worker.running = true
    }
    function receive(line) {
        try {
            var data = JSON.parse(line)
            if (data.type === "sample") {
                sample = data
                var valid = selectedId === "__all__" && data.batteries.length > 1
                for (var i = 0; i < data.batteries.length; ++i)
                    valid = valid || selectedId === data.batteries[i].id
                if (!valid) selectedId = data.aggregate ? data.aggregate.id : ""
                var bucket = Math.floor(data.ts / 60)
                if (bucket !== historyBucket || history.points.length === 0) {
                    historyBucket = bucket
                    if (openPanels > 0) requestHistory()
                }
            } else if (data.type === "history") {
                if (battery && data.battery === battery.id && data.hours === historyHours)
                    history = data
            } else {
                message = data.message || "Resposta recebida."
                messageOk = data.type !== "error" && data.ok !== false
            }
        } catch (error) {
            message = "Não foi possível ler os dados do coletor."
            messageOk = false
        }
    }
    Process {
        id: collector
        command: ["python3", model.script, "monitor"]
        stdinEnabled: true
        stdout: SplitParser { onRead: function(data) { model.receive(data) } }
        stderr: SplitParser {
            onRead: function(data) { console.warn("Battery Studio collector: " + data) }
        }
        onStarted: model.send({op: "visible", value: model.openPanels > 0})
        onExited: function(exitCode, exitStatus) {
            if (model.clients === 0) return
            model.message = "Coletor interrompido. Tentando reconectar…"
            model.messageOk = false
            reconnect.start()
        }
    }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text)
                    model.workerParsed = true
                    model.message = result.message || "Operação concluída."
                    model.messageOk = result.ok === true
                } catch (error) {
                    model.message = "A operação não retornou uma resposta válida."
                    model.messageOk = false
                }
            }
        }
        stderr: SplitParser {
            onRead: function(data) { console.warn("Battery Studio action: " + data) }
        }
        onExited: function(exitCode, exitStatus) {
            model.busy = false
            if (!model.workerParsed) {
                model.message = "Não foi possível executar a operação. Verifique Python e polkit."
                model.messageOk = false
            }
            model.refresh()
        }
    }
    Timer { id: reconnect; interval: 5000; onTriggered: if (model.clients > 0) collector.running = true }
    Timer { interval: 10000; running: model.clients > 0; repeat: true; onTriggered: model.now = Date.now() / 1000 }
}
