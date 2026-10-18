#!/usr/bin/env bash
# Shared preparation for native plugin installs and the optional installer.
set -euo pipefail
[[ $EUID != 0 ]] || { echo 'Run PowerKit setup as your normal user.' >&2; exit 1; }
runtime=false
check=false
for option in "$@"; do
  case "$option" in --runtime) runtime=true;; --check) check=true;; *) exit 2;; esac
done
packages=()
for entry in 'cargo:rust' 'cc:gcc' 'powerprofilesctl:power-profiles-daemon' 'pkexec:polkit' 'jq:jq' 'tee:coreutils'; do
  if [[ $runtime == true && ( $entry == cargo:* || $entry == cc:* ) ]]; then continue; fi
  command -v "${entry%%:*}" >/dev/null || packages+=("${entry#*:}")
done
batctl_missing=false
# Reject Arch's unrelated mesh-networking package, which has the same executable name.
pacman -Q batctl-tui >/dev/null 2>&1 && [[ -x /usr/bin/batctl ]] || batctl_missing=true
service_missing=false
systemctl is-active --quiet power-profiles-daemon.service || service_missing=true
if [[ $check == true ]]; then
  [[ ${#packages[@]} == 0 && $batctl_missing == false && $service_missing == false ]]
  exit
fi
if [[ ${#packages[@]} == 0 && $batctl_missing == false && $service_missing == false ]]; then exit 0; fi
printf 'PowerKit — first-run preparation\n\n'
printf 'Install missing dependencies using Omarchy, build the Rust backend as your user,\nand enable power-profiles-daemon if needed. Your battery limits will not change.\n\n'
((${#packages[@]} == 0)) || printf 'Arch packages: %s\n' "${packages[*]}"
[[ $batctl_missing == false ]] || printf 'AUR package: batctl-tui (Ooooze/batctl); build tools if missing.\n'
[[ $service_missing == false ]] || printf 'Service: enable and start power-profiles-daemon.\n'
read -r -p 'Continue? [y/N] ' answer
[[ $answer == y || $answer == Y || $answer == yes ]] || exit 2
if [[ $service_missing == true ]]; then
  for service in tlp.service auto-cpufreq.service tuned.service; do
    if systemctl is-active --quiet "$service"; then
      printf 'PowerKit: %s is active. Choose your power manager before retrying setup.\n' "$service" >&2
      exit 1
    fi
  done
fi
((${#packages[@]} == 0)) || omarchy pkg add "${packages[@]}"
if [[ $batctl_missing == true ]]; then
  omarchy pkg add base-devel git
  omarchy pkg aur add batctl-tui
fi
[[ $service_missing == false ]] || sudo systemctl enable --now power-profiles-daemon.service
if [[ $runtime == true ]]; then
  bash "${BASH_SOURCE[0]}" --runtime --check
else
  bash "${BASH_SOURCE[0]}" --check
fi
printf '\nPowerKit is ready. You can close this window.\n'
