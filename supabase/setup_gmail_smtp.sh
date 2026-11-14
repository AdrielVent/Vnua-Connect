#!/usr/bin/env bash
# Connects Gmail to Supabase so sign-in emails contain a 6-digit CODE (no link), then proves it with a real code.
# Run it yourself in Terminal (not through Claude) so your app password never appears in a chat log:
#     cd ~/Desktop/Vnua-Connect && bash supabase/setup_gmail_smtp.sh
# Needs: a Gmail with 2-Step Verification and an App password (Google Account → Security → App passwords).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Vnua-connect: switch sign-in emails to a 6-digit code"
echo
read -r -p "Gmail address that will send the codes: " SMTP_USER
SMTP_USER="$(echo "$SMTP_USER" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
if [[ "$SMTP_USER" != *@gmail.com && "$SMTP_USER" != *@googlemail.com ]]; then
  echo "Use a personal Gmail address (…@gmail.com). School accounts like @pride.hofstra.edu usually can't create app passwords."
  exit 1
fi
read -r -s -p "Its 16-character App password (hidden as you type): " SMTP_PASS; echo
SMTP_PASS="${SMTP_PASS//[[:space:]]/}"            # Google shows it in groups of 4; spaces don't matter
[[ "$SMTP_USER" == *@* && ${#SMTP_PASS} -ge 16 ]] || { echo "That doesn't look right. Nothing was changed."; exit 1; }
export SMTP_USER SMTP_PASS

echo; echo "Checking what will change on Supabase…"
DIFF_OUT="$(supabase config diff --output-format json 2>&1 || true)"
if ! echo "$DIFF_OUT" | python3 -c "
import json,sys; t=sys.stdin.read(); j=json.loads(t[t.index('{'):])
if j.get('_tag') == 'Error': raise SystemExit(1)
print('Changes that will be sent to Supabase (nothing else changes):')
for c in j.get('changes', []): print('  ', '.'.join(c['path']))" 2>/dev/null; then
  echo "Supabase couldn't compare settings. Its message was:"; echo "$DIFF_OUT" | tail -15
  echo "Nothing was changed. Copy the lines above to Claude."; exit 1
fi
read -r -p "Apply? (y/n) " ok; [[ "$ok" == y* ]] || { echo "Cancelled. Nothing was changed."; exit 1; }
PUSH_OUT="$(supabase config push --yes 2>&1)" || { echo "Supabase refused the change:"; echo "$PUSH_OUT" | tail -15; echo "Copy the lines above to Claude."; exit 1; }
echo "Supabase now sends sign-in email through $SMTP_USER."

# Prove it end to end: send a real code, type it in, verify it with Supabase.
URL=https://mjxriwbyvfyndrwtqeeh.supabase.co
ANON=$(node -e "const g={window:{}};require('vm').runInNewContext(require('fs').readFileSync('web/config.js','utf8'),g);console.log(g.window.VNUA_CONFIG.supabaseAnonKey)")
echo
read -r -p "Your Hofstra email to receive a test code: " ME
curl -sf -X POST "$URL/auth/v1/otp" -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d "{\"email\":\"$ME\",\"create_user\":false}" >/dev/null || { echo "Supabase could not send the email. Check the Gmail address and App password, then run this again."; exit 1; }
echo "Sent. Check $ME (and junk). The email should show ONLY a 6-digit code, no link."
read -r -p "Type the code: " CODE
if curl -sf -X POST "$URL/auth/v1/verify" -H "apikey: $ANON" -H "Content-Type: application/json" \
     -d "{\"type\":\"email\",\"email\":\"$ME\",\"token\":\"$CODE\"}" | grep -q access_token; then
  echo; echo "CODE SIGN-IN VERIFIED. Tell Claude \"codes work\" so the website switches to code mode."
else
  echo; echo "Code was rejected (wrong, expired, or the email still had a link). Nothing else changed; tell Claude what you saw."
  exit 1
fi
