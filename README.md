# Battery Studio · Omarchy

A native-looking battery panel for the Omarchy Quickshell desktop, with a **Rust backend**, [batctl](https://github.com/Ooooze/batctl) charge thresholds and power-profiles-daemon profiles. The interface is entirely in English.

The bar keeps its battery artwork, charging indicator, seven display formats and mouse shortcuts: **left-click** opens the panel, **right-click** changes the display format, and **middle-click** refreshes. Appearance is configured only from the bar; there is no Settings section.

![Compact power panel with simulated readings](previews/power-panel-v2.png)

## Panel

Inspired by [Omarchy's power panel](https://github.com/omacom/omarchy/tree/246f33a2fef66411c990860d88e0823ae83987fc/shell/plugins/panels/power): large percentage, charge gauge with a limit marker, compact two-column statistics and horizontal profile buttons.

- **Battery:** health, cycles, current full capacity, design capacity, estimated runtime or time to the charge limit, and charging/discharging power. Temperature and voltage appear when temperature telemetry exists. Missing readings display `—`.
- **Power profile:** the profiles actually advertised by the daemon. Uses the stock `omarchy-powerprofiles-set` bridge to remember the current source's profile.
- **Charge behaviour:** **Auto**, **Inhibit charge** and **Force discharge**, restricted to modes advertised by the selected battery's kernel driver. The current mode is highlighted, with a short explanation of its effect.
- **Charge limits:** expand to show four batctl presets, custom start/stop limits, boot/resume persistence and saved-limit restoration. These controls stay collapsed by default.

**Charge behaviour applies to the selected battery. Thresholds apply to all batteries through batctl.** Auto follows the hardware's normal charging policy and thresholds. Inhibit charge pauses charging; AC power routing depends on hardware. Force discharge uses the battery even on AC power; switch back to Auto to stop it. Behaviour changes are live and are not saved or replayed by the plugin. Persistence covers charge thresholds only.

The installed batctl CLI can read charge behaviour but has no setter. The plugin therefore writes the same standard `charge_behaviour` sysfs attribute used by batctl's backend, using `/usr/bin/pkexec /usr/bin/tee` with a validated power-supply entry and allowlisted mode passed over stdin. No shell or custom privileged helper is used. Only modes advertised by the real kernel attribute can be selected.

## Install

Requires Omarchy's Quickshell plugin API, Rust/Cargo for compilation, Ooooze's `batctl-tui` (`/usr/bin/batctl`), configured power-profiles-daemon, `jq`, `/usr/bin/tee`, polkit and a graphical authentication agent. Development checks also need Rust's `clippy` and `rustfmt` components and Node.js or Deno.

```bash
bash check.sh
bash install.sh
# Alternatively, install an already-built binary:
bash install.sh --prebuilt target/release/battery-studio
```

The installer does not install packages or change power-management services. It installs runtime files under `~/.config/omarchy/plugins/local.battery-studio`, archives the previous version under the XDG state directory and preserves an enabled widget's position. The plugin ID and display-format preference remain unchanged; old language preferences are ignored.

Charge actions use system authentication. When persistence is active, changing thresholds also saves their new values using `batctl persist enable`. If this second step fails, the panel reports that live limits were applied but saving failed.

```bash
bash uninstall.sh
```

Uninstall disables and archives the plugin without changing battery settings, batctl services, power profiles or saved state. Legacy installation flags `--with-controls` and `--monitor-only` remain accepted; installs use standard system authentication. Version 1's TLP controls and charts are no longer used. Their existing system files and historical data are untouched.

## Development

```bash
cargo test --locked
cargo clippy --locked --all-targets -- -D warnings
cargo fmt --check
cargo build --release --locked
./target/release/battery-studio sample
```

The backend has no Python runtime dependency. QML is the shell's frontend format; the daemon's own `powerprofilesctl` may internally use Python. Monitoring exchanges JSON lines, refreshes every 5 seconds while open and every 30 seconds otherwise, and exits on stdin EOF. Display preferences use atomic writes to `$XDG_STATE_HOME/omarchy-battery-studio/preferences.json`.

Battery metrics and supported charge behaviours come from sysfs; batctl's text output supplies threshold capabilities and current limits. `previews/power-panel-v2.png` shows the current panel with simulated data; other images under `previews/` show version 1. See [VALIDACAO.md](VALIDACAO.md) for verification and limitations.
