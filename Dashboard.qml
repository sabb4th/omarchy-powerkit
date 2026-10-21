import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts
import qs.Commons as Commons
import qs.Ui as Ui
import "Display.js" as Display

Item {
    id: root
    property var backend: null
    property color foreground: Commons.Color.popups.text
    property color background: Commons.Color.popups.background
    property color accent: Commons.Color.accent
    property color muted: Commons.Color.muted
    property color urgent: Commons.Color.urgent
    property string fontFamily: Commons.Style.font.family
    property real scaleFactor: 1
    property int cornerRadius: Commons.Style.cornerRadius
    property bool limitsExpanded: false
    property int draftStart: 0
    property int draftStop: 80
    property bool dirty: false
    readonly property var sample: backend ? backend.sample : ({})
    readonly property var b: backend && backend.battery ? backend.battery : ({})
    readonly property var ctl: sample.batctl || ({})
    readonly property var cpu: sample.cpu || ({count: 0, governors: [], preferences: []})
    readonly property var power: sample.power || ({profiles: []})
    readonly property var orderedProfiles: {
        var available = power.profiles || []
        return ["power-saver", "balanced", "performance"].filter(function(profile) {
            return available.indexOf(profile) >= 0
        })
    }
    readonly property var behaviour: b.behaviour || ({current: null, available: []})
    readonly property var startSpec: ctl.start || ({supported: false, min: 0, max: 99, values: []})
    readonly property var stopSpec: ctl.stop || ({supported: false, min: 1, max: 100, values: []})
    readonly property bool busy: backend ? backend.busy : false
    readonly property bool fresh: !!backend && !backend.stale
    readonly property bool canCharge: ctl.available === true && stopSpec.supported === true && !busy && fresh
    readonly property int chargeLimit: b.limits && b.limits.stop !== null ? b.limits.stop : 100
    readonly property real chargeFraction: known(b.percent) ? Math.max(0, Math.min(1, b.percent / 100)) : 0
    readonly property string limitSummary: b.limits && known(b.limits.stop) ? (startSpec.supported && known(b.limits.start) ? b.limits.start + "% → " : "") + b.limits.stop + "%" : "Unavailable"
    readonly property real desiredHeight: Math.min(u(760), content.implicitHeight + u(32))
    implicitWidth: u(440)
    implicitHeight: desiredHeight

    function u(px) { return Math.round(px * scaleFactor) }
    function known(value) { return value !== undefined && value !== null && isFinite(value) }
    function fmt(value, suffix) { return known(value) ? Number(value).toFixed(1) + (suffix || "") : "—" }
    function act(op, args) { if (backend && !busy) { dirty = false; backend.action(op, args) } }
    function profileLabel(p) { return p === "performance" ? "Performance" : p === "power-saver" ? "Saver" : "Balanced" }
    function profileIcon(p) { return p === "performance" ? "󰓅" : p === "power-saver" ? "󰌪" : "󰊚" }
    function behaviourLabel(mode) { return mode === "auto" ? "Auto" : mode === "inhibit-charge" ? "Inhibit charge" : "Force discharge" }
    function behaviourHelp(mode) {
        if (mode === "inhibit-charge") return "Charging is paused. AC can power the laptop; switch to Auto to resume charging."
        if (mode === "force-discharge") return "Uses the battery even on AC power. Switch to Auto to stop forced discharge."
        return "Charges automatically within your battery's charge limits."
    }
    function cpuLabel(value) {
        var labels = {powersave:"Powersave", performance:"Performance", balance_power:"Balanced power", balance_performance:"Balanced performance", power:"Power saving", default:"System default", mixed:"Mixed policies", schedutil:"Schedutil", ondemand:"On demand", conservative:"Conservative", userspace:"Userspace"}
        return labels[value] || value || "Unavailable"
    }
    function cpuOptions(values, current) {
        var options = (values || []).map(function(value) { return {value:value, label:root.cpuLabel(value)} })
        if (current === "mixed") options.unshift({value:"mixed",label:"Mixed policies"})
        if (!options.length) options.push({value:"",label:"Unavailable"})
        return options
    }
    function syncDraft() {
        if (dirty) return
        draftStart = b.limits && known(b.limits.start) ? b.limits.start : startSpec.min
        draftStop = b.limits && known(b.limits.stop) ? b.limits.stop : 80
    }
    function accepts(value, spec) { return value >= spec.min && value <= spec.max && (!spec.values.length || spec.values.indexOf(value) >= 0) }
    function stateLabel() {
        if (!b.id) return "No battery detected"
        if (sample.ac && behaviour.current === "force-discharge") return "Forced discharge · AC power"
        if (sample.ac && behaviour.current === "inhibit-charge") return "Charging inhibited · AC power"
        if (b.status === "Charging") return "Charging to " + chargeLimit + "% · AC power"
        if (b.status === "Discharging") return "On battery"
        if (b.status === "Full") return "Fully charged · AC power"
        return sample.ac === true ? "AC power · charging paused" : "Charging paused"
    }
    function runtime() {
        if (b.status !== "Charging") return Display.runtimeText(b.hours)
        if (!known(b.full_wh) || !known(b.energy_wh) || !known(b.power_w) || b.power_w < 0.1) return "—"
        return Display.runtimeText(Math.max(0, b.full_wh * chargeLimit / 100 - b.energy_wh) / b.power_w)
    }
    onBChanged: syncDraft()
    onStartSpecChanged: syncDraft()
    Component.onCompleted: syncDraft()

    component Label: Text {
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.bodySmall
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    component Action: Ui.Button {
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Commons.Style.font.bodySmall
        focusable: true
        bordered: true
        enabled: !root.busy
        opacity: enabled ? 1 : 0.45
    }
    component Heading: Ui.PanelSectionHeader {
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.fillWidth: true
    }
    component Rule: Ui.PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }
    component InfoPair: RowLayout {
        property string label: ""
        property string value: "—"
        Layout.fillWidth: true
        spacing: root.u(8)
        Label { text: parent.label; opacity: 0.6; elide: Text.ElideRight; wrapMode: Text.NoWrap }
        Label { text: parent.value; Layout.fillWidth: false; horizontalAlignment: Text.AlignRight; wrapMode: Text.NoWrap }
    }

    Controls.ScrollView {
        id: scroll
        anchors.fill: parent
        anchors.margins: root.u(16)
        clip: true
        contentWidth: availableWidth
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
        ColumnLayout {
            id: content
            width: scroll.availableWidth
            spacing: root.u(12)

            // Same hierarchy as Omarchy's power panel: icon, state, large percentage.
            RowLayout {
                Layout.fillWidth: true
                spacing: root.u(14)
                BatteryGlyph {
                    Layout.preferredWidth: root.u(36) + (charging ? root.u(18) * 0.6 : 0)
                    Layout.preferredHeight: root.u(18)
                    percent: root.known(root.b.percent) ? root.b.percent : null
                    charging: root.b.status === "Charging"
                    foreground: root.foreground
                    background: root.background
                    urgent: root.urgent
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: root.u(2)
                    Label { text: "Battery"; font.pixelSize: Commons.Style.font.title; font.bold: true }
                    Label {
                        text: root.stateLabel().toUpperCase()
                        opacity: 0.65
                        font.pixelSize: Commons.Style.font.caption
                        font.letterSpacing: 1.0
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                }
                Label {
                    Layout.fillWidth: false
                    text: Display.percentText(root.b.percent)
                    font.pixelSize: Commons.Style.font.displayLarge
                    font.bold: true
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: root.u(8)
                radius: height / 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                Rectangle {
                    height: parent.height
                    width: parent.width * root.chargeFraction
                    radius: parent.radius
                    color: root.foreground
                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                }
                Rectangle {
                    visible: root.chargeLimit < 100 && root.stopSpec.supported
                    width: Math.max(1, root.u(2))
                    height: parent.height + root.u(4)
                    x: Math.min(parent.width - width, parent.width * root.chargeLimit / 100)
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.accent
                }
            }
            Ui.Dropdown {
                visible: (root.sample.batteries || []).length > 1
                Layout.fillWidth: true
                showLabel: false
                value: root.b.id || ""
                options: (root.sample.batteries || []).map(function(b) { return {value: b.id, label: b.id + " · " + b.model} })
                foreground: root.foreground
                background: root.background
                onChanged: function(value) { root.dirty = false; root.backend.selectBattery(value) }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.u(20)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: root.u(7)
                    InfoPair { label: "Health"; value: root.fmt(root.b.health, "%") }
                    InfoPair { label: root.b.status === "Charging" ? "To " + root.chargeLimit + "%" : "Time left"; value: root.runtime() }
                    InfoPair { visible: root.known(root.b.temperature_c); label: "Temperature"; value: root.fmt(root.b.temperature_c, " °C") }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: root.u(7)
                    InfoPair { label: "Cycles"; value: root.known(root.b.cycles) ? String(root.b.cycles) : "—" }
                    InfoPair { label: root.b.status === "Charging" ? "Charging" : root.b.status === "Discharging" ? "Discharging" : "Power"; value: Display.wattsText(root.b.power_w) }
                    InfoPair { visible: root.known(root.b.temperature_c); label: "Voltage"; value: root.fmt(root.b.voltage_v, " V") }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: cpuControls.implicitHeight + root.u(20)
                radius: root.cornerRadius
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
                border.width: 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                ColumnLayout {
                    id: cpuControls
                    anchors.fill: parent
                    anchors.margins: root.u(10)
                    spacing: root.u(8)
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Governor"; Layout.preferredWidth: root.u(132); Layout.fillWidth: false; color: root.foreground; opacity: 0.7; wrapMode: Text.NoWrap }
                        Ui.Dropdown {
                            Layout.fillWidth: true
                            showLabel: false
                            value: root.cpu.governor || ""
                            options: root.cpuOptions(root.cpu.governors, root.cpu.governor)
                            foreground: root.foreground
                            background: root.background
                            fontFamily: root.fontFamily
                            enabled: root.fresh && !root.busy && root.cpu.governors.length > 0
                            opacity: enabled ? 1 : 0.78
                            onChanged: function(value) { if (value && value !== "mixed" && value !== root.cpu.governor) root.act("cpu-governor", [value]) }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Energy preference"; Layout.preferredWidth: root.u(132); Layout.fillWidth: false; color: root.foreground; opacity: 0.7; wrapMode: Text.NoWrap }
                        Ui.Dropdown {
                            Layout.fillWidth: true
                            showLabel: false
                            value: root.cpu.preference || ""
                            options: root.cpuOptions(root.cpu.preferences, root.cpu.preference)
                            foreground: root.foreground
                            background: root.background
                            fontFamily: root.fontFamily
                            enabled: root.fresh && !root.busy && !root.cpu.preference_locked && root.cpu.preferences.length > 0
                            opacity: enabled ? 1 : 0.78
                            onChanged: function(value) { if (value && value !== "mixed" && value !== root.cpu.preference) root.act("cpu-preference", [value]) }
                        }
                    }
                    Label {
                        text: !root.cpu.count ? "CPU controls are not available on this system." : root.cpu.preference_locked ? "Select Powersave to adjust energy preference." : "All CPU policies · profiles may override."
                        color: root.foreground
                        opacity: 0.62
                        font.pixelSize: Commons.Style.font.bodySmall
                    }
                }
            }
            Rule {}
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.u(10)
                Heading { text: "POWER PROFILE" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.u(6)
                    Repeater {
                        model: root.orderedProfiles
                        Action {
                            required property string modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            text: root.profileLabel(modelData)
                            iconText: root.profileIcon(modelData)
                            iconSize: Commons.Style.font.title
                            active: root.power.profile === modelData
                            onClicked: root.act("profile", [modelData])
                        }
                    }
                }
                Label { visible: !!root.power.error; text: root.power.error || ""; color: root.urgent }
            }
            Rule {}
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.u(10)
                Heading { text: "CHARGE BEHAVIOUR" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.u(6)
                    Repeater {
                        model: root.behaviour.available || []
                        Action {
                            required property string modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            text: root.behaviourLabel(modelData)
                            active: root.behaviour.current === modelData
                            enabled: !root.busy && root.fresh
                            onClicked: root.act("behaviour", [root.b.id, modelData])
                        }
                    }
                }
                Label {
                    text: root.behaviour.available.length ? root.behaviourHelp(root.behaviour.current) : "Charge behaviour control is not supported by this battery."
                    color: root.behaviour.current === "force-discharge" ? root.urgent : root.muted
                }
            }
            Rule {}
            Action {
                Layout.fillWidth: true
                text: "Charge limits · " + root.limitSummary
                iconText: root.limitsExpanded ? "⌃" : "⌄"
                leftAlign: true
                enabled: true
                onClicked: root.limitsExpanded = !root.limitsExpanded
            }
            ColumnLayout {
                visible: root.limitsExpanded
                Layout.fillWidth: true
                spacing: root.u(10)
                GridLayout {
                    columns: 2
                    Layout.fillWidth: true
                    Repeater {
                        model: [{key:"max-lifespan", label:"Longevity"}, {key:"balanced",label:"Balanced"}, {key:"plugged-in",label:"Plugged in"}, {key:"full-charge",label:"Full charge"}]
                        Action {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.label
                            enabled: root.canCharge
                            onClicked: root.act("preset", [modelData.key])
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Ui.NumberField {
                        visible: root.startSpec.supported
                        Layout.fillWidth: true
                        label: "Start at (%)"
                        from: root.startSpec.min
                        to: root.startSpec.max
                        value: root.draftStart
                        enabled: root.canCharge
                        foreground: root.foreground
                        onModified: function(value) { root.dirty = true; root.draftStart = value }
                    }
                    Ui.NumberField {
                        Layout.fillWidth: true
                        label: "Stop at (%)"
                        from: root.stopSpec.min
                        to: root.stopSpec.max
                        value: root.draftStop
                        enabled: root.canCharge
                        foreground: root.foreground
                        onModified: function(value) { root.dirty = true; root.draftStop = value }
                    }
                    Action {
                        Layout.alignment: Qt.AlignBottom
                        text: "Apply"
                        enabled: root.canCharge && root.accepts(root.draftStop, root.stopSpec) && (!root.startSpec.supported || (root.accepts(root.draftStart, root.startSpec) && root.draftStart < root.draftStop))
                        onClicked: root.act("threshold", [root.startSpec.supported ? root.draftStart : 0, root.draftStop])
                    }
                }
                Label { visible: root.stopSpec.values.length > 0; text: "Accepted stop values: " + root.stopSpec.values.join(", ") + "%"; color: root.muted }
                Ui.Toggle {
                    Layout.fillWidth: true
                    label: "Keep limits after reboot and sleep"
                    description: "Saves thresholds only; charge behaviour is not saved."
                    checked: root.ctl.boot === true && root.ctl.resume === true
                    enabled: root.canCharge
                    foreground: root.foreground
                    onClicked: root.act("persist", [!checked])
                }
                Label { visible: root.ctl.boot !== root.ctl.resume; text: "Persistence is incomplete. Enable again to repair."; color: root.urgent }
                Action { text: "Restore saved limits"; enabled: root.canCharge && (root.ctl.boot || root.ctl.resume); onClicked: root.act("apply", []) }
                Label { text: "Thresholds apply to all batteries. Charge behaviour applies to the selected battery."; color: root.muted }
                Label { visible: root.ctl.available && !root.stopSpec.supported; text: "Charge limits are not supported by this hardware."; color: root.muted }
            }
            Label { visible: !!root.ctl.error; text: root.ctl.error || ""; color: root.urgent }
            Label { visible: !!root.ctl.warning; text: root.ctl.warning || ""; color: root.urgent }
            Label {
                visible: !!root.backend && (root.backend.message !== "" || root.busy || root.backend.stale)
                text: root.busy ? "Applying… complete system authentication if requested." : root.backend && root.backend.message ? root.backend.message : "Waiting for an update"
                color: root.backend && !root.backend.messageOk ? root.urgent : root.muted
                maximumLineCount: 4
                elide: Text.ElideRight
            }
            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: root.b.id ? root.b.id + " · " + (root.b.model || root.b.manufacturer || "Battery") : "No battery detected"
                    color: root.muted
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
                Rectangle {
                    id: healthIndicator
                    readonly property bool available: root.known(root.b.health) && root.b.health >= 0
                    readonly property color tint: available ? root.accent : root.muted
                    Layout.fillWidth: false
                    implicitWidth: healthContent.implicitWidth + root.u(20)
                    implicitHeight: root.u(34)
                    radius: Math.min(root.cornerRadius, height / 2)
                    color: Qt.rgba(tint.r, tint.g, tint.b, 0.07)
                    border.width: 1
                    border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.18)
                    opacity: root.fresh ? 1 : 0.55
                    Accessible.role: Accessible.StaticText
                    Accessible.name: "Battery health: " + (available ? root.fmt(root.b.health, "%") : "unavailable")

                    RowLayout {
                        id: healthContent
                        anchors.centerIn: parent
                        spacing: root.u(8)
                        BatteryGlyph {
                            Layout.preferredWidth: root.u(24)
                            Layout.preferredHeight: root.u(16)
                            percent: healthIndicator.available ? root.b.health : null
                            foreground: healthIndicator.tint
                            background: root.background
                            alert: false
                        }
                        Label {
                            text: "Health"
                            Layout.fillWidth: false
                            font.pixelSize: Commons.Style.font.caption
                            color: root.muted
                            wrapMode: Text.NoWrap
                        }
                        Label {
                            text: healthIndicator.available ? root.fmt(root.b.health, "%") : "—"
                            Layout.fillWidth: false
                            font.bold: true
                            color: healthIndicator.tint
                            wrapMode: Text.NoWrap
                        }
                    }
                }
            }
        }
    }
}
