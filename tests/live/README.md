# Live tests (what "verified" means in the docs)

| Script | What it tests | Where |
|---|---|---|
| `run.sh` → `web_e2e.mjs` | Every web feature end to end (~95 checks), with throwaway accounts, deleted afterwards | **WebKit on a Mac emulating an iPhone**, against the live site + live Supabase |
| `ios_sim_demo_path.mjs` | The Nov 20 demo path, tapping through real **iOS Mobile Safari** | **iPhone 17 Pro Simulator** via Apple's `safaridriver` (not a physical phone). Some taps/typing fall back to JS; the script prints how many. |
| `ptr_check.mjs` | Pull-to-refresh in Home Screen mode: success, failed reload, sideways swipe, indicator cleanup | WebKit with standalone mode and touch data emulated (not a physical iPhone) |
| `reminder_probe.mjs` | The pg_cron reminder scheduler delivers a reminder | Live database |
| `fonts_hang.mjs` | The app still starts if Google Fonts never answers | WebKit |
| `photo_storage_probe.mjs` | Profile-photo storage permissions | Live storage |
| `../../supabase/tests/run_local.sh` | Database security rules (9 suites) | Local Postgres with every migration |

None of these is a physical iPhone, a real inbox, or the Home Screen install; see `docs/DEMO.md` for the on-device run.
`../vnua.spec.js` + `../../playwright.config.js` are the **old prototype's** tests and say nothing about the live app.

Setup: `cd tests/live && npm install && npx playwright install webkit`, and be logged in to the Supabase CLI.
