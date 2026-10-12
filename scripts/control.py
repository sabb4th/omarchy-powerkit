#!/usr/bin/python3 -I
"""Root-owned, polkit-authenticated TLP control helper. No arbitrary commands."""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import sys
import tempfile

# In the installed helper this directory is root-owned and mode 0755.
# Isolated Python ignores PYTHONPATH, user site packages and user startup code.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from domain import (
    PROFILES, SYS, battery_dirs, battery_info, limits_for, parse_care,
    parse_config, parse_tlp_status, run, validate_value, version_tuple,
)

TLP = "/usr/bin/tlp"
STAT = "/usr/bin/tlp-stat"
SYSTEMCTL = "/usr/bin/systemctl"
DROPIN = Path("/etc/tlp.d/99-battery-studio.conf")
ORIGINAL = Path("/var/lib/omarchy-battery-studio/original.json")
LOCK = Path("/run/omarchy-battery-studio.lock")
KEYS = {
    "TLP_AUTO_SWITCH", "TLP_PROFILE_AC", "TLP_PROFILE_BAT",
    "CPU_BOOST_ON_AC", "CPU_BOOST_ON_BAT", "CPU_BOOST_ON_SAV",
    "START_CHARGE_THRESH_BAT0", "STOP_CHARGE_THRESH_BAT0",
    "START_CHARGE_THRESH_BAT1", "STOP_CHARGE_THRESH_BAT1",
}
CONFLICTS = ["power-profiles-daemon.service", "auto-cpufreq.service",
             "tuned.service", "tuned-ppd.service"]


def checked(argv, timeout=12):
    code, out, err = run(argv, timeout)
    if code:
        raise ValueError((err or out or "Falha no comando: "+argv[0]).strip()[:2400])
    return out


def installed():
    if not Path(TLP).is_file() or not Path(STAT).is_file():
        raise ValueError("TLP não instalado. Veja os comandos de instalação no README.")


def conflict_services():
    return [name for name in CONFLICTS if run([SYSTEMCTL, "is-active", name])[1].strip() == "active"]


def require_ready():
    installed()
    conflicts = conflict_services()
    if conflicts:
        raise ValueError("Outro gerenciador está ativo: "+", ".join(conflicts)+
                         ". Desative-o antes de controlar o TLP.")
    status = parse_tlp_status(checked([STAT, "-s"]))
    if status.get("state") == "disabled":
        raise ValueError("TLP_ENABLE=0. Ative o TLP na sua configuração antes de alterar os controles.")
    return status


def atomic_write(path, content, mode=0o644):
    if path.is_symlink():
        raise ValueError("O arquivo de configuração não pode ser um link simbólico.")
    path.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    handle, name = tempfile.mkstemp(prefix="."+path.name+".", dir=path.parent)
    try:
        os.fchmod(handle, mode)
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def remember_original():
    if ORIGINAL.exists():
        return
    ORIGINAL.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    saved = {p.name: {"start": battery_info(p)["start"], "stop": battery_info(p)["stop"]}
             for p in battery_dirs()}
    atomic_write(ORIGINAL, json.dumps(saved), 0o600)


def owned_config():
    if DROPIN.is_symlink():
        raise ValueError("O arquivo de configuração não pode ser um link simbólico.")
    data = parse_config(DROPIN.read_text()) if DROPIN.exists() else {}
    if set(data) - KEYS:
        raise ValueError("O arquivo gerenciado contém opções externas. Mova-as para outro arquivo do TLP.")
    return data


def rollback_file(old):
    if old is None:
        DROPIN.unlink(missing_ok=True)
    else:
        atomic_write(DROPIN, old)


def persistent(changes, apply, restore=None):
    """Check TLP's real precedence before changing hardware; roll back on errors."""
    if set(changes) - KEYS:
        raise ValueError("Opção de configuração não autorizada.")
    old = DROPIN.read_text() if DROPIN.exists() and not DROPIN.is_symlink() else None
    data = owned_config()
    data.update({k: str(v) for k, v in changes.items()})
    if any(not v.replace("-", "").isalnum() for v in data.values()):
        raise ValueError("Valor de configuração inválido.")
    remember_original()
    content = "# Gerenciado pelo Battery Studio. /etc/tlp.conf tem precedência.\n"
    content += "\n".join(k+'="'+data[k]+'"' for k in sorted(data))+"\n"
    atomic_write(DROPIN, content)
    touched = False
    try:
        effective = parse_config(checked([STAT, "-c"]))
        mismatch = [k for k, v in changes.items() if effective.get(k) != str(v)]
        if mismatch:
            raise ValueError("Uma configuração externa tem precedência sobre: "+", ".join(mismatch)+
                             ". Revise /etc/tlp.conf ou os outros arquivos de /etc/tlp.d. Nada foi aplicado.")
        touched = True
        apply()
    except Exception:
        rollback_file(old)
        if touched and restore:
            try:
                restore()
            except Exception:
                pass
        raise


def care_for(name):
    batteries = battery_dirs()
    found = next((p for p in batteries if p.name == name), None)
    if found is None:
        raise ValueError("Bateria ausente ou nome inválido.")
    care = parse_care(checked([STAT, "-b"]))
    limits = limits_for(care, name, len(batteries))
    if not limits["supported"]:
        raise ValueError("O TLP não confirmou suporte a limites de carga para esta bateria.")
    return found, care, limits


def verify_thresholds(path, start, stop, limits):
    actual = battery_info(path)
    bad = []
    if actual["stop"] is not None and not limits["fixed"] and actual["stop"] != stop:
        bad.append("limite máximo")
    if actual["start"] is not None and limits["start_supported"] and actual["start"] != start:
        bad.append("limite de início")
    if bad:
        raise ValueError("O firmware não aplicou "+", ".join(bad)+". O ajuste foi revertido.")


def threshold(name, start, stop, permanent):
    require_ready()
    path, care, limits = care_for(name)
    start_spec = limits.get("start", {"min": 0, "max": 0, "values": [0], "raw": "0"})
    validate_value(start, start_spec, "Início de carga")
    validate_value(stop, limits["stop"], "Limite de carga")
    if limits["start_supported"] and start >= stop:
        raise ValueError("O início da carga deve ser menor que o limite máximo.")
    if care["plugin"] == "dell" and start > stop-5:
        raise ValueError("A Dell exige uma diferença mínima de 5 pontos entre início e fim.")
    previous = battery_info(path)
    def apply():
        checked([TLP, "setcharge", str(start), str(stop), name])
        verify_thresholds(path, start, stop, limits)
    def restore():
        old_start = previous["start"] if limits["start_supported"] else 0
        old_stop = previous["stop"]
        if old_start is not None and old_stop is not None and not limits["fixed"]:
            checked([TLP, "setcharge", str(int(old_start)), str(int(old_stop)), name])
        else:
            checked([TLP, "setcharge", name])
    if permanent:
        slot = limits["slot"]
        persistent({
            "START_CHARGE_THRESH_BAT"+slot: start,
            "STOP_CHARGE_THRESH_BAT"+slot: stop,
        }, apply, restore)
    else:
        try:
            apply()
        except Exception:
            restore()
            raise
    return {"message": "Proteção de carga aplicada"+(" e salva para reiniciar." if permanent else " nesta sessão."),
            "care": care}


def unlimit(name, permanent):
    require_ready()
    path, care, limits = care_for(name)
    start = limits.get("start", {}).get("default", 0)
    stop = limits["stop"]["default"]
    if limits["fixed"]:
        start, stop = 0, 0
    result = threshold(name, start, stop, permanent)
    result["message"] = "Limite de carga desativado"+(" de forma permanente." if permanent else " nesta sessão.")
    return result


def inspect():
    installed()
    raw_battery = checked([STAT, "-b"])
    return {
        "message": "Recursos do TLP verificados.",
        "care": parse_care(raw_battery),
        "tlp": {**parse_tlp_status(checked([STAT, "-s"])),
                "config": parse_config(checked([STAT, "-c"])),
                "version": checked([TLP, "--version"]).strip()},
    }


def dispatch(args):
    if not args:
        raise ValueError("Informe uma operação.")
    op, rest = args[0], args[1:]
    if op == "inspect" and not rest:
        return inspect()
    if op == "profile" and len(rest) == 1:
        name = rest[0]
        require_ready()
        version = version_tuple(checked([TLP, "--version"]))
        mapping = {"auto": "start", "performance": "ac", "balanced": "bat", "power-saver": "power-saver"}
        if name not in mapping:
            raise ValueError("Perfil desconhecido.")
        if name == "power-saver" and version < (1, 9, 0):
            raise ValueError("Economia de energia exige TLP 1.9 ou mais recente.")
        checked([TLP, mapping[name]])
        return {"message": "Perfil aplicado: "+name+".", "tlp": inspect()["tlp"]}
    if op == "threshold" and len(rest) == 4:
        name, first, last, persist = rest
        if persist not in ("0", "1") or not first.isdigit() or not last.isdigit():
            raise ValueError("Valores de limite inválidos.")
        return threshold(name, int(first), int(last), persist == "1")
    if op == "unlimit" and len(rest) == 2 and rest[1] in ("0", "1"):
        return unlimit(rest[0], rest[1] == "1")
    if op in ("fullcharge", "chargeonce", "restore-charge") and len(rest) == 1:
        require_ready()
        path, care, limits = care_for(rest[0])
        if op == "chargeonce" and not care["chargeonce"]:
            raise ValueError("Este hardware não oferece carga única até o limite.")
        command = "setcharge" if op == "restore-charge" else op
        checked([TLP, command, path.name])
        messages = {
            "fullcharge": "Carga até 100% liberada uma vez. O limite salvo continua no TLP.",
            "chargeonce": "Carga única liberada até o limite configurado.",
            "restore-charge": "Limites configurados no TLP restaurados.",
        }
        return {"message": messages[op]}
    if op == "auto-policy" and len(rest) == 3:
        require_ready()
        ac, bat, switching = rest
        if ac not in PROFILES or bat not in PROFILES or switching not in ("1", "2"):
            raise ValueError("Política de alternância inválida.")
        if version_tuple(checked([TLP, "--version"])) < (1, 10, 0):
            raise ValueError("Perfis automáticos personalizados exigem TLP 1.10 ou mais recente.")
        persistent({"TLP_PROFILE_AC": PROFILES[ac], "TLP_PROFILE_BAT": PROFILES[bat],
                    "TLP_AUTO_SWITCH": switching}, lambda: checked([TLP, "start"]),
                   lambda: checked([TLP, "start"]))
        return {"message": "Alternância automática salva e aplicada.", "tlp": inspect()["tlp"]}
    if op == "cpu-boost" and len(rest) == 2:
        status = require_ready()
        name, enabled = rest
        if name not in PROFILES or enabled not in ("0", "1"):
            raise ValueError("Ajuste de turbo inválido.")
        if name == "power-saver" and version_tuple(checked([TLP, "--version"])) < (1, 9, 0):
            raise ValueError("Este TLP não oferece o perfil Economia.")
        if not any(p.exists() for p in [
            SYS/"devices/system/cpu/intel_pstate/no_turbo",
            SYS/"devices/system/cpu/cpufreq/boost",
        ]):
            raise ValueError("Este driver não expõe controle de turbo compatível.")
        suffix = {"performance": "AC", "balanced": "BAT", "power-saver": "SAV"}[name]
        command = status["profile"] if status["profile"] and not status["manual"] else (
            "ac" if status["profile"] == "performance" else "bat" if status["profile"] == "balanced" else "power-saver")
        if version_tuple(checked([TLP, "--version"])) < (1, 9, 0):
            command = "ac" if status["profile"] == "performance" else "bat"
        persistent({"CPU_BOOST_ON_"+suffix: enabled},
                   lambda: checked([TLP, command]),
                   lambda: checked([TLP, command]))
        return {"message": "Turbo "+("ativado" if enabled == "1" else "desativado")+" no perfil escolhido."}
    if op == "enable-tlp" and not rest:
        require_ready()
        checked([SYSTEMCTL, "enable", "--now", "tlp.service"])
        return {"message": "Serviço TLP habilitado."}
    if op == "reset" and not rest:
        require_ready()
        if DROPIN.is_symlink():
            raise ValueError("Configuração gerenciada inválida.")
        old = DROPIN.read_text() if DROPIN.exists() else None
        saved = json.loads(ORIGINAL.read_text()) if ORIGINAL.exists() else {}
        DROPIN.unlink(missing_ok=True)
        try:
            checked([TLP, "start"])
            effective = parse_config(checked([STAT, "-c"]))
            care = parse_care(checked([STAT, "-b"]))
            paths = battery_dirs()
            for p in paths:
                limits = limits_for(care, p.name, len(paths))
                if not limits["supported"]:
                    continue
                slot = limits["slot"]
                if "STOP_CHARGE_THRESH_BAT"+slot in effective:
                    checked([TLP, "setcharge", p.name])
                elif saved.get(p.name, {}).get("stop") is not None and not limits["fixed"]:
                    start = saved[p.name]["start"] if limits["start_supported"] else 0
                    if start is not None:
                        checked([TLP, "setcharge", str(int(start)), str(int(saved[p.name]["stop"])), p.name])
                else:
                    checked([TLP, "fullcharge", p.name])
        except Exception:
            rollback_file(old)
            checked([TLP, "start"])
            raise
        ORIGINAL.unlink(missing_ok=True)
        return {"message": "Ajustes do Battery Studio removidos; configurações externas preservadas."}
    raise ValueError("Operação ou argumentos não autorizados.")


def main():
    if os.geteuid() != 0:
        print(json.dumps({"ok": False, "message": "Use a autenticação do sistema (pkexec)."}))
        return 1
    try:
        with open(LOCK, "a", encoding="utf-8") as lock:
            os.chmod(LOCK, 0o600)
            fcntl.flock(lock, fcntl.LOCK_EX)
            result = dispatch(sys.argv[1:])
        print(json.dumps({"ok": True, **result}, ensure_ascii=False))
        return 0
    except Exception as error:
        print(json.dumps({"ok": False, "message": str(error)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
