# Security

## Design

- **No secrets in the installer.** The package contains only the app, two launchd plists and
  two scripts. The webhook URL and signing secret come from an MDM profile or a root-only
  (`0600`) `config.json`; the build fails if a config file ends up in the payload.
- **Least exposure.** The root daemon writes secrets and raw samples only to root-only files.
  The menu bar agent runs as the user and reads a separate, secret-free `status.json`.
- **Signed requests.** Webhook bodies are signed with HMAC-SHA256 over timestamp + body, so
  receivers can reject forged and replayed requests. HTTPS is enforced (plain HTTP only for localhost).
- **No cloud credentials on endpoints.** There are deliberately no direct Drive/OneDrive/Dropbox
  uploads: those would need a token on every Mac that can read the whole drive. Storage access lives
  in the webhook receiver; Macs only hold a secret that can submit reports.
- **Untrusted input is escaped.** Process and computer names are HTML-escaped in reports
  (covered by tests); receivers must sanitize `fileName` before using it as a path.
- **No shell interpolation.** External tools are executed by absolute path with argument arrays.
  The uninstall script contains only compile-time constants.
- **No custom password prompts.** Installation uses the standard macOS Installer or MDM.

## Reporting a vulnerability

Please open a private security advisory on GitHub ("Security" tab → "Report a vulnerability")
instead of a public issue.
