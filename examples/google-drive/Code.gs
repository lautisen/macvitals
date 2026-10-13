/**
 * MacVitals → Google Drive receiver (Google Apps Script web app).
 *
 * Saves every report into one Drive folder, replacing the previous version of the same
 * session's file. No Google credentials are ever stored on the Macs.
 *
 * Setup (5 minutes):
 *   1. script.google.com → New project → paste this file.
 *   2. Project Settings → Script properties:
 *        FOLDER_ID          the id at the end of the Drive folder URL
 *        MACVITALS_SECRET   a long random string (openssl rand -base64 32)
 *   3. Deploy → New deployment → Web app → Execute as: Me, Who has access: Anyone.
 *   4. In the MacVitals config:
 *        "webhook": { "url": "<web app URL>", "secret": "<same secret>", "signatureInQuery": true }
 *
 * Apps Script cannot read request headers, hence `signatureInQuery`: the HMAC travels as the
 * `mv_ts` / `mv_sig` query parameters. It also cannot return HTTP error codes, so rejected
 * requests still answer 200 with an explanatory body; check the script's Executions log.
 */

const TOLERANCE_SECONDS = 300;

function doPost(e) {
  const props = PropertiesService.getScriptProperties();
  const secret = props.getProperty('MACVITALS_SECRET');
  const folderId = props.getProperty('FOLDER_ID');
  if (!secret || !folderId) return reply('error: set FOLDER_ID and MACVITALS_SECRET in Script properties');

  const body = e.postData && e.postData.contents;
  if (!body) return reply('error: empty body');

  if (!verify(secret, body, e.parameter.mv_ts, e.parameter.mv_sig)) {
    console.warn('Rejected request with an invalid or stale signature');
    return reply('error: invalid signature');
  }

  const payload = JSON.parse(body);
  // Never trust a client-supplied name as a path.
  const name = String(payload.fileName || 'report.html').replace(/[^A-Za-z0-9._-]/g, '-');
  const html = Utilities.newBlob(Utilities.base64Decode(payload.contentBase64)).getDataAsString('UTF-8');

  const folder = DriveApp.getFolderById(folderId);
  const existing = folder.getFilesByName(name);
  if (existing.hasNext()) {
    existing.next().setContent(html);
  } else {
    folder.createFile(name, html, MimeType.HTML);
  }

  const findings = (payload.insights || []).map(function (i) { return i.title; }).join('; ');
  console.log('[' + payload.kind + '] ' + payload.computerName + ' → ' + name + ' | ' + findings);
  return reply('ok');
}

/** HMAC-SHA256 over "<timestamp>.<body>", same scheme as RequestSignature in the Swift code. */
function verify(secret, body, timestamp, signature) {
  const ts = parseInt(timestamp, 10);
  if (!ts || Math.abs(Date.now() / 1000 - ts) > TOLERANCE_SECONDS || !signature) return false;
  const mac = Utilities.computeHmacSha256Signature(ts + '.' + body, secret, Utilities.Charset.UTF_8);
  const expected = 'sha256=' + mac.map(function (b) { return ('0' + (b & 0xff).toString(16)).slice(-2); }).join('');
  if (expected.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  return diff === 0;
}

function reply(text) {
  return ContentService.createTextOutput(text).setMimeType(ContentService.MimeType.TEXT);
}
