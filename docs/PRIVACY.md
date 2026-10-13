# Privacy

MacVitals monitors a **machine's** health, not a person's activity. It is designed so the
monitored user can see and verify everything that leaves their Mac.

## What is collected (every 5 minutes by default)

| Data | Source | Why |
|---|---|---|
| Whole-machine CPU usage and load average | `host_statistics`, `getloadavg` | Detect saturation |
| Memory used, compressed, swap, memory pressure | `host_statistics64`, `sysctl` | Detect lack of RAM |
| Free disk space on the Data volume | `statfs` | Detect full disks |
| Battery charge, health, cycle count, temperature, power source | IOKit `AppleSmartBattery` | Detect worn batteries |
| Thermal state | `ProcessInfo.thermalState` | Detect throttling |
| Names of the busiest processes with their CPU and memory (optional) | `ps` | Find the cause of slowness |
| Kernel panic report file names and dates | `/Library/Logs/DiagnosticReports` | Detect system crashes |
| Computer name, logged-in user name, model, chip, macOS version | `sysctl`, SystemConfiguration | Identify the report |

Set `"collectProcessNames": false` to drop process names entirely.

## What is never collected

File names or contents, window titles, URLs or browsing history, keystrokes, screenshots,
messages, location, or the contents of the panic reports themselves.

## Transparency built in

- A menu bar icon is shown while monitoring is active, with the end date and the organization.
- A one-time notice explains what is collected (`showNotice`).
- **"Open the report IT receives"** opens a local copy of exactly the latest report sent.
- Monitoring ends automatically after `monitoringDays` and the tool uninstalls itself (`autoUninstall`).

## Your responsibilities as an operator

Depending on your jurisdiction (e.g. GDPR in the EU), monitoring company devices may require
informing employees, a legitimate purpose, and data-retention rules. Keep the notice on, keep
sessions short and purposeful, and delete reports when the ticket is resolved.
