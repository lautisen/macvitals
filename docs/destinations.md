# Where reports go

Every report is always written to `reportDirectory` on the Mac itself. To collect reports
centrally, MacVitals POSTs each one to a **webhook**: a URL you control that stores it wherever you like.

Why a webhook and not built-in Google Drive / OneDrive / Dropbox uploads? Uploading directly would
mean storing an OAuth token or service-account key on **every** Mac. Anyone who extracts it could
read or delete your whole drive. A webhook keeps cloud credentials in one place you control; the
Macs only hold a signing secret that can do nothing but submit reports.

## Pick your platform

| You use… | Receiver | Cost | Effort | Signature verified |
|---|---|---|---|---|
| **Google Drive** | [Apps Script web app](#google-drive-apps-script) | Free | 5 min | ✅ (query params) |
| **SharePoint / OneDrive** | [Power Automate flow](#sharepoint--onedrive-power-automate) | Microsoft 365 | 10 min | ⚠️ not natively |
| SharePoint / OneDrive, verified | Azure Function → Microsoft Graph | Azure | 1 h | ✅ |
| Dropbox, Box, S3, Notion, Slack… | [n8n / Make / Zapier](#n8n--make--zapier) | Varies | 15 min | ✅ (code step) |
| **Your own server** | [`receiver.py`](../examples/receiver/receiver.py) or [any API](#your-own-api) | Free | 5 min | ✅ |

## Payload

```jsonc
{
  "schema": 1,
  "kind": "initial | partial | final | test",
  "fileName": "MacVitals_Design-MBP-14_alex_20261007-0900.html",  // stable for the whole session
  "computerName": "Design-MBP-14",
  "user": "alex",
  "generatedAt": "2026-10-07T10:00:00Z",
  "periodStart": "2026-10-07T09:00:00Z",
  "periodEnd": "2026-10-14T09:00:00Z",                              // absent = no end date
  "summary": { "cpuAverage": 25.1, "memoryPeak": 96, "batteryHealth": 78.4, "...": "..." },
  "insights": [ { "severity": "warning", "title": "Battery needs service (78.4 % health)", "detail": "..." } ],
  "contentType": "text/html",
  "contentBase64": "PCFkb2N0eXBlIGh0bWw+..."
}
```

`fileName` is stable for the whole session: writing it to the same path makes each hourly update
**replace** the previous one, so you get one file per Mac per session. `summary` and `insights`
let you trigger alerts (e.g. "battery needs service") without parsing HTML.

## Signature

With `webhook.secret` set, every request is signed:

| Header | Value |
|---|---|
| `X-MacVitals-Timestamp` | Unix time in seconds |
| `X-MacVitals-Signature` | `sha256=` + hex HMAC-SHA256 of `"<timestamp>.<raw body>"` |

With `"signatureInQuery": true` the same values are also appended to the URL as `mv_ts` and
`mv_sig`, for platforms that cannot read headers (Apps Script).

Receivers should recompute the HMAC, compare in constant time, and reject timestamps older than
~5 minutes. Reference implementations:
[Swift](../Sources/MacVitalsCore/Delivery/Delivery.swift) (`RequestSignature.verify`),
[Python](../examples/receiver/receiver.py), [Apps Script](../examples/google-drive/Code.gs).

Failed deliveries (network errors, non-2xx) wait in an on-disk outbox and are retried on the next
sampling tick, including after reboots.

## Recipes

### Google Drive (Apps Script)

Full instructions are in the header of [`examples/google-drive/Code.gs`](../examples/google-drive/Code.gs):
paste the script, set `FOLDER_ID` and `MACVITALS_SECRET` as script properties, deploy as a web app,
then:

```json
"webhook": { "url": "https://script.google.com/macros/s/…/exec", "secret": "…", "signatureInQuery": true }
```

The script runs as you, so reports land in your Drive (or a Shared Drive folder you can write to).
Apps Script always answers HTTP 200, even when it rejects a request; check its *Executions* log.

### SharePoint / OneDrive (Power Automate)

1. New flow → trigger **When an HTTP request is received** (Who can trigger: *Anyone*).
2. Paste the payload above as sample JSON to generate the schema.
3. Action **SharePoint › Create file** (or **OneDrive › Create file**):
   - File name: `triggerBody()?['fileName']`
   - File content: `base64ToBinary(triggerBody()?['contentBase64'])`
4. Action **Response** with status `200`.
5. Put the trigger URL in `webhook.url`, **in your MDM profile, never in the package or a repository**.

The trigger URL embeds a `sig=` token that works like a password, and Power Automate cannot check
HMAC signatures. If that matters, put an Azure Function in front that verifies
`X-MacVitals-Signature` and writes the file through Microsoft Graph.

### n8n / Make / Zapier

Webhook trigger → code step that verifies the signature (port `verify()` from `receiver.py`) →
decode `contentBase64` → save to Dropbox, Box, S3, Google Drive, or post `insights` to Slack/Teams.

### Your own API

Anything that accepts `POST application/json` over HTTPS and returns `2xx`. Add authentication
headers with `webhook.headers` if your gateway needs them. Plain `http://` is accepted only for
`localhost`, for testing:

```bash
MACVITALS_SECRET=change-me python3 examples/receiver/receiver.py --port 8787
```
