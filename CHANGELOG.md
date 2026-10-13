# Changelog

## 0.1.0 (unreleased)

First public release.

- Root daemon sampling CPU, memory, swap, disk, battery, thermal state and top processes.
- Self-contained HTML report with SVG charts, hover tooltips, dark mode, CSV export.
- Rule-based findings (saturation streaks, memory pressure, disk, battery health, panics…).
- Delivery to a local folder and to any HTTPS webhook, HMAC-signed, with an offline outbox.
- Ready-made receivers: Google Drive (Apps Script), Python reference server; Power Automate recipe.
- Menu bar agent: visible notice, end date, "open the report IT receives".
- Time-boxed sessions with automatic uninstall; `macvitals` CLI for admins.
- Configuration via MDM managed preferences or root-only `config.json`; nothing secret in the package.
- Universal (arm64 + x86_64) installer package; optional Developer ID signing and notarization.
