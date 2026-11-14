# Vnua-connect — Giving clubs a chance.

A home for emerging, student-led clubs at Hofstra: discover clubs, join or help found one, RSVP, show a check-in pass, and give officers phone check-in, corrections and attendance exports.

Vnua-connect is student-run. It isn't affiliated with or endorsed by Hofstra University, and appearing on it doesn't mean university recognition.

## Try it
- **Web (Safari, any phone or computer):** https://adrielvent.github.io/Vnua-Connect/. Sign in with your Hofstra email. On iPhone, use Share → Add to Home Screen.
- **iPhone app:** open `VnuaConnect-iOS/VnuaConnect.xcodeproj` in Xcode and press Run. See `VnuaConnect-iOS/README.md`.
- **Original design prototype** (fictional data, works offline): https://adrielvent.github.io/Vnua-Connect/prototype/

Both apps use the same live backend, so a club started on the web shows up in the iPhone app.

## How it fits together
| Folder | What it is |
|---|---|
| `index.html`, `web/` | Live web app. Plain HTML/CSS/JS with no build step; GitHub Pages serves it as is |
| `VnuaConnect-iOS/` | Native SwiftUI iPhone app |
| `supabase/` | Backend: database schema, security rules, server functions, security tests. See `supabase/README.md` |
| `prototype/`, `src/` | The original clickable design prototype and its source |

All the rules live in the database: who can see what, officer-only check-in, one record per person per event, corrections that keep the original. The web and iPhone apps can't bypass them. `web/config.js` contains the Supabase **anon** key, which is public by design. The service_role key must never appear in this repo.

## Run the web app locally
```
python3 -m http.server 8000      # from the repo root
# open http://localhost:8000/
```
Sign-in links can return to `http://localhost:8000/` and to the GitHub Pages URL (set in `supabase/config.toml`).

## Updating the live site
Push to `main`. GitHub Pages redeploys in about a minute. When `web/app.js` or `web/app.css` changes, bump the `?v=` number in `index.html` so browsers don't use a cached copy.

## License
MIT. See `LICENSE`. QR libraries (qrcode-generator, jsQR) are MIT/Apache-2.0. Fonts are not included in this repo.
