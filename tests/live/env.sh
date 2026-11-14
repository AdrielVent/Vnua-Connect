# Source me: exports SB_URL, SB_ANON (public, from web/config.js) and SB_SERVICE (fetched at runtime from your
# logged-in Supabase CLI; never written to disk or committed).
cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.."
export SB_URL=https://mjxriwbyvfyndrwtqeeh.supabase.co
export SB_ANON=$(node -e "const g={window:{}};require('vm').runInNewContext(require('fs').readFileSync('web/config.js','utf8'),g);console.log(g.window.VNUA_CONFIG.supabaseAnonKey)")
for i in 1 2 3 4 5; do
  SB_SERVICE=$(supabase projects api-keys -o json 2>/dev/null | python3 -c 'import json,sys; print([k["api_key"] for k in json.load(sys.stdin) if k["name"]=="service_role"][0])' 2>/dev/null) && [ -n "$SB_SERVICE" ] && break; sleep 3
done
export SB_SERVICE
