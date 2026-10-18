# Security and permissions

PowerKit runs with the current user's permissions inside Omarchy's unsandboxed plugin environment. Its Rust process reads sysfs and invokes installed local tools without evaluating shell input.

- Monitoring requires no root privileges. Network access is not used by the Rust backend, and no telemetry is collected.
- Threshold and persistence changes invoke fixed `/usr/bin/pkexec /usr/bin/batctl` commands with validated operations, presets and numeric arguments.
- Charge-behaviour changes validate the selected entry in `/sys/class/power_supply`, verify its type and supported modes, then invoke fixed `/usr/bin/pkexec /usr/bin/tee` with the exact sysfs attribute path. A mode from a three-value allowlist is sent over stdin; readback is checked. No general-purpose privileged helper, password storage or custom polkit rule is installed.
- CPU governor/EPP changes enumerate real `policyN` entries under `/sys/devices/system/cpu/cpufreq`, validate a fixed operation and allowlisted value against every policy's advertised options, reject incompatible Intel Performance/EPP settings, and use one fixed pkexec/tee command with only those discovered attribute paths. Values are read back; partial application is reported on errors. They are live overrides and are neither persisted nor periodically enforced.
- Power-profile changes use Omarchy's existing `omarchy-powerprofiles-set` bridge and daemon permissions.
- First-use preparation opens a visible terminal and requires explicit confirmation before installing missing packages through `omarchy pkg add` / `omarchy pkg aur add` or enabling power-profiles-daemon with sudo. AUR build scripts run as the user. Active competing power managers block automatic service activation. Cancellation/failure is remembered to avoid repeated prompts. No battery limits or profiles are changed during preparation.
- The source launcher builds Rust dependencies using Cargo on first use or after a source change, then caches the binary under the user's XDG cache directory. Compilation can access the configured Cargo registry. The runtime does not download executables or elevate the build.
- Preference files use mode 0600. No external power-management configuration is edited automatically. `install.sh --migrate` explicitly authorizes a backed-up replacement of the legacy widget ID in shell.json; the ordinary native installation never runs that script.
- Native removal does not change hardware thresholds, charge behaviour, services or profiles. State/cache files are retained; users may remove the documented directories separately.

To report a vulnerability, contact the repository maintainer through GitHub's private vulnerability reporting if enabled, or open an issue requesting a private contact channel without disclosing exploit details.
