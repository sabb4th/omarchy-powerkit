# Battery Studio · TLP

**Version 1.1.0 · Omarchy Quattro (4.x)**

Native, theme-aware battery monitoring and TLP controls. The compact panel has
**Overview, Charge, Profiles, History, Battery, System, Settings and Extra charge**.
The TLP & system card keeps its original fields and organization.

[Leia em português](README.pt-BR.md)

## Install

Extract the archive and open a terminal in the omarchy-battery-studio directory.
If needed, install the official Arch packages first:

    sudo pacman -S --needed tlp tlp-pd
    sudo systemctl enable --now tlp.service tlp-pd.service

The tlp-pd package is optional for this plugin but provides the profile API used
by other desktop components. TLP conflicts with power-profiles-daemon; pacman
may ask to replace that package. Other active power managers are diagnosed,
not silently disabled by the installer.

Install the plugin and authenticated controls:

    bash install.sh --with-controls

Monitoring only, without administrator controls:

    bash install.sh --monitor-only

When upgrading from version 1.0, restart the shell after installation:

    omarchy-restart-shell

This loads the updated shared model. Existing history and TLP settings remain.
Omarchy 3.x/Waybar uses a different contract and is not supported by this package.

## Compact interface and languages

Maximum panel content size is **500 × 560 logical pixels**, reduced from
640 × 660. Height adapts to shorter tabs. The font, scale, colors and corners
follow the active Omarchy theme. Long pages scroll; advanced CPU controls expand
on request. The plugin runs inside the existing shell, not another Quickshell process.

Select English, Portuguese or Automatic in **Settings → Language**. Automatic
uses the system locale. Language and bar presentation are saved locally.

## Bar interactions

- **Left-click:** open or close the panel.
- **Right-click:** cycle display modes.
- **Middle-click:** refresh data.

| Mode | Display |
|---|---|
| Full | Battery icon, percentage and watts |
| Percentage | Icon and percentage |
| Icon | Icon only |
| Watts | Icon and battery power flow |
| Runtime | Icon and estimated runtime |
| Percentage + runtime | Icon, percentage and runtime |
| Percentage + profile | Icon, percentage and PRF/BAL/SAV |

The selected mode survives shell restarts. The battery graphic has levels from
empty to full, an unknown state and a charging indicator. Choose a mode directly
in **Settings → Bar display**. Vertical bars keep an icon-only presentation.

## Battery and TLP features

- Instantaneous battery power, runtime estimate, health, wear and cycle count.
- Start/stop charge thresholds, presets and optional persistence.
- One-time charging to 100%, restore saved limits and chargeonce on compatible hardware.
- Automatic/manual TLP profiles, custom AC/battery policy with TLP 1.10+.
- CPU boost settings per profile, where the driver supports them.
- Local charge, power and health graphs; 1h, 6h, 24h, 7d and 30d ranges.
- CSV export, power events, 7/30/90-day retention and a local diagnostic report.
- Multiple batteries, charger information, CPU/battery temperatures, driver, governor and EPP.
- Detection of active power-profiles-daemon, auto-cpufreq, tuned and tuned-ppd conflicts.

Hardware capabilities are checked by TLP before every privileged change.
Unsupported controls remain unavailable. Fixed Lenovo conservation modes are
shown as on/off controls rather than invented percentage limits.

## Understand the readings

**Watts describe battery flow, not total wall power.** Positive values in the
graph mean discharge; negative values mean charging. An idle battery may report
zero even while the computer is using power from the charger.

Runtime is estimated from current flow and may change with workload. Charging
estimates use the stop threshold. Missing sensors show a dash. Wh values derived
from Ah are labelled. Health is current full capacity divided by design capacity.
Setting a lower limit does not force a discharge.

## Persistence and permissions

Preferences/history are stored under the XDG state directory, normally:

    ~/.local/state/omarchy-battery-studio/

The plugin saves its TLP changes only in:

    /etc/tlp.d/99-battery-studio.conf

External settings in /etc/tlp.conf take precedence. Effective values are checked
before applying persistent changes; conflicts cause rollback. Original readable
thresholds are stored for reset/uninstall. The root-owned helper uses isolated
Python, an allowlist of operations and polkit authentication; no passwordless sudo
rule is installed. Viewing the panel does not request administrator credentials.

TLP charge capability inspection is cached against kernel/TLP/battery identity.
The cache is for presentation; privileged controls always recheck the hardware.
One collector is shared across monitors and stops when the last widget is disabled.
Sampling is every 3 seconds with a panel open, 15 seconds otherwise; history is
recorded once per minute. The plugin does not access the internet.

Exports go to the system downloads directory. Critical battery notifications
remain handled by Omarchy's existing battery service. Lowering retention deletes
older history records.

## Validate and remove

    bash check.sh
    bash check.sh --qml

Python tests use simulated sysfs/TLP. JavaScript tests run when Node.js is present.
The --qml option uses installed Omarchy imports. See [VALIDACAO.md](VALIDACAO.md)
for executed checks and the distinction between Qt/adaptor tests and a real session.

Remove only the widget, keeping controls/settings:

    bash uninstall.sh

Also remove the controls and restore available previous TLP settings:

    bash uninstall.sh --remove-controls

History/backups remain. TLP and tlp-pd are not uninstalled.

## Compatibility and verification limits

Requires Quickshell, QtQuick/QtQuick Controls, Python 3 and TLP. Controls also
require polkit/pkexec. Traditional profiles work with TLP 1.8; Power saver requires
1.9 and custom automatic policies require 1.10. Firmware/kernel decide charge
features. The preview screenshots use **simulated data**.

The code, Qt layouts, data flow and adapter contracts were tested. The authoring
environment does not have your laptop's battery, TLP installation or a live
Omarchy session. Firmware, authentication and installed shell integration still
need verification on the target notebook.

## References

- [Omarchy Plugins development guide](https://plugins.omarchy.org/develop.html)
- [Official shell contract](https://github.com/omacom/omarchy/blob/quattro/docs/omarchy-shell.md)
- [TLP documentation](https://linrunner.de/tlp/index.html)
- [TLP commands](https://linrunner.de/tlp/usage/tlp.html)
- [Vendor capabilities](https://linrunner.de/tlp/settings/bc-vendors.html)
- [TLP profiles and switching](https://linrunner.de/tlp/settings/operation.html)
- [Linux power supply units](https://docs.kernel.org/power/power_supply_class.html)

MIT licensed. This archive is a local-installable plugin project. It has not been
published to GitHub or the marketplace. The bar/panel adapters follow Omarchy's
MIT examples.
