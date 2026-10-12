"""Read-only battery calculations and TLP capability parsing. Python stdlib only."""
from __future__ import annotations

import math
import os
from pathlib import Path
import re
import subprocess
import time

SYS = Path("/sys")
PROFILES = {"performance": "PRF", "balanced": "BAL", "power-saver": "SAV"}
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def read(path: Path, default=None):
    try:
        return path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError):
        return default


def number(path: Path):
    try:
        value = float(read(path))
        return value if math.isfinite(value) else None
    except (TypeError, ValueError):
        return None


def positive(value):
    return value if value is not None and value > 0 else None


def ratio(numerator, denominator):
    return numerator / denominator if numerator is not None and positive(denominator) else None


def scaled(path: Path, scale=1_000_000):
    value = number(path)
    return value / scale if value is not None else None


def version_tuple(raw: str):
    found = re.search(r"(\d+)\.(\d+)(?:\.(\d+))?", raw or "")
    return tuple(int(x or 0) for x in found.groups()) if found else (0, 0, 0)


def run(argv, timeout=6):
    """Never invokes a shell; commands and outputs are bounded."""
    try:
        result = subprocess.run(
            argv, capture_output=True, text=True, timeout=timeout,
            env={**os.environ, "LC_ALL": "C", "LANG": "C", "TLP_MSG_COLORS": ""},
        )
        return result.returncode, ANSI.sub("", result.stdout), ANSI.sub("", result.stderr)
    except (OSError, subprocess.TimeoutExpired) as error:
        return 127, "", str(error)


def battery_dirs(sys=SYS):
    base = sys / "class/power_supply"
    try:
        return sorted(p for p in base.iterdir()
                      if read(p / "type") == "Battery"
                      and read(p / "scope") != "Device"
                      and read(p / "present", "1") != "0")
    except OSError:
        return []


def source_info(sys=SYS):
    """USB, USB-C and mains supplies count; peripheral device supplies do not."""
    items = []
    try:
        paths = sorted((sys / "class/power_supply").iterdir())
    except OSError:
        paths = []
    for p in paths:
        kind = read(p / "type", "")
        if kind == "Battery" or read(p / "scope") == "Device":
            continue
        online = number(p / "online")
        if online is None:
            continue
        items.append({
            "id": p.name, "type": kind, "online": online == 1,
            "voltage_v": scaled(p / "voltage_now"),
            "current_a": scaled(p / "current_now"),
            "power_w": scaled(p / "power_now"),
            "usb_type": read(p / "usb_type"),
        })
    return {"ac": any(i["online"] for i in items) if items else None, "chargers": items}


def battery_info(p: Path):
    energy_now = scaled(p / "energy_now")
    energy_full = positive(scaled(p / "energy_full"))
    energy_design = positive(scaled(p / "energy_full_design"))
    charge_now = scaled(p / "charge_now")
    charge_full = positive(scaled(p / "charge_full"))
    charge_design = positive(scaled(p / "charge_full_design"))
    voltage = positive(scaled(p / "voltage_now"))
    nominal = positive(scaled(p / "voltage_min_design")) or voltage
    power = scaled(p / "power_now")
    current = scaled(p / "current_now")
    power_source = "power_now"
    if power is None and current is not None and voltage is not None:
        power, power_source = abs(current) * voltage, "current_now × voltage_now"
    power = abs(power) if power is not None else None
    charge_only = energy_now is None
    if charge_only and nominal:
        energy_now = charge_now * nominal if charge_now is not None else None
        energy_full = charge_full * nominal if charge_full else None
        energy_design = charge_design * nominal if charge_design else None
    fraction = ratio(charge_now, charge_full) if charge_only else ratio(energy_now, energy_full)
    percentage = number(p / "capacity")
    if percentage is None and fraction is not None:
        percentage = fraction * 100
    if percentage is not None:
        percentage = max(0.0, min(100.0, percentage))
    health = ratio(charge_full, charge_design) if charge_only else ratio(energy_full, energy_design)
    health = health * 100 if health is not None else None
    start = number(p / "charge_control_start_threshold")
    stop = number(p / "charge_control_end_threshold")
    status = read(p / "status", "Unknown")
    signed = None
    if status == "Discharging":
        signed = power
    elif status == "Charging":
        signed = -power if power is not None else None
    elif status in ("Full", "Not charging"):
        signed = 0.0
    hours = None
    target = stop if stop is not None and 1 <= stop < 100 else 100
    if status == "Discharging":
        hours = ratio(charge_now, abs(current)) if charge_only and current is not None else ratio(energy_now, power)
    elif status == "Charging":
        if charge_only and charge_full is not None and charge_now is not None and current is not None:
            hours = ratio(max(0, charge_full * target / 100 - charge_now), abs(current))
        elif energy_full is not None and energy_now is not None:
            hours = ratio(max(0, energy_full * target / 100 - energy_now), power)
    # Instantaneous estimates at tiny currents are misleading.
    if hours is not None and (hours > 72 or power is None or power < 0.3):
        hours = None
    return {
        "id": p.name, "status": status, "percent": percentage,
        "energy_wh": energy_now, "full_wh": energy_full, "design_wh": energy_design,
        "charge_ah": charge_now, "voltage_v": voltage, "current_a": current,
        "power_w": power, "signed_power_w": signed, "power_source": power_source if power is not None else None,
        "health": health, "wear": max(0, 100-health) if health is not None else None,
        "cycles": number(p / "cycle_count"), "temperature_c": scaled(p / "temp", 10),
        "hours": hours, "charge_target": target, "start": start, "stop": stop,
        "manufacturer": read(p / "manufacturer"), "model": read(p / "model_name"),
        "technology": read(p / "technology"), "derived_energy": charge_only and nominal is not None,
    }


def aggregate(batteries):
    if not batteries:
        return None
    if len(batteries) == 1:
        return dict(batteries[0])
    def total(key):
        values = [b.get(key) for b in batteries]
        return sum(values) if all(v is not None for v in values) else None
    energy, full, design = total("energy_wh"), total("full_wh"), total("design_wh")
    weighted = ratio(energy, full)
    percentages = [b["percent"] for b in batteries if b["percent"] is not None]
    percent = weighted * 100 if weighted is not None else (
        sum(percentages)/len(percentages) if percentages else None)
    flow = total("signed_power_w")
    states = {b["status"] for b in batteries}
    state = "Charging" if flow is not None and flow < -0.1 else (
        "Discharging" if flow is not None and flow > 0.1 else (
            next(iter(states)) if len(states) == 1 else "Not charging"))
    health = ratio(full, design)
    hours = ratio(energy, flow) if state == "Discharging" else (
        ratio(max(0, full-energy), -flow) if state == "Charging" and full is not None and energy is not None else None)
    if hours is not None and (hours > 72 or abs(flow or 0) < 0.3):
        hours = None
    return {
        "id": "__all__", "status": state, "percent": percent, "energy_wh": energy,
        "full_wh": full, "design_wh": design, "power_w": abs(flow) if flow is not None else None,
        "signed_power_w": flow, "power_source": "Soma das baterias",
        "health": health*100 if health is not None else None,
        "wear": max(0, 100-health*100) if health is not None else None,
        "hours": hours, "cycles": None, "temperature_c": None, "voltage_v": None,
        "manufacturer": None, "model": str(len(batteries))+" baterias", "start": None, "stop": None,
        "charge_target": 100,
    }


def parse_range(raw):
    """Parse ranges emitted by tlp-stat, including discrete hardware presets."""
    numbers = [int(n) for n in re.findall(r"(?<![A-Za-z])\b\d+\b", raw)]
    numbers = [n for n in numbers if 0 <= n <= 100]
    if not numbers or "don't care" in raw.lower() or "don’t care" in raw.lower():
        return {"min": 0, "max": 0, "values": [0], "default": 0, "raw": raw, "dummy": True}
    match = re.search(r"(\d+)\s*\(default\)", raw, re.I) or re.search(
        r"(\d+)\s*\((?:off|Standard)\)", raw, re.I)
    default = int(match[1]) if match else max(numbers)
    # '..' denotes a continuous range. Commas denote fixed supported choices.
    values = None if ".." in raw and len(set(numbers)) > 1 else sorted(set(numbers))
    return {"min": min(numbers), "max": max(numbers), "values": values, "default": default, "raw": raw, "dummy": False}


def parse_care(raw):
    raw = ANSI.sub("", raw or "")
    match = re.search(r"^Plugin:\s*(\S+)", raw, re.M)
    plugin = match[1] if match else None
    features_match = re.search(r"^Supported features:\s*(.+)", raw, re.M)
    features = features_match[1].strip() if features_match else ""
    parameters = {}
    for kind, indices, value in re.findall(
        r"^\s*\*\s*(START|STOP)_CHARGE_THRESH_BAT([01](?:/[01])?)\s*:\s*(.+)$", raw, re.M
    ):
        for index in indices.split("/"):
            parameters.setdefault(index, {})[kind.lower()] = parse_range(value)
    supported = bool(parameters) and bool(features) and "none" not in features.lower()
    return {
        "plugin": plugin, "features": features, "parameters": parameters,
        "supported": supported,
        "fixed_conservation": plugin in ("lenovo", "lenovo-legacy"),
        "chargeonce": plugin in ("thinkpad", "thinkpad-legacy", "cros-ec")
                      and "recalibration" in features,
        "recalibrate": "recalibration" in features,
    }


def battery_slot(name, plugin, count=1):
    if plugin in ("huawei", "lenovo", "lenovo-legacy", "lg", "lg-legacy", "macbook", "samsung"):
        return "0"
    if name in ("BAT0", "BAT1"):
        return name[-1]
    if plugin == "asus" and name in ("BATC", "BATT"):
        return "0"
    if count == 1:
        return "0"
    return None


def limits_for(care, name, count=1):
    slot = battery_slot(name, care.get("plugin"), count)
    limits = care.get("parameters", {}).get(slot, {})
    return {
        **limits, "slot": slot, "supported": care.get("supported", False) and "stop" in limits,
        "fixed": care.get("fixed_conservation", False),
        "start_supported": "start" in limits and not limits["start"].get("dummy", False),
    }


def validate_value(value, limits, label):
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(label+" deve ser um número inteiro.")
    if value < limits["min"] or value > limits["max"] or (
        limits["values"] is not None and value not in limits["values"]
    ):
        raise ValueError(label+" não é aceito pelo hardware: "+limits["raw"])


def parse_config(raw):
    result = {}
    for line in ANSI.sub("", raw or "").splitlines():
        found = re.search(r"(?:^|:\s*)([A-Z][A-Z0-9_]*)=(.*)$", line)
        if found:
            value = found[2].strip()
            if value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
            result[found[1]] = value
    return result


def parse_tlp_status(raw):
    def field(key):
        m = re.search(r"^"+key+r"\s*=\s*(.+)$", raw, re.M | re.I)
        return m[1].strip() if m else None
    mode = field("TLP profile") or field("Mode") or field("Profile") or ""
    lower = mode.lower()
    if "power-saver" in lower or re.search(r"\bsav\b", lower):
        profile = "power-saver"
    elif "performance" in lower or re.search(r"\b(ac|prf)\b", lower):
        profile = "performance"
    elif "balanced" in lower or re.search(r"\b(bat|bal)\b", lower):
        profile = "balanced"
    else:
        profile = None
    state = field("State")
    if state is None:
        tlp_state = field("tlp")
        if tlp_state:
            state = tlp_state.split(",", 1)[0]
    return {
        "profile": profile, "mode": mode or None,
        "manual": "manual" in lower, "state": state, "source": field("Power source"),
    }


def cpu_info(sys=SYS):
    cpu = sys / "devices/system/cpu/cpu0/cpufreq"
    temperatures = []
    try:
        paths = sorted((sys / "class/hwmon").iterdir())
    except OSError:
        paths = []
    for hw in paths:
        if read(hw / "name") not in ("coretemp", "k10temp", "zenpower", "cpu_thermal"):
            continue
        for p in sorted(hw.glob("temp*_input")):
            value = scaled(p, 1000)
            if value is not None and 0 <= value < 150:
                temperatures.append(value)
    no_turbo = number(sys / "devices/system/cpu/intel_pstate/no_turbo")
    boost = number(sys / "devices/system/cpu/cpufreq/boost")
    return {
        "driver": read(cpu / "scaling_driver"), "governor": read(cpu / "scaling_governor"),
        "epp": read(cpu / "energy_performance_preference"),
        "platform_profile": read(sys / "firmware/acpi/platform_profile"),
        "temperature_c": max(temperatures) if temperatures else None,
        "boost_supported": no_turbo is not None or boost is not None,
        "boost_enabled": no_turbo == 0 if no_turbo is not None else (
            boost == 1 if boost is not None else None),
    }


def snapshot(sys=SYS):
    batteries = [battery_info(p) for p in battery_dirs(sys)]
    source = source_info(sys)
    if source["ac"] is None and batteries:
        # Keep source unknown if all batteries are idle and no supply reports it.
        if any(b["status"] == "Charging" for b in batteries):
            source["ac"] = True
        elif any(b["status"] == "Discharging" for b in batteries):
            source["ac"] = False
    return {
        "ts": time.time(), "batteries": batteries, "aggregate": aggregate(batteries),
        **source, "cpu": cpu_info(sys),
    }
