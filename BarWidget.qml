import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
import "." as Local
import "Display.js" as Display

Ui.BarWidget {
    id: root
    moduleName: "io.github.sabb4th.powerkit"
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing : false
    readonly property var battery: Local.BatteryModel.sample.aggregate
    readonly property string mode: Local.BatteryModel.displayMode
    readonly property string label: Display.barText(mode, battery,
        (Local.BatteryModel.sample.power || {}).profile)
    readonly property string stateLabel: battery ? (
        battery.status === "Charging" ? "Charging" :
        battery.status === "Discharging" ? "On battery" : "Charging paused"
    ) : "No battery"
    readonly property var modeLabels: [
        "Icon + percentage + watts", "Icon + percentage", "Icon only",
        "Icon + watts", "Icon + runtime", "Icon + percentage + runtime",
        "Icon + percentage + profile"
    ]
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function open() { if (panelLoader.item) panelLoader.item.open() }
    function close() { if (panelLoader.item) panelLoader.item.close() }
    function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
    function closeForPopoutSwitch() {
        if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
    }
    function injectPanel() {
        if (!panelLoader.item) return
        panelLoader.item.bar = bar
        panelLoader.item.anchorItem = button
        panelLoader.item.hostWidget = root
        panelLoader.item.settings = settings
    }
    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()
    Component.onCompleted: Local.BatteryModel.registerClient()
    Component.onDestruction: Local.BatteryModel.unregisterClient()
    Loader {
        id: panelLoader
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
    }
    Ui.WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        active: root.opened
        labelVisible: false
        hasVisualContent: true
        fixedWidth: root.vertical ? root.barSize : Math.max(Commons.Style.space(30),
                    parts.implicitWidth + Commons.Style.space(14))
        text: root.label
        tooltipText: "PowerKit · " + root.stateLabel +
                     (Local.BatteryModel.stale ? "\n" + "Waiting for an update" : "") +
                     "\n" + "Display: " + root.modeLabels[Display.modes.indexOf(root.mode)] +
                     "\n" + "Right-click: next display mode"
        Row {
            id: parts
            anchors.centerIn: parent
            spacing: Commons.Style.space(6)
            Local.BatteryGlyph {
                width: Commons.Style.space(21) + (charging ? height * 0.75 : 0)
                height: button.fontSize * 1.05
                anchors.verticalCenter: parent.verticalCenter
                percent: root.battery ? root.battery.percent : null
                charging: !!root.battery && root.battery.status === "Charging"
                foreground: button.foreground
                urgent: Commons.Color.urgent
                background: Commons.Color.background
            }
            Text {
                visible: !root.vertical && root.label !== ""
                text: root.label
                anchors.verticalCenter: parent.verticalCenter
                color: button.foreground
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
                textFormat: Text.PlainText
            }
        }
        onPressed: function(code) {
            if (code === Qt.LeftButton) root.toggle()
            else if (code === Qt.RightButton) Local.BatteryModel.cycleDisplay()
            else if (code === Qt.MiddleButton) Local.BatteryModel.refresh()
        }
    }
}
