import QtQuick
import qs.Ui as Ui
import "." as Local

Ui.BarWidget {
    id: root
    moduleName: "local.battery-studio"
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing : false
    readonly property var battery: Local.BatteryModel.sample.aggregate
    readonly property string stateLabel: battery ? (
        battery.status === "Charging" ? "Carregando" :
        battery.status === "Discharging" ? "Na bateria" : "Carga em espera"
    ) : "Sem bateria"
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
        text: {
            var b = root.battery
            var icon = !b ? "󰂑" : b.status === "Charging" ? "󰂄" :
                b.percent !== null && b.percent < 20 ? "󰁺" : "󰁹"
            if (root.vertical) return icon
            var label = icon
            if (root.setting("showPercentage", true))
                label += b && b.percent !== null ? " " + Math.round(b.percent) + "%" : " —"
            if (root.setting("showWatts", true) && b && b.power_w !== null)
                label += " · " + b.power_w.toFixed(1) + " W"
            return label
        }
        tooltipText: "Battery Studio · " + root.stateLabel +
                     (Local.BatteryModel.stale ? "\nAguardando atualização" : "") +
                     "\nClique para abrir o painel TLP"
        onPressed: function(code) {
            if (code === Qt.LeftButton) root.toggle()
            else if (code === Qt.RightButton) Local.BatteryModel.refresh()
        }
    }
}
