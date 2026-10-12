import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts

Item {
    id: dashboard
    property var backend: null
    property color foreground: "#d6d8de"
    property color background: "#14181c"
    property color accent: "#8ba4b8"
    property color muted: "#80858d"
    property color urgent: "#d17f79"
    property string fontFamily: "monospace"
    property real scaleFactor: 1
    property int cornerRadius: 8
    property int activeTab: 0
    property string chartMetric: "percent"
    property bool permanent: true
    property int draftStart: 75
    property int draftStop: 80
    property string initializedBattery: ""
    property int acProfile: 0
    property int batProfile: 1
    property int switching: 0
    property int boostProfile: 1
    property bool policyInitialized: false
    property bool resetConfirm: false
    readonly property var sample: backend ? backend.sample : ({})
    readonly property var battery: backend ? backend.battery : null
    readonly property var b: battery || ({})
    readonly property var tlp: sample.tlp || ({})
    readonly property var care: sample.care || ({})
    readonly property var limits: b.limits || ({})
    readonly property var history: backend ? backend.history : ({points: [], events: [], samples: 0})
    readonly property var cpu: sample.cpu || ({})
    readonly property var config: tlp.config || ({})
    readonly property bool busy: backend ? backend.busy : false
    readonly property bool canControl: tlp.installed === true && tlp.controls === true &&
                                       !busy && !(tlp.conflicts || []).length
    readonly property bool canCharge: canControl && b.id !== "__all__" && limits.supported === true
    readonly property var profileKeys: ["performance", "balanced", "power-saver"]
    readonly property var profileLabels: ["Desempenho", "Equilibrado", "Economia"]
    readonly property var tabs: ["Visão geral", "Carga", "Histórico", "Sistema"]
    readonly property real compactWidth: u(510)
    readonly property color cardColor: alpha(foreground, 0.035)
    readonly property color lineColor: alpha(muted, 0.23)
    implicitWidth: u(640)
    implicitHeight: u(660)

    function u(px) { return Math.round(px * scaleFactor) }
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function fmt(value, digits, suffix) {
        return value === undefined || value === null || !isFinite(value) ? "—" :
               Number(value).toFixed(digits || 0) + (suffix || "")
    }
    function duration(hours) {
        if (hours === undefined || hours === null || !isFinite(hours)) return "—"
        var minutes = Math.round(hours * 60)
        return minutes >= 60 ? Math.floor(minutes/60) + "h " + minutes%60 + "min" : minutes + "min"
    }
    function statusLabel() {
        if (!battery) return "Nenhuma bateria detectada"
        if (b.status === "Charging") return "Carregando até " + (b.charge_target || 100) + "%"
        if (b.status === "Discharging") return "Usando a bateria"
        if (b.status === "Full") return "Carga completa"
        if (sample.ac === true) return "Na tomada · carga em espera"
        return "Sem fluxo de carga informado"
    }
    function profileLabel(key) {
        var index = profileKeys.indexOf(key)
        return index < 0 ? "Não informado" : profileLabels[index]
    }
    function act(op, args) {
        if (backend && !busy) backend.action(op, args || [])
    }
    function accepts(value, spec) {
        return spec && value >= spec.min && value <= spec.max &&
               (!spec.values || spec.values.indexOf(value) >= 0)
    }
    function startFor(stop) {
        var spec = limits.start
        if (!limits.start_supported || !spec) return 0
        var target = Math.max(spec.min, Math.min(spec.max, stop-5))
        if (spec.values) {
            var valid = spec.values.filter(function(v) { return v <= stop-5 })
            return valid.length ? valid[valid.length-1] : spec.values[0]
        }
        return target
    }
    function preset(stop) {
        if (!canCharge || !accepts(stop, limits.stop)) return
        act("threshold", [b.id, startFor(stop), stop, permanent ? "1" : "0"])
    }
    function initializeDraft() {
        if (!b.id || !limits.supported || initializedBattery === b.id) return
        initializedBattery = b.id
        draftStop = accepts(b.stop, limits.stop) ? b.stop :
                    accepts(80, limits.stop) ? 80 : limits.stop.default
        draftStart = limits.start_supported && accepts(b.start, limits.start) ? b.start : startFor(draftStop)
    }
    function initializePolicy() {
        if (policyInitialized || !tlp.installed || !config.TLP_AUTO_SWITCH) return
        var codes = ["PRF", "BAL", "SAV"]
        acProfile = Math.max(0, codes.indexOf(config.TLP_PROFILE_AC || "PRF"))
        batProfile = Math.max(0, codes.indexOf(config.TLP_PROFILE_BAT || "BAL"))
        switching = config.TLP_AUTO_SWITCH === "2" ? 1 : 0
        policyInitialized = true
    }
    function rangeLabel(spec) {
        if (!spec) return "Não informado"
        return spec.values ? spec.values.join(", ") + "%" : spec.min + "–" + spec.max + "%"
    }
    function serviceLabel(value) {
        return value === "active" ? "Ativo" : value === "inactive" || value === "failed" ? "Inativo" : "Não detectado"
    }
    onBChanged: initializeDraft()
    onLimitsChanged: initializeDraft()
    onConfigChanged: initializePolicy()

    component Label: Text {
        color: dashboard.foreground
        font.family: dashboard.fontFamily
        font.pixelSize: dashboard.u(12)
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
    }
    component Caption: Label {
        font.pixelSize: dashboard.u(10)
        color: dashboard.muted
    }
    component Heading: Label {
        font.pixelSize: dashboard.u(13)
        font.bold: true
    }
    component Action: Controls.Button {
        id: actionButton
                implicitHeight: dashboard.u(34)
        implicitWidth: Math.max(dashboard.u(80), label.implicitWidth + dashboard.u(24))
        font.family: dashboard.fontFamily
        font.pixelSize: dashboard.u(11)
        palette.window: dashboard.background
        palette.windowText: dashboard.foreground
        palette.text: dashboard.foreground
        palette.buttonText: dashboard.foreground
        palette.base: dashboard.background
        palette.highlight: dashboard.accent
        leftPadding: dashboard.u(10)
        rightPadding: dashboard.u(10)
        hoverEnabled: true
        opacity: enabled ? 1 : 0.38
        contentItem: Text {
            id: label
            text: actionButton.text
            color: dashboard.foreground
            font.family: dashboard.fontFamily
            font.pixelSize: dashboard.u(11)
            font.bold: actionButton.highlighted
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: Math.max(0, dashboard.cornerRadius)
            color: dashboard.alpha(dashboard.accent, actionButton.down ? 0.28 :
                   actionButton.highlighted ? 0.18 : actionButton.hovered ? 0.1 : 0.025)
            border.width: 1
            border.color: actionButton.activeFocus || actionButton.highlighted ?
                          dashboard.alpha(dashboard.accent, 0.65) : dashboard.lineColor
        }
    }
    component Choice: Controls.ComboBox {
        id: choice
        implicitHeight: dashboard.u(34)
        implicitWidth: dashboard.u(170)
        font.family: dashboard.fontFamily
        font.pixelSize: dashboard.u(11)
        palette.text: dashboard.foreground
        palette.buttonText: dashboard.foreground
        palette.windowText: dashboard.foreground
        palette.base: dashboard.background
        palette.button: dashboard.cardColor
        palette.window: dashboard.background
        palette.highlight: dashboard.alpha(dashboard.accent, 0.25)
        palette.highlightedText: dashboard.foreground
        contentItem: Text {
            text: choice.displayText
            color: choice.enabled ? dashboard.foreground : dashboard.muted
            font: choice.font
            verticalAlignment: Text.AlignVCenter
            leftPadding: dashboard.u(10)
            rightPadding: dashboard.u(22)
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        background: Rectangle {
            radius: Math.max(0, dashboard.cornerRadius)
            color: dashboard.cardColor
            border.width: 1
            border.color: choice.activeFocus ? dashboard.accent : dashboard.lineColor
        }
    }
    component NumberInput: Controls.SpinBox {
        id: numberInput
        editable: true
        implicitWidth: dashboard.u(125)
        implicitHeight: dashboard.u(36)
        font.family: dashboard.fontFamily
        font.pixelSize: dashboard.u(13)
        palette.text: dashboard.foreground
        palette.buttonText: dashboard.foreground
        palette.base: dashboard.background
        palette.button: dashboard.cardColor
        palette.highlight: dashboard.alpha(dashboard.accent, 0.3)
        palette.highlightedText: dashboard.foreground
        opacity: enabled ? 1 : 0.38
        background: Rectangle {
            radius: Math.max(0, dashboard.cornerRadius)
            color: dashboard.cardColor
            border.width: 1
            border.color: numberInput.activeFocus ? dashboard.accent : dashboard.lineColor
        }
    }
    component Check: Controls.CheckBox {
        id: checkbox
        font.family: dashboard.fontFamily
        font.pixelSize: dashboard.u(11)
        palette.text: dashboard.foreground
        palette.windowText: dashboard.foreground
        palette.button: dashboard.background
        palette.base: dashboard.background
        palette.highlight: dashboard.accent
        palette.highlightedText: dashboard.background
        contentItem: Text {
            text: checkbox.text
            font: checkbox.font
            color: dashboard.foreground
            leftPadding: checkbox.indicator.width + dashboard.u(8)
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
        }
    }
    component Card: Rectangle {
        radius: Math.max(0, dashboard.cornerRadius)
        color: dashboard.cardColor
        border.width: 1
        border.color: dashboard.lineColor
    }
    component Metric: Card {
        id: metric
        property string label: ""
        property string value: ""
        property string detail: ""
        implicitHeight: dashboard.u(105)
        Column {
            anchors.fill: parent
            anchors.margins: dashboard.u(13)
            spacing: dashboard.u(5)
            Caption { width: parent.width; text: metric.label }
            Label {
                width: parent.width
                text: metric.value
                font.pixelSize: dashboard.u(23)
                font.bold: true
                maximumLineCount: 1
                elide: Text.ElideRight
            }
            Caption { width: parent.width; text: metric.detail; maximumLineCount: 2; elide: Text.ElideRight }
        }
    }
    component DetailRow: RowLayout {
        property string label: ""
        property string value: ""
        property bool warning: false
        spacing: dashboard.u(12)
        Caption { Layout.fillWidth: true; Layout.preferredWidth: 1; text: parent.label; font.pixelSize: dashboard.u(11) }
        Label {
            Layout.fillWidth: true
            Layout.preferredWidth: 1.2
            text: parent.value
            horizontalAlignment: Text.AlignRight
            color: parent.warning ? dashboard.urgent : dashboard.foreground
            font.pixelSize: dashboard.u(11)
        }
    }
    component CardColumn: Column {
        anchors.fill: parent
        anchors.margins: dashboard.u(16)
        spacing: dashboard.u(12)
    }
    component MessageCard: Card {
        id: notice
        property string text: ""
        property bool warning: false
        implicitHeight: noticeText.implicitHeight + dashboard.u(24)
        color: dashboard.alpha(notice.warning ? dashboard.urgent : dashboard.accent, 0.07)
        border.color: dashboard.alpha(notice.warning ? dashboard.urgent : dashboard.accent, 0.3)
        Label {
            id: noticeText
            x: dashboard.u(12)
            y: dashboard.u(12)
            width: parent.width - dashboard.u(24)
            text: notice.text
            font.pixelSize: dashboard.u(11)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: u(12)
        RowLayout {
            Layout.fillWidth: true
            Column {
                Layout.fillWidth: true; Layout.preferredWidth: 1
                spacing: u(3)
                Caption { text: "ENERGIA  /  TLP"; font.letterSpacing: u(1) }
                Label { text: "Battery Studio"; font.pixelSize: u(24); font.bold: true }
            }
            Choice {
                visible: (sample.batteries || []).length > 1
                Layout.preferredWidth: u(142)
                model: {
                    var result = ["Todas as baterias"]
                    var list = sample.batteries || []
                    for (var i = 0; i < list.length; ++i) result.push(list[i].id)
                    return result
                }
                currentIndex: {
                    if (!backend || backend.selectedId === "__all__") return 0
                    var list = sample.batteries || []
                    for (var i = 0; i < list.length; ++i)
                        if (list[i].id === backend.selectedId) return i+1
                    return 0
                }
                onActivated: function(index) {
                    if (backend) backend.selectBattery(index === 0 ? "__all__" : sample.batteries[index-1].id)
                }
            }
            Action {
                text: "↻"
                implicitWidth: u(36)
                enabled: !busy
                onClicked: if (backend) backend.refresh()
                Controls.ToolTip.visible: hovered
                Controls.ToolTip.text: "Atualizar os dados"
            }
        }
        Row {
            Layout.fillWidth: true
            spacing: u(5)
            Repeater {
                model: dashboard.tabs
                Action {
                    required property int index
                    required property string modelData
                    width: (parent.width - dashboard.u(15))/4
                    text: modelData
                    highlighted: dashboard.activeTab === index
                    onClicked: { dashboard.activeTab = index; dashboard.resetConfirm = false }
                }
            }
        }
        MessageCard {
            Layout.fillWidth: true
            visible: busy || (backend && backend.message !== "")
            text: busy ? "Aguardando a operação e, quando necessário, a autenticação…" :
                         backend ? backend.message : ""
            warning: !busy && backend && !backend.messageOk
        }
        MessageCard {
            Layout.fillWidth: true
            visible: (tlp.conflicts || []).length > 0
            text: "Gerenciador em conflito: " + (tlp.conflicts || []).join(", ") + ". Os controles aguardam a resolução."
            warning: true
        }
        Controls.ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
            Controls.ScrollBar.vertical.policy: Controls.ScrollBar.AsNeeded
            Column {
                id: pages
                width: scroll.availableWidth
                spacing: u(12)

                Column {
                    width: parent.width
                    visible: activeTab === 0
                    spacing: u(12)
                    Card {
                        width: parent.width
                        height: u(143)
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: u(18)
                            Column {
                                Layout.fillWidth: true; Layout.preferredWidth: 1
                                spacing: u(4)
                                Caption { text: sample.ac === true ? "CONECTADO À TOMADA" :
                                                sample.ac === false ? "ENERGIA DA BATERIA" : "FONTE NÃO INFORMADA" }
                                Label { text: fmt(b.percent, 0, "%"); font.pixelSize: u(52); font.bold: true }
                                Label { text: statusLabel(); font.pixelSize: u(11); color: muted }
                            }
                            Column {
                                Layout.preferredWidth: u(113)
                                spacing: u(12)
                                Item {
                                    width: u(113); height: u(54)
                                    Rectangle {
                                        width: parent.width-u(7); height: parent.height
                                        radius: u(7); color: "transparent"
                                        border.width: u(2); border.color: alpha(foreground, 0.35)
                                        Rectangle {
                                            x: u(5); y: u(5); height: parent.height-u(10)
                                            width: (parent.width-u(10))*Math.max(0, Math.min(1, (b.percent || 0)/100))
                                            radius: u(3)
                                            color: b.percent !== undefined && b.percent !== null && b.percent < 20 ?
                                                   urgent : alpha(accent, 0.8)
                                            Behavior on width { NumberAnimation { duration: 220 } }
                                        }
                                    }
                                    Rectangle {
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        width: u(4); height: u(20); radius: u(2); color: alpha(foreground, 0.35)
                                    }
                                }
                                Caption {
                                    width: parent.width
                                    text: b.id === "__all__" ? "Visão combinada" : (b.id || "Sem bateria")
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                    GridLayout {
                        width: parent.width
                        columns: width > dashboard.compactWidth ? 3 : 2
                        columnSpacing: u(8); rowSpacing: u(8)
                        Metric {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            label: b.status === "Charging" ? "Potência de carga" : "Descarga da bateria"
                            value: fmt(b.power_w, 1, " W")
                            detail: b.status === "Charging" ? "Fluxo que entra na bateria" :
                                    sample.ac === true ? "Fluxo da bateria, não da tomada" : "Potência instantânea"
                        }
                        Metric {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            label: b.status === "Charging" ? "Até o limite" : "Autonomia estimada"
                            value: duration(b.hours)
                            detail: "Estimativa pelo fluxo atual"
                        }
                        Metric {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            label: "Saúde da bateria"
                            value: fmt(b.health, 1, "%")
                            detail: fmt(b.cycles, 0, " ciclos") + " · " + fmt(b.wear, 1, "% desgaste")
                        }
                    }
                    Card {
                        width: parent.width
                        height: u(231)
                        CardColumn {
                            Heading { text: "Fluxo de energia"; width: parent.width }
                            Caption { text: "Últimas " + (backend ? backend.historyHours : 24) + " horas · registros por minuto"; width: parent.width }
                            HistoryChart {
                                width: parent.width; height: u(155)
                                dataset: dashboard.history; metric: "power"
                                foreground: dashboard.foreground; accent: dashboard.accent
                                muted: dashboard.muted; background: dashboard.background
                                fontFamily: dashboard.fontFamily; scaleFactor: dashboard.scaleFactor
                            }
                        }
                    }
                    Card {
                        width: parent.width
                        height: profilesColumn.implicitHeight + u(32)
                        CardColumn {
                            id: profilesColumn
                            Heading { text: "Perfil de energia"; width: parent.width }
                            Caption { text: "Atual: " + profileLabel(tlp.profile) +
                                            (tlp.manual ? " · seleção manual" : ""); width: parent.width }
                            Row {
                                width: parent.width; spacing: u(6)
                                Repeater {
                                    model: ["Automático", "Economia", "Equilibrado", "Desempenho"]
                                    Action {
                                        required property int index
                                        required property string modelData
                                        readonly property string key: ["auto", "power-saver", "balanced", "performance"][index]
                                        width: (parent.width-dashboard.u(18))/4
                                        text: modelData
                                        enabled: dashboard.canControl && (key !== "power-saver" || dashboard.tlp.supports_saver)
                                        highlighted: key !== "auto" && dashboard.tlp.profile === key
                                        onClicked: dashboard.act("profile", [key])
                                    }
                                }
                            }
                            Caption { width: parent.width; text: "Automático devolve a seleção ao TLP; os outros botões aplicam um perfil manual." }
                            Caption {
                                width: parent.width
                                visible: !tlp.controls || !tlp.installed
                                text: !tlp.installed ? "TLP não instalado. O monitoramento continua disponível." :
                                      "Instale os controles com a opção --with-controls do instalador."
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    visible: activeTab === 1
                    spacing: u(12)
                    MessageCard {
                        width: parent.width
                        visible: b.id === "__all__"
                        text: "Selecione uma bateria no menu acima para ajustar sua proteção de carga."
                    }
                    Card {
                        width: parent.width
                        height: chargeColumn.implicitHeight + u(32)
                        CardColumn {
                            id: chargeColumn
                            RowLayout {
                                width: parent.width
                                Heading { Layout.fillWidth: true; text: "Proteção de carga" }
                                Action {
                                    text: "Verificar recursos"
                                    enabled: tlp.installed === true && tlp.controls === true && !busy
                                    onClicked: act("inspect", [])
                                }
                            }
                            Label {
                                width: parent.width
                                text: limits.fixed ? "Este modelo usa um limite fixo definido pelo fabricante." :
                                      b.stop !== undefined && b.stop !== null ?
                                      "Limite aplicado: " + b.stop + "%" +
                                      (b.start !== undefined && b.start !== null ? " · retoma abaixo de " + b.start + "%" : "") :
                                      "O firmware não informou os limites atuais."
                            }
                            Caption {
                                width: parent.width
                                visible: !limits.supported && b.id !== "__all__"
                                text: "O suporte ainda não foi confirmado pelo TLP. Use Verificar recursos; controles incompatíveis ficam indisponíveis."
                            }
                            Check {
                                width: parent.width
                                text: "Manter o ajuste após reiniciar"
                                checked: permanent
                                onToggled: permanent = checked
                            }
                            Row {
                                width: parent.width; spacing: u(8)
                                visible: !limits.fixed
                                Repeater {
                                    model: [{label: "Mesa · 60%", stop: 60}, {label: "Diário · 80%", stop: 80}, {label: "Viagem · 95%", stop: 95}]
                                    Action {
                                        required property var modelData
                                        width: (parent.width-dashboard.u(16))/3
                                        text: modelData.label
                                        highlighted: dashboard.b.stop === modelData.stop
                                        enabled: dashboard.canCharge && dashboard.accepts(modelData.stop, dashboard.limits.stop) &&
                                                 (!dashboard.limits.start_supported || dashboard.startFor(modelData.stop) < modelData.stop)
                                        onClicked: dashboard.preset(modelData.stop)
                                    }
                                }
                            }
                            RowLayout {
                                width: parent.width
                                visible: !limits.fixed && limits.supported === true
                                Column {
                                    Layout.fillWidth: true; Layout.preferredWidth: 1
                                    spacing: u(6)
                                    Caption { text: "Iniciar abaixo de"; width: parent.width }
                                    NumberInput {
                                        width: parent.width
                                        enabled: canCharge && limits.start_supported
                                        from: limits.start ? limits.start.min : 0
                                        to: limits.start ? limits.start.max : 0
                                        value: draftStart
                                        onValueModified: draftStart = value
                                    }
                                }
                                Column {
                                    Layout.fillWidth: true; Layout.preferredWidth: 1
                                    spacing: u(6)
                                    Caption { text: "Parar em"; width: parent.width }
                                    NumberInput {
                                        width: parent.width
                                        enabled: canCharge
                                        from: limits.stop ? Math.max(1, limits.stop.min) : 1
                                        to: limits.stop ? limits.stop.max : 100
                                        value: draftStop
                                        onValueModified: draftStop = value
                                    }
                                }
                                Action {
                                    text: "Aplicar"
                                    Layout.alignment: Qt.AlignBottom
                                    highlighted: true
                                    enabled: canCharge && accepts(draftStop, limits.stop) &&
                                             (!limits.start_supported || accepts(draftStart, limits.start) && draftStart < draftStop)
                                    onClicked: act("threshold", [b.id, limits.start_supported ? draftStart : 0,
                                                                draftStop, permanent ? "1" : "0"])
                                }
                            }
                            Caption {
                                width: parent.width
                                visible: limits.supported === true && !limits.fixed
                                text: "Fim permitido: " + rangeLabel(limits.stop) +
                                      (limits.start_supported ? " · Início: " + rangeLabel(limits.start) : " · Início controlado pelo hardware")
                            }
                            Row {
                                width: parent.width; spacing: u(8)
                                Action {
                                    visible: limits.fixed === true
                                    text: "Ativar conservação"
                                    enabled: canCharge
                                    onClicked: act("threshold", [b.id, 0, 1, permanent ? "1" : "0"])
                                }
                                Action {
                                    text: "Desativar limite"
                                    enabled: canCharge
                                    onClicked: act("unlimit", [b.id, permanent ? "1" : "0"])
                                }
                            }
                            Caption {
                                width: parent.width
                                text: "Se a carga já estiver acima do limite, ela não é descarregada à força. A recarga aguarda a faixa configurada."
                            }
                        }
                    }
                    Card {
                        width: parent.width
                        height: onceColumn.implicitHeight + u(32)
                        CardColumn {
                            id: onceColumn
                            Heading { width: parent.width; text: "Uma carga extra" }
                            Caption { width: parent.width; text: "Para sair com mais autonomia, libere uma carga sem apagar a proteção permanente." }
                            Flow {
                                width: parent.width; spacing: u(8)
                                Action {
                                    text: "100% uma vez"
                                    enabled: canCharge
                                    onClicked: act("fullcharge", [b.id])
                                }
                                Action {
                                    text: "Retomar limite"
                                    enabled: canCharge
                                    onClicked: act("restore-charge", [b.id])
                                }
                                Action {
                                    visible: care.chargeonce === true
                                    text: "Carregar até o limite"
                                    enabled: canCharge && care.chargeonce
                                    onClicked: act("chargeonce", [b.id])
                                }
                            }
                            Caption { width: parent.width; text: "A restauração automática segue a configuração do TLP. Você também pode retomá-la pelo botão acima." }
                        }
                    }
                    Card {
                        width: parent.width
                        height: batteryColumn.implicitHeight + u(32)
                        CardColumn {
                            id: batteryColumn
                            Heading { width: parent.width; text: "Informações da bateria" }
                            DetailRow { width: parent.width; label: "Fabricante / modelo"; value: [b.manufacturer, b.model].filter(Boolean).join(" · ") || "—" }
                            DetailRow { width: parent.width; label: "Capacidade de fábrica"; value: fmt(b.design_wh, 2, " Wh") }
                            DetailRow { width: parent.width; label: "Capacidade atual máxima"; value: fmt(b.full_wh, 2, " Wh") }
                            DetailRow { width: parent.width; label: "Energia restante"; value: fmt(b.energy_wh, 2, " Wh") }
                            DetailRow { width: parent.width; label: "Tensão / corrente"; value: fmt(b.voltage_v, 2, " V") + " / " + fmt(b.current_a, 2, " A") }
                            DetailRow { width: parent.width; label: "Temperatura da bateria"; value: fmt(b.temperature_c, 1, " °C"); warning: b.temperature_c !== null && b.temperature_c > 40 }
                            DetailRow { width: parent.width; label: "Tecnologia"; value: b.technology || "—" }
                            Caption {
                                width: parent.width
                                visible: b.derived_energy === true
                                text: "Capacidades em Wh estimadas a partir de Ah e tensão nominal."
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    visible: activeTab === 2
                    spacing: u(12)
                    Row {
                        width: parent.width; spacing: u(6)
                        Repeater {
                            model: [{label: "1h", hours: 1}, {label: "6h", hours: 6}, {label: "24h", hours: 24},
                                    {label: "7d", hours: 168}, {label: "30d", hours: 720}]
                            Action {
                                required property var modelData
                                width: (parent.width-dashboard.u(24))/5
                                text: modelData.label
                                highlighted: backend && backend.historyHours === modelData.hours
                                onClicked: if (backend) backend.selectHistory(modelData.hours)
                            }
                        }
                    }
                    Row {
                        width: parent.width; spacing: u(6)
                        Repeater {
                            model: [{label: "Carga (%)", key: "percent"}, {label: "Potência (W)", key: "power"}, {label: "Saúde (%)", key: "health"}]
                            Action {
                                required property var modelData
                                width: (parent.width-dashboard.u(12))/3
                                text: modelData.label
                                highlighted: chartMetric === modelData.key
                                onClicked: chartMetric = modelData.key
                            }
                        }
                    }
                    Card {
                        width: parent.width; height: u(266)
                        HistoryChart {
                            anchors.fill: parent; anchors.margins: u(12)
                            dataset: dashboard.history; metric: dashboard.chartMetric
                            foreground: dashboard.foreground; accent: dashboard.accent
                            muted: dashboard.muted; background: dashboard.background
                            fontFamily: dashboard.fontFamily; scaleFactor: dashboard.scaleFactor
                        }
                    }
                    GridLayout {
                        width: parent.width; columns: 2; columnSpacing: u(8)
                        Metric {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            label: "Média na bateria"; value: fmt(history.average_w, 1, " W")
                            detail: "Apenas registros de descarga"
                        }
                        Metric {
                            Layout.fillWidth: true; Layout.preferredWidth: 1
                            label: "Pico de descarga"; value: fmt(history.peak_w, 1, " W")
                            detail: (history.samples || 0) + " registros no período"
                        }
                    }
                    RowLayout {
                        width: parent.width
                        Action { text: "Exportar CSV"; enabled: !busy && history.samples > 0; onClicked: if (backend) backend.exportHistory() }
                        Item { Layout.fillWidth: true }
                        Caption { text: "Guardar por" }
                        Choice {
                            Layout.preferredWidth: u(108)
                            model: ["7 dias", "30 dias", "90 dias"]
                            currentIndex: [7, 30, 90].indexOf(sample.retention_days || 30)
                            onActivated: function(index) { if (backend) backend.setRetention([7, 30, 90][index]) }
                        }
                    }
                    Caption {
                        width: parent.width
                        text: "Dados locais, sem envio à internet. Reduzir a retenção elimina os registros mais antigos. Lacunas de suspensão aparecem no gráfico."
                    }
                    MessageCard { width: parent.width; visible: !!sample.history_error; warning: true; text: sample.history_error || "" }
                    Card {
                        width: parent.width
                        height: eventColumn.implicitHeight + u(32)
                        CardColumn {
                            id: eventColumn
                            Heading { width: parent.width; text: "Eventos de energia" }
                            Caption { width: parent.width; visible: !(history.events || []).length; text: "Nenhum evento registrado neste período." }
                            Repeater {
                                model: history.events || []
                                DetailRow {
                                    required property var modelData
                                    width: parent.width
                                    label: Qt.formatDateTime(new Date(modelData.ts*1000), "dd/MM HH:mm")
                                    value: modelData.detail
                                }
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    visible: activeTab === 3
                    spacing: u(12)
                    Card {
                        width: parent.width
                        height: systemColumn.implicitHeight + u(32)
                        CardColumn {
                            id: systemColumn
                            Heading { width: parent.width; text: "TLP e sistema" }
                            DetailRow { width: parent.width; label: "Versão do TLP"; value: tlp.version || "Não instalado" }
                            DetailRow { width: parent.width; label: "Serviço TLP"; value: serviceLabel((tlp.services || {})["tlp.service"]) }
                            DetailRow { width: parent.width; label: "TLP Profiles Daemon"; value: serviceLabel((tlp.services || {})["tlp-pd.service"]) }
                            DetailRow { width: parent.width; label: "Perfil atual"; value: profileLabel(tlp.profile) }
                            DetailRow {
                                width: parent.width
                                label: "Carregador conectado"
                                value: (sample.chargers || []).filter(function(c) { return c.online }).map(function(c) {
                                    return c.id + " · " + c.type + (c.voltage_v !== null && c.voltage_v !== undefined ?
                                           " · " + dashboard.fmt(c.voltage_v, 1, " V") : "")
                                }).join(", ") || (sample.ac === false ? "Não" : "Não informado")
                            }
                            DetailRow { width: parent.width; label: "Temperatura da CPU"; value: fmt(cpu.temperature_c, 1, " °C"); warning: cpu.temperature_c > 85 }
                            DetailRow { width: parent.width; label: "Driver / governor"; value: [cpu.driver, cpu.governor].filter(Boolean).join(" · ") || "—" }
                            DetailRow { width: parent.width; label: "Política de energia da CPU"; value: cpu.epp || "—" }
                            DetailRow { width: parent.width; label: "Perfil da plataforma"; value: cpu.platform_profile || "—" }
                            DetailRow { width: parent.width; label: "Turbo da CPU agora"; value: cpu.boost_enabled === true ? "Ativo" : cpu.boost_enabled === false ? "Desativado" : "Não informado" }
                            Flow {
                                width: parent.width; spacing: u(8)
                                Action { text: "Salvar diagnóstico"; enabled: !busy; onClicked: if (backend) backend.report() }
                                Action {
                                    visible: (tlp.services || {})["tlp.service"] !== "active"
                                    text: "Habilitar TLP"
                                    enabled: canControl
                                    onClicked: act("enable-tlp", [])
                                }
                            }
                        }
                    }
                    Card {
                        width: parent.width
                        height: autoColumn.implicitHeight + u(32)
                        CardColumn {
                            id: autoColumn
                            Heading { width: parent.width; text: "Alternância automática" }
                            Caption { width: parent.width; text: "Escolha os perfis que o TLP usará quando o carregador for conectado ou removido." }
                            RowLayout {
                                width: parent.width; spacing: u(10)
                                Column {
                                    Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: u(6)
                                    Caption { text: "Na tomada" }
                                    Choice {
                                        width: parent.width; model: profileLabels; currentIndex: acProfile
                                        enabled: tlp.supports_policy === true && canControl
                                        onActivated: function(index) { acProfile = index }
                                    }
                                }
                                Column {
                                    Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: u(6)
                                    Caption { text: "Na bateria" }
                                    Choice {
                                        width: parent.width; model: profileLabels; currentIndex: batProfile
                                        enabled: tlp.supports_policy === true && canControl
                                        onActivated: function(index) { batProfile = index }
                                    }
                                }
                            }
                            Choice {
                                width: parent.width
                                model: ["Sempre seguir o carregador", "Respeitar o perfil selecionado manualmente"]
                                currentIndex: switching
                                enabled: tlp.supports_policy === true && canControl
                                onActivated: function(index) { switching = index }
                            }
                            Action {
                                text: "Salvar alternância"
                                highlighted: true
                                enabled: tlp.supports_policy === true && canControl
                                onClicked: act("auto-policy", [profileKeys[acProfile], profileKeys[batProfile], String(switching+1)])
                            }
                            Caption {
                                width: parent.width
                                visible: !tlp.supports_policy
                                text: "Políticas personalizadas exigem TLP 1.10+. Em versões anteriores, o botão Automático aplica a política disponível."
                            }
                        }
                    }
                    Card {
                        width: parent.width
                        height: turboColumn.implicitHeight + u(32)
                        CardColumn {
                            id: turboColumn
                            Heading { width: parent.width; text: "Turbo por perfil" }
                            Caption { width: parent.width; text: "Desativar o turbo pode reduzir aquecimento e consumo, com menor desempenho em tarefas intensas." }
                            RowLayout {
                                width: parent.width; spacing: u(8)
                                Choice {
                                    Layout.fillWidth: true
                                    model: profileLabels
                                    currentIndex: boostProfile
                                    onActivated: function(index) { boostProfile = index }
                                }
                                Action {
                                    text: "Ativar"
                                    enabled: canControl && cpu.boost_supported === true &&
                                             (boostProfile !== 2 || tlp.supports_saver)
                                    onClicked: act("cpu-boost", [profileKeys[boostProfile], "1"])
                                }
                                Action {
                                    text: "Desativar"
                                    enabled: canControl && cpu.boost_supported === true &&
                                             (boostProfile !== 2 || tlp.supports_saver)
                                    onClicked: act("cpu-boost", [profileKeys[boostProfile], "0"])
                                }
                            }
                            Caption {
                                width: parent.width
                                text: "O ajuste é salvo no perfil escolhido. Não altera os outros perfis."
                            }
                        }
                    }
                    Card {
                        width: parent.width
                        height: resetColumn.implicitHeight + u(32)
                        CardColumn {
                            id: resetColumn
                            Heading { width: parent.width; text: "Ajustes gerenciados" }
                            Caption { width: parent.width; text: "O plugin mantém seus ajustes em um arquivo próprio. Configurações externas do TLP têm precedência e são preservadas." }
                            Action {
                                text: resetConfirm ? "Confirmar restauração" : "Restaurar ajustes externos"
                                enabled: canControl && tlp.managed
                                onClicked: {
                                    if (!resetConfirm) resetConfirm = true
                                    else { act("reset", []); resetConfirm = false }
                                }
                            }
                            Caption {
                                visible: resetConfirm; width: parent.width
                                text: "Remove as configurações salvas pelo Battery Studio e reaplica o TLP e os limites anteriores disponíveis."
                            }
                        }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Caption {
                Layout.fillWidth: true
                text: backend && backend.stale ? "Aguardando dados…" :
                      "Ao vivo · histórico a cada minuto · " + (b.id || "sem bateria")
            }
            Caption { text: "v1.0.0" }
        }
    }
}
