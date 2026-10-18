import QtQuick
import qs.Commons as Commons
import qs.Ui as Ui
import "." as Local

Ui.Panel {
    id: root
    moduleName: "io.github.sabb4th.powerkit"
    manageIpc: false
    property var anchorItem: null
    property var hostWidget: null
    property bool countedOpen: false
    onOpenedChanged: {
        if (countedOpen !== opened) {
            Local.BatteryModel.panelVisible(opened)
            countedOpen = opened
        }
    }
    Component.onDestruction: {
        if (countedOpen) Local.BatteryModel.panelVisible(false)
    }
    function switchPanel(direction) {
        if (bar && typeof bar.switchPanelFrom === "function")
            return bar.switchPanelFrom(hostWidget || root, direction)
        return false
    }
    Ui.KeyboardPanel {
        id: surface
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keys
        contentWidth: fittedContentWidth(Commons.Style.space(440))
        contentHeight: fittedContentHeight(Math.min(Commons.Style.space(640), Math.max(Commons.Style.space(260), dashboard.desiredHeight)))
        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.close()
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ControlModifier)) {
                    root.switchPanel(event.modifiers & Qt.ShiftModifier ? -1 : 1)
                    event.accepted = true
                }
            }
            Local.Dashboard {
                id: dashboard
                anchors.fill: parent
                backend: Local.BatteryModel
                foreground: Commons.Color.popups.text
                background: Commons.Color.popups.background
                accent: Commons.Color.accent
                muted: Commons.Color.muted
                urgent: Commons.Color.urgent
                fontFamily: root.bar ? root.bar.fontFamily : Commons.Style.font.family
                scaleFactor: Commons.Style.font.body / 12
                cornerRadius: Commons.Style.cornerRadius
            }
        }
    }
}
