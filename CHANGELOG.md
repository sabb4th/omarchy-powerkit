# Changelog

## 3.1.0

- Corrected the project author and copyright attribution to Elias Sabat.

- Replaced Capacity/Design with full-width CPU governor and energy-preference controls, including active/mixed values and hardware-advertised choices.
- Added validated, authenticated CPU changes across active policies, Intel Performance/EPP handling and readback verification.
- Removed hover tooltips; improved control-label contrast and spacing.
- Added smooth level, charging-bolt, text, width and hover/open transitions with compact charging-only space and no idle animation loop.

## 3.0.0 · PowerKit

- Renamed the project/repository to PowerKit / omarchy-powerkit and adopted io.github.sabb4th.powerkit as the permanent marketplace ID.
- Moved the solid charging bolt to the left of the battery while preserving the battery fill.
- Added a source launcher for native Omarchy install/update, cached Rust builds, checksummed release packages and CI/release workflows.
- Added explicit, backed-up migration from local.battery-studio and fallback reading of legacy display preferences.
- Added root preview, security documentation and marketplace submission metadata.

## 2.1.0

- Added hardware-advertised Auto, Inhibit charge and Force discharge controls for the selected battery.
- Use the same kernel charge_behaviour interface as batctl, with validated arguments and standard system authentication.
- Rebuilt the panel around Omarchy's native power layout: prominent percentage, charge gauge, two-column metrics and horizontal profiles.
- Removed Settings and localization; the interface is English and bar appearance changes only through right-click.
- Added design capacity, optional temperature/voltage and time to the actual charge limit.
- Collapsed charge presets and custom limits into an expandable section.

## 2.0.0

- Replaced the Python/TLP collector and privileged helper with a Rust JSON-lines backend.
- Added batctl presets, hardware-aware thresholds and boot/resume persistence controls.
- Added power-profiles-daemon profiles through Omarchy's standard source-aware bridge.
- Rebuilt the panel as Energy, Charge and Settings using Omarchy's UI components.
- Preserved bar artwork, charging indicators, seven formats, mouse shortcuts and plugin ID.
- Replaced Python setup with shell installation and locked Cargo release builds.
- Removed TLP controls and version 1 charts/exports; old state remains untouched.
