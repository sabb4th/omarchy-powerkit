// Pure formatting and presentation. No state writes or hardware commands.
var modes = ["full", "percentage", "icon", "watts", "runtime", "percentage-runtime", "profile"]

function nextMode(mode) {
    var index = modes.indexOf(mode)
    return modes[(index + 1 + modes.length) % modes.length]
}

function level(percent) {
    if (percent === null || percent === undefined || !isFinite(percent)) return -1
    if (percent <= 0) return 0
    return Math.max(1, Math.min(10, Math.ceil(percent / 10)))
}

function percentText(value) {
    return value === null || value === undefined || !isFinite(value) ? "—" : Math.round(value) + "%"
}

function wattsText(value) {
    if (value === null || value === undefined || !isFinite(value)) return "— W"
    var result = Number(value).toFixed(1)
    return result + " W"
}

function runtimeText(hours) {
    if (hours === null || hours === undefined || !isFinite(hours)) return "—"
    var minutes = Math.round(hours * 60)
    return minutes >= 60 ? Math.floor(minutes / 60) + "h " + minutes % 60 + "m" : minutes + "m"
}

function profileText(key) {
    return key === "performance" ? "PRF" : key === "balanced" ? "BAL" : key === "power-saver" ? "SAV" : "—"
}

function barText(mode, battery, profile) {
    var b = battery || {}
    if (mode === "icon") return ""
    if (mode === "percentage") return percentText(b.percent)
    if (mode === "watts") return wattsText(b.power_w)
    if (mode === "runtime") return runtimeText(b.hours)
    if (mode === "percentage-runtime") return percentText(b.percent) + " · " + runtimeText(b.hours)
    if (mode === "profile") return percentText(b.percent) + " · " + profileText(profile)
    return percentText(b.percent) + " · " + wattsText(b.power_w)
}
