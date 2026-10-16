#!/usr/bin/env bash
set -euo pipefail
[[ $EUID != 0 ]] || { echo 'Run as your normal user.' >&2; exit 1; }
[[ $# == 0 ]] || { echo 'Usage: bash uninstall.sh' >&2; exit 2; }
plugin_id=io.github.sabb4th.powerkit
target=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$plugin_id
state=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-powerkit
[[ ! -L $target ]] || { echo "Symlink destination: $target" >&2; exit 1; }
omarchy plugin disable "$plugin_id"
if [[ -d $target ]]; then
  mkdir -p -- "$state/backups"
  mv -- "$target" "$state/backups/$plugin_id-uninstalled-$(date +%Y%m%d-%H%M%S)-$$"
fi
omarchy-shell shell rescanPlugins
printf 'Plugin disabled and archived. Battery settings and power profiles are preserved.\n'
