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
    property bool animateLayout: false
    readonly property bool animationsEnabled: settings.animations !== false
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
    Component.onCompleted: { Local.BatteryModel.registerClient(); animateLayout = true }
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
        clip: true
        labelVisible: false
        hasVisualContent: true
        fixedWidth: root.vertical ? root.barSize : Math.max(Commons.Style.space(30),
                    parts.implicitWidth + Commons.Style.space(12))
        text: root.label
        tooltipText: ""
        Behavior on fixedWidth {
            enabled: root.animateLayout && root.animationsEnabled
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        HoverHandler { id: hover }
        Rectangle {
            anchors.fill: parent
            anchors.margins: Commons.Style.space(2)
            radius: Commons.Style.cornerRadius
            color: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, root.opened ? 0.1 : hover.hovered ? 0.055 : 0)
            Behavior on color { enabled: root.animationsEnabled; ColorAnimation { duration: 160 } }
        }
        Row {
            id: parts
            anchors.centerIn: parent
            spacing: Commons.Style.space(4)
            Local.BatteryGlyph {
                width: Commons.Style.space(21) + (charging ? height * 0.6 : 0)
                Behavior on width { enabled: root.animationsEnabled; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                height: button.fontSize * 1.05
                anchors.verticalCenter: parent.verticalCenter
                percent: root.battery ? root.battery.percent : null
                animated: root.animationsEnabled
                charging: !!root.battery && root.battery.status === "Charging"
                foreground: button.foreground
                urgent: Commons.Color.urgent
                background: Commons.Color.background
            }
            Text {
                id: barLabel
                property string displayed: ""
                Component.onCompleted: displayed = root.label
                visible: !root.vertical && root.label !== ""
                text: displayed
                anchors.verticalCenter: parent.verticalCenter
                color: button.foreground
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
                textFormat: Text.PlainText
            }
        }
        Connections {
            target: root
            function onLabelChanged() {
                if (!root.animateLayout || !root.animationsEnabled || root.vertical) {
                    barLabel.displayed = root.label
                    barLabel.opacity = 1
                } else labelSwap.restart()
            }
        }
        SequentialAnimation {
            id: labelSwap
            NumberAnimation { target: barLabel; property: "opacity"; to: 0.35; duration: 65; easing.type: Easing.OutQuad }
            ScriptAction { script: barLabel.displayed = root.label }
            NumberAnimation { target: barLabel; property: "opacity"; to: 1; duration: 130; easing.type: Easing.OutCubic }
        }
        onPressed: function(code) {
            if (code === Qt.LeftButton) root.toggle()
            else if (code === Qt.RightButton) Local.BatteryModel.cycleDisplay()
            else if (code === Qt.MiddleButton) Local.BatteryModel.refresh()
        }
    }
}
