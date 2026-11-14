#!/usr/bin/env bash
# Sets a password on YOUR Vnua-connect account so you can use "Sign in with a password" (no email needed).
# Run it yourself in Terminal:  cd ~/Desktop/Vnua-Connect && bash supabase/set_password.sh
# Uses your logged-in Supabase CLI to fetch the service key at runtime; nothing is written to disk.
set -euo pipefail
cd "$(dirname "$0")/.."
URL=https://mjxriwbyvfyndrwtqeeh.supabase.co
read -r -p "Account email: " EMAIL
read -r -s -p "New password (8+ characters, hidden): " PW; echo
read -r -s -p "Type it again: " PW2; echo
[[ "$PW" == "$PW2" && ${#PW} -ge 8 ]] || { echo "Passwords didn't match or were too short. Nothing changed."; exit 1; }
KEY=$(supabase projects api-keys -o json 2>/dev/null | python3 -c 'import json,sys; print([k["api_key"] for k in json.load(sys.stdin) if k["name"]=="service_role"][0])')
ANON=$(node -e "const g={window:{}};require('vm').runInNewContext(require('fs').readFileSync('web/config.js','utf8'),g);console.log(g.window.VNUA_CONFIG.supabaseAnonKey)")
ID=$(curl -sf "$URL/rest/v1/profiles?email=eq.$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1].lower()))' "$EMAIL")&select=id" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["id"] if d else "")')
[[ -n "$ID" ]] || { echo "No Vnua-connect account with that email. Nothing changed."; exit 1; }
BODY=$(python3 -c 'import json,sys; print(json.dumps({"password": sys.argv[1]}))' "$PW")
curl -sf -X PUT "$URL/auth/v1/admin/users/$ID" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d "$BODY" >/dev/null
LOGIN=$(python3 -c 'import json,sys; print(json.dumps({"email": sys.argv[1].lower(), "password": sys.argv[2]}))' "$EMAIL" "$PW")
if curl -sf -X POST "$URL/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" -d "$LOGIN" | grep -q access_token; then
  echo "Done. In the app: Sign in with a password → $EMAIL + your new password."
else
  echo "Password was set but the test sign-in failed. Tell Claude."; exit 1
fi
