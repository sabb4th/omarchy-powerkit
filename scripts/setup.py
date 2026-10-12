#!/usr/bin/env python3
"""Local installer. System changes require the explicit --with-controls option."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
sys.path.insert(0, str(Path(__file__).resolve().parent))
from backend import machine_fingerprint

ROOT = Path(__file__).resolve().parents[1]
ID = "local.battery-studio"
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home()/".config")
STATE_HOME = Path(os.environ.get("XDG_STATE_HOME") or Path.home()/".local/state")
PLUGINS = CONFIG_HOME/"omarchy/plugins"
TARGET = PLUGINS/ID
STATE = STATE_HOME/"omarchy-battery-studio"
SYSTEM = Path("/usr/local/lib/omarchy-battery-studio")
POLICY = Path("/usr/share/polkit-1/actions/local.battery-studio.policy")


def invoke(argv, capture=False, optional=False):
    result = subprocess.run([str(a) for a in argv], text=True, capture_output=capture)
    if result.returncode and not optional:
        detail = (result.stderr or result.stdout or "").strip() if capture else ""
        raise RuntimeError("Falha: "+" ".join(str(a) for a in argv)+("\n"+detail if detail else ""))
    return result


def validate():
    data = json.loads((ROOT/"manifest.json").read_text())
    if data["schemaVersion"] != 1 or data["id"] != ID:
        raise RuntimeError("Manifesto inválido.")
    if data["kinds"] != ["bar-widget"]:
        raise RuntimeError("Contrato de widget inválido.")
    for value in data["entryPoints"].values():
        path = Path(value)
        if path.is_absolute() or ".." in value or not (ROOT/path).is_file():
            raise RuntimeError("Entrada de plugin inválida: "+value)
    for p in ROOT.rglob("*"):
        if p.is_symlink():
            raise RuntimeError("Links simbólicos não são aceitos: "+str(p))
    for p in (ROOT/"scripts").glob("*.py"):
        compile(p.read_text(), str(p), "exec")
    print("Manifesto e fontes Python: válidos.", flush=True)


def need_quattro():
    if not shutil.which("omarchy") or not shutil.which("omarchy-shell"):
        raise RuntimeError("Execute no seu notebook com Omarchy Quattro (4.x), em uma sessão gráfica.")
    validator = shutil.which("omarchy-plugin-validate")
    if not validator:
        raise RuntimeError("O sistema não oferece a API Quattro de plugins. Atualize o Omarchy antes de instalar.")
    invoke([validator, ROOT])


def skip_copy(directory, names):
    return [n for n in names if n in ("__pycache__", ".git", ".pytest_cache") or n.endswith((".pyc", ".pyo"))]


def install_system():
    if not shutil.which("sudo"):
        raise RuntimeError("sudo não encontrado. Os controles precisam ser instalados pelo administrador.")
    print("Instalando os controles do TLP com autenticação do sistema…", flush=True)
    invoke(["sudo", "-v"])
    invoke(["sudo", "/usr/bin/install", "-d", "-o", "root", "-g", "root", "-m", "0755", SYSTEM])
    invoke(["sudo", "/usr/bin/install", "-o", "root", "-g", "root", "-m", "0644",
            ROOT/"scripts/domain.py", SYSTEM/"domain.py"])
    invoke(["sudo", "/usr/bin/install", "-o", "root", "-g", "root", "-m", "0755",
            ROOT/"scripts/control.py", SYSTEM/"control.py"])
    invoke(["sudo", "/usr/bin/install", "-o", "root", "-g", "root", "-m", "0644",
            ROOT/"system/local.battery-studio.policy", POLICY])
    if shutil.which("tlp") and shutil.which("tlp-stat"):
        result = invoke(["sudo", SYSTEM/"control.py", "inspect"], capture=True, optional=True)
        try:
            data = json.loads(result.stdout)
            if data.get("ok"):
                STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
                cache = {"care":data.get("care"), "tlp":data.get("tlp"), "ts":time.time(),
                         "fingerprint":machine_fingerprint((data.get("tlp") or {}).get("version", ""))}
                (STATE/"inspection.json").write_text(json.dumps(cache))
                os.chmod(STATE/"inspection.json", 0o600)
                print("Recursos de carga verificados e salvos.", flush=True)
            else:
                print("Verifique os recursos pelo painel: "+data.get("message", ""), flush=True)
        except ValueError:
            print("A verificação de recursos poderá ser feita pelo painel.", flush=True)


def install(with_controls):
    validate()
    need_quattro()
    if os.geteuid() == 0:
        raise RuntimeError("Inicie o instalador como seu usuário normal. Ele usará sudo somente nos controles.")
    if TARGET.is_symlink():
        raise RuntimeError("O destino é um link simbólico; revise-o antes de instalar.")
    if with_controls:
        install_system()
    PLUGINS.mkdir(parents=True, exist_ok=True)
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    stage = Path(tempfile.mkdtemp(prefix=".battery-studio-", dir=PLUGINS))
    backup = None
    installed_stage = False
    try:
        shutil.copytree(ROOT, stage, dirs_exist_ok=True, ignore=skip_copy)
        if TARGET.exists():
            backups = STATE/"backups"
            backups.mkdir(exist_ok=True)
            backup = backups/(ID+"-"+time.strftime("%Y%m%d-%H%M%S")+"-"+str(time.time_ns()))
            shutil.move(TARGET, backup)
        stage.rename(TARGET)
        installed_stage = True
        invoke(["omarchy-shell", "shell", "rescanPlugins"])
        invoke(["omarchy", "plugin", "enable", ID, "--section", "right"])
    except Exception:
        if installed_stage and TARGET.exists():
            shutil.rmtree(TARGET)
        if backup:
            shutil.move(backup, TARGET)
            invoke(["omarchy-shell", "shell", "rescanPlugins"], optional=True)
        raise
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    print("\nBattery Studio instalado na barra. Clique para abrir.", flush=True)
    if not with_controls:
        print("Para alterar o TLP, execute: bash install.sh --with-controls", flush=True)
    if not shutil.which("tlp"):
        print("\nInstale o TLP e depois habilite seu serviço:\n"
              "sudo pacman -S --needed tlp tlp-pd\n"
              "sudo systemctl enable --now tlp.service tlp-pd.service", flush=True)
    print("O instalador preserva os outros widgets, os temas e as configurações externas do TLP.", flush=True)


def uninstall(remove_controls):
    need_quattro()
    if os.geteuid() == 0:
        raise RuntimeError("Execute como seu usuário normal.")
    if remove_controls and (SYSTEM/"control.py").exists():
        invoke(["sudo", SYSTEM/"control.py", "reset"])
        invoke(["sudo", "/usr/bin/rm", "-f", POLICY, SYSTEM/"control.py", SYSTEM/"domain.py"])
        invoke(["sudo", "/usr/bin/rmdir", SYSTEM], optional=True)
    invoke(["omarchy", "plugin", "disable", ID], optional=True)
    if TARGET.exists():
        if TARGET.is_symlink():
            raise RuntimeError("O destino é um link simbólico; não foi removido.")
        shutil.rmtree(TARGET)
    invoke(["omarchy-shell", "shell", "rescanPlugins"])
    print("Plugin removido. Histórico e backups preservados.", flush=True)


def check(qml):
    validate()
    validator = shutil.which("omarchy-plugin-validate")
    if validator:
        invoke([validator, ROOT])
        print("Contrato Omarchy: validado pelo sistema.", flush=True)
    else:
        print("Validador Omarchy não disponível neste ambiente.", flush=True)
    invoke([sys.executable, "-B", "-m", "unittest", "discover", "-s", ROOT/"tests", "-v"])
    if qml:
        tool = shutil.which("qmllint")
        if not tool:
            raise RuntimeError("qmllint não encontrado (pacote qt6-declarative).")
        base = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))/"shell"
        if not base.exists():
            base = Path.home()/".local/share/omarchy/shell"
        if not base.exists():
            raise RuntimeError("Imports do Omarchy não encontrados. Defina OMARCHY_PATH.")
        invoke([tool, "-I", base, "--unqualified", "disable", "--unused-imports", "disable",
                *sorted(ROOT.glob("*.qml"))])


def main():
    parser = argparse.ArgumentParser(description="Battery Studio · Omarchy Quattro")
    sub = parser.add_subparsers(dest="command", required=True)
    install_parser = sub.add_parser("install")
    mode = install_parser.add_mutually_exclusive_group()
    mode.add_argument("--with-controls", action="store_true", help="instala controles autenticados do TLP")
    mode.add_argument("--monitor-only", action="store_true", help="instala apenas leitura e gráficos")
    uninstall_parser = sub.add_parser("uninstall")
    uninstall_parser.add_argument("--remove-controls", action="store_true")
    check_parser = sub.add_parser("check")
    check_parser.add_argument("--qml", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "install":
            install(args.with_controls)
        elif args.command == "uninstall":
            uninstall(args.remove_controls)
        else:
            check(args.qml)
        return 0
    except Exception as error:
        print("Battery Studio: "+str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
