#!/usr/bin/env python3
"""Unprivileged collector, history, export and client for the root-owned helper."""
from __future__ import annotations

import argparse
import csv
import json
import os
from pathlib import Path
import platform
import selectors
import shutil
import sqlite3
import sys
import time

from domain import (
    battery_dirs, limits_for, parse_care, parse_config, parse_tlp_status, read, run,
    snapshot, version_tuple,
)

HELPER = Path("/usr/local/lib/omarchy-battery-studio/control.py")
OPERATIONS = {
    "inspect": 0, "profile": 1, "threshold": 4, "unlimit": 2,
    "fullcharge": 1, "chargeonce": 1, "restore-charge": 1,
    "auto-policy": 3, "cpu-boost": 2, "enable-tlp": 0, "reset": 0,
}
SERVICES = [
    "tlp.service", "tlp-pd.service", "power-profiles-daemon.service",
    "auto-cpufreq.service", "tuned.service", "tuned-ppd.service",
]


def state_dir():
    base = Path(os.environ.get("XDG_STATE_HOME") or Path.home()/".local/state")
    path = base / "omarchy-battery-studio"
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    return path


def emit(value):
    print(json.dumps(value, ensure_ascii=False, allow_nan=False), flush=True)


class History:
    def __init__(self, path=None):
        self.path = Path(path or state_dir()/"history.sqlite3")
        self.db = sqlite3.connect(self.path, timeout=5)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript("""
          CREATE TABLE IF NOT EXISTS samples (
            ts INTEGER NOT NULL, battery TEXT NOT NULL, percent REAL, power REAL,
            health REAL, energy REAL, ac INTEGER, status TEXT,
            PRIMARY KEY (ts, battery));
          CREATE TABLE IF NOT EXISTS events (
            ts REAL NOT NULL, kind TEXT NOT NULL, detail TEXT, boot TEXT);
          CREATE INDEX IF NOT EXISTS events_ts ON events(ts);
        """)
        os.chmod(self.path, 0o600)
        self.last_bucket = None
        previous = self.db.execute("SELECT ac FROM samples ORDER BY ts DESC LIMIT 1").fetchone()
        self.last_source = bool(previous[0]) if previous and previous[0] is not None else None
        self.boot = read(Path("/proc/sys/kernel/random/boot_id"), "unknown")
        row = self.db.execute("SELECT boot FROM events ORDER BY ts DESC LIMIT 1").fetchone()
        if row is None or row[0] != self.boot:
            self.db.execute("INSERT INTO events VALUES (?, 'boot', 'Sessão iniciada', ?)",
                            (time.time(), self.boot))
            self.db.commit()

    def record(self, sample):
        bucket = int(sample["ts"]//60)*60
        source = sample.get("ac")
        if source is not None and source != self.last_source:
            self.db.execute("INSERT INTO events VALUES (?, ?, ?, ?)",
                            (sample["ts"], "ac" if source else "battery",
                             "Carregador conectado" if source else "Operação na bateria", self.boot))
            self.last_source = source
        if bucket != self.last_bucket:
            items = list(sample["batteries"])
            if sample["aggregate"] and sample["aggregate"]["id"] == "__all__":
                items.append(sample["aggregate"])
            for b in items:
                self.db.execute("INSERT OR REPLACE INTO samples VALUES (?, ?, ?, ?, ?, ?, ?, ?)", (
                    bucket, b["id"], b.get("percent"), b.get("signed_power_w"), b.get("health"),
                    b.get("energy_wh"), source, b.get("status"),
                ))
            self.last_bucket = bucket
        self.db.commit()

    def trim(self, days=30, now=None):
        since = (now or time.time())-days*86400
        self.db.execute("DELETE FROM samples WHERE ts < ?", (since,))
        self.db.execute("DELETE FROM events WHERE ts < ?", (since,))
        self.db.commit()

    def query(self, battery, hours=24, now=None):
        end = now or time.time()
        start = end-hours*3600
        group = max(60, int(hours*3600/240))
        rows = self.db.execute("""
          SELECT MIN(ts), AVG(percent), AVG(power), AVG(health), MIN(ac), MAX(ac)
          FROM samples WHERE battery=? AND ts>=? AND ts<=?
          GROUP BY CAST((ts-?)/? AS INTEGER) ORDER BY MIN(ts)
        """, (battery, start, end, start, group)).fetchall()
        points = [{"ts": r[0], "percent": r[1], "power": r[2], "health": r[3],
                   "ac": r[4] if r[4] == r[5] else None} for r in rows]
        summary = self.db.execute("""
          SELECT AVG(CASE WHEN status='Discharging' AND power>0 THEN power END),
                 MAX(CASE WHEN status='Discharging' THEN power END),
                 COUNT(*) FROM samples WHERE battery=? AND ts>=? AND ts<=?
        """, (battery, start, end)).fetchone()
        events = [{"ts": r[0], "kind": r[1], "detail": r[2]} for r in self.db.execute(
            "SELECT ts, kind, detail FROM events WHERE ts>=? AND ts<=? ORDER BY ts DESC LIMIT 12",
            (start, end))]
        return {"type": "history", "battery": battery, "hours": hours,
                "from": start, "to": end, "gap": group*3, "points": points, "events": events,
                "average_w": summary[0], "peak_w": summary[1], "samples": summary[2]}

    def export(self, path, battery, hours=24):
        since = time.time()-hours*3600
        with open(path, "x", newline="", encoding="utf-8-sig") as stream:
            writer = csv.writer(stream)
            writer.writerow(["data_local", "timestamp_unix", "bateria", "carga_pct",
                             "fluxo_w_positivo_descarga", "saude_pct", "energia_wh",
                             "na_tomada", "estado"])
            for r in self.db.execute(
                "SELECT ts,battery,percent,power,health,energy,ac,status FROM samples "
                "WHERE battery=? AND ts>=? ORDER BY ts", (battery, since)
            ):
                writer.writerow([time.strftime("%Y-%m-%d %H:%M:%S%z", time.localtime(r[0])), *r])
        os.chmod(path, 0o600)
        return str(path)

    def close(self):
        self.db.close()


def diagnostics():
    tlp = shutil.which("tlp")
    stat = shutil.which("tlp-stat")
    care = parse_care("")
    config, status, version, error = {}, {}, "", ""
    _, services_raw, _ = run(["/usr/bin/systemctl", "is-active", *SERVICES], timeout=4)
    lines = services_raw.strip().splitlines()
    services = {name: lines[i] if i < len(lines) else "unknown" for i, name in enumerate(SERVICES)}
    if tlp:
        _, version, _ = run([tlp, "--version"], timeout=4)
        version = version.strip()
    if stat:
        if os.geteuid() == 0:
            code, raw, err = run([stat, "-b"], timeout=4)
            care = parse_care(raw)
            if code:
                error = (err or raw).strip()[:800]
        else:
            error = "A verificação dos recursos de carga do TLP requer autenticação."
        _, raw, _ = run([stat, "-s"], timeout=4)
        status = parse_tlp_status(raw)
        _, raw, _ = run([stat, "-c"], timeout=4)
        # Show only the relevant options, not unrelated identifiers or devices.
        config = {k: v for k, v in parse_config(raw).items() if
                  k.startswith(("START_CHARGE", "STOP_CHARGE", "CPU_BOOST", "TLP_"))}
    try:
        helper_stat = HELPER.stat()
        controls = HELPER.is_file() and helper_stat.st_uid == 0 and not helper_stat.st_mode & 0o022
    except OSError:
        controls = False
    info = {
        "installed": bool(tlp and stat), "version": version,
        "supports_saver": version_tuple(version) >= (1, 9, 0),
        "supports_policy": version_tuple(version) >= (1, 10, 0),
        "controls": controls and bool(shutil.which("pkexec")),
        "services": services, "conflicts": [k for k in SERVICES[2:] if services[k] == "active"],
        "config": config, "read_error": error, **status,
        "managed": Path("/etc/tlp.d/99-battery-studio.conf").exists(),
    }
    return {"tlp": info, "care": care}


def enrich(sample, diag):
    sample.update(diag)
    for b in sample["batteries"]:
        b["limits"] = limits_for(diag["care"], b["id"], len(sample["batteries"]))
    if sample["aggregate"] and len(sample["batteries"]) == 1:
        sample["aggregate"]["limits"] = sample["batteries"][0]["limits"]
    sample["type"] = "sample"
    return sample


def downloads_dir():
    code, value, _ = run(["xdg-user-dir", "DOWNLOAD"], timeout=3)
    path = Path(value.strip()) if code == 0 and value.strip().startswith("/") else Path.home()/"Downloads"
    path.mkdir(parents=True, exist_ok=True)
    return path


def unique_download(stem, suffix):
    folder = downloads_dir()
    name = time.strftime("%Y%m%d-%H%M%S")
    for index in range(100):
        path = folder/(stem+"-"+name+("-"+str(index) if index else "")+suffix)
        if not path.exists():
            return path
    raise ValueError("Não foi possível escolher um nome para a exportação.")


def action(request):
    op, args = request.get("op"), request.get("args", [])
    if op not in OPERATIONS or not isinstance(args, list) or len(args) != OPERATIONS[op]:
        raise ValueError("Ação inválida.")
    if any(isinstance(v, (dict, list, bool)) or len(str(v)) > 100 for v in args):
        raise ValueError("Argumentos inválidos.")
    if not HELPER.is_file():
        raise ValueError("Instale os controles com: bash install.sh --with-controls")
    if not shutil.which("pkexec"):
        raise ValueError("pkexec não encontrado. Instale o pacote polkit.")
    code, out, err = run(["pkexec", str(HELPER), op, *[str(v) for v in args]], timeout=180)
    try:
        result = json.loads(out.strip())
    except json.JSONDecodeError:
        raise ValueError("Autenticação cancelada ou comando indisponível. "+err.strip()[:600])
    if not isinstance(result, dict):
        raise ValueError("Resposta inválida do controle.")
    result["ok"] = code == 0 and result.get("ok") is True
    # Successful privileged inspection is useful when tlp-stat restricts reads.
    if result.get("care") or result.get("tlp"):
        version = (result.get("tlp") or {}).get("version")
        if not version and shutil.which("tlp"):
            version = run([shutil.which("tlp"), "--version"])[1].strip()
        cache = {"care": result.get("care"), "tlp": result.get("tlp"), "ts": time.time(),
                 "fingerprint": machine_fingerprint(version or "")}
        try:
            previous = json.loads((state_dir()/"inspection.json").read_text())
            if previous.get("fingerprint") == cache["fingerprint"]:
                cache["care"] = cache["care"] or previous.get("care")
                cache["tlp"] = cache["tlp"] or previous.get("tlp")
        except (OSError, ValueError, TypeError, AttributeError):
            pass
        target = state_dir()/"inspection.json"
        target.write_text(json.dumps(cache), encoding="utf-8")
        os.chmod(target, 0o600)
    return result


def machine_fingerprint(version):
    return {"kernel": platform.release(), "tlp": version,
            "batteries": [[p.name, read(p/"manufacturer"), read(p/"model_name")] for p in battery_dirs()]}


def cached_diagnostics():
    data = diagnostics()
    try:
        cache = json.loads((state_dir()/"inspection.json").read_text())
        valid = cache.get("fingerprint") == machine_fingerprint(data["tlp"].get("version", ""))
        if valid or (not cache.get("fingerprint") and time.time()-cache["ts"] < 86400):
            if not data["care"]["supported"] and cache.get("care"):
                data["care"] = cache["care"]
            if cache.get("tlp"):
                for key in ("config", "profile", "mode", "state", "source"):
                    if not data["tlp"].get(key) and cache["tlp"].get(key):
                        data["tlp"][key] = cache["tlp"][key]
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return data


def preferences():
    try:
        raw = json.loads((state_dir()/"preferences.json").read_text())
        days = raw.get("retention_days")
        if days in (7, 30, 90):
            return {"retention_days": days}
    except (OSError, ValueError, TypeError, AttributeError):
        pass
    return {"retention_days": 30}


def monitor():
    os.umask(0o077)
    history = None
    history_error = ""
    try:
        history = History()
    except (OSError, sqlite3.Error) as error:
        history_error = "Histórico indisponível: "+str(error)
    selected = selectors.DefaultSelector()
    selected.register(sys.stdin, selectors.EVENT_READ)
    buffer = b""
    visible = False
    last_emit, last_diag, last_trim = 0.0, 0.0, 0.0
    diag = {"tlp": {}, "care": parse_care("")}
    settings = preferences()
    latest = None
    try:
        while True:
            now = time.monotonic()
            if now-last_diag >= (30 if visible else 120):
                diag = cached_diagnostics()
                last_diag = now
            if now-last_emit >= (3 if visible else 15):
                latest = enrich(snapshot(), diag)
                latest["retention_days"] = settings["retention_days"]
                latest["history_error"] = history_error
                if history:
                    try:
                        history.record(latest)
                        if now-last_trim >= 3600:
                            history.trim(settings["retention_days"])
                            last_trim = now
                    except sqlite3.Error as error:
                        latest["history_error"] = "Falha ao salvar o histórico: "+str(error)
                emit(latest)
                last_emit = now
            events = selected.select(timeout=0.5)
            if not events:
                continue
            chunk = os.read(sys.stdin.fileno(), 65536)
            if not chunk:
                break
            buffer += chunk
            if len(buffer) > 131072:
                buffer = b""
                emit({"type": "error", "message": "Solicitação grande demais."})
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                try:
                    request = json.loads(line)
                    op = request.get("op")
                    if op == "visible":
                        visible = request.get("value") is True
                        last_emit = 0
                    elif op == "refresh":
                        last_diag = last_emit = 0
                    elif op == "history":
                        if not history:
                            raise ValueError(history_error)
                        hours = request.get("hours", 24)
                        battery = request.get("battery")
                        if hours not in (1, 6, 24, 168, 720, 2160) or not isinstance(battery, str):
                            raise ValueError("Filtro de histórico inválido.")
                        emit(history.query(battery, hours))
                    elif op == "retention":
                        days = request.get("days")
                        if days not in (7, 30, 90):
                            raise ValueError("Retenção inválida.")
                        settings = {"retention_days": days}
                        (state_dir()/"preferences.json").write_text(json.dumps(settings))
                        if history:
                            history.trim(days)
                        last_emit = 0
                        emit({"type": "result", "ok": True, "message": "Retenção do histórico salva."})
                    else:
                        raise ValueError("Solicitação desconhecida.")
                except Exception as error:
                    emit({"type": "error", "message": str(error)})
    finally:
        selected.close()
        if history:
            history.close()


def report():
    data = enrich(snapshot(), cached_diagnostics())
    target = unique_download("Battery-Studio-diagnostico", ".txt")
    text = "BATTERY STUDIO 1.0.0 · DIAGNÓSTICO\n"+time.strftime("%Y-%m-%d %H:%M:%S %Z")+"\n\n"
    text += "Potência: fluxo da bateria; não é o consumo total da tomada.\n"
    text += "Não inclui número de série nem uma lista de dispositivos de rede.\n\n"
    text += json.dumps(data, ensure_ascii=False, indent=2)
    with open(target, "x", encoding="utf-8") as stream:
        stream.write(text)
    os.chmod(target, 0o600)
    return {"ok": True, "message": "Diagnóstico salvo em "+str(target), "path": str(target)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("monitor", "snapshot", "action", "export", "report"))
    parser.add_argument("parameters", nargs="?", default="{}")
    args = parser.parse_args()
    try:
        if args.command == "monitor":
            monitor()
            return 0
        if args.command == "snapshot":
            result = enrich(snapshot(), cached_diagnostics())
        elif args.command == "action":
            if len(args.parameters) > 16384:
                raise ValueError("Solicitação grande demais.")
            result = action(json.loads(args.parameters))
        elif args.command == "report":
            result = report()
        else:
            req = json.loads(args.parameters)
            if req.get("hours", 24) not in (1, 6, 24, 168, 720, 2160) or not isinstance(req.get("battery"), str):
                raise ValueError("Filtro de exportação inválido.")
            history = History()
            try:
                path = history.export(unique_download("Battery-Studio-historico", ".csv"),
                                      req["battery"], req.get("hours", 24))
            finally:
                history.close()
            result = {"ok": True, "message": "CSV salvo em "+path, "path": path}
        emit(result)
        return 0 if result.get("ok", True) else 1
    except Exception as error:
        emit({"ok": False, "message": str(error)})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
