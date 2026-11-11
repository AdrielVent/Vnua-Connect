# Vnua-connect — Giving clubs a chance.

Prototype app for emerging, student-led interest groups: discover clubs, join or help found one, RSVP, check in, and give officers phone check-in, corrections and attendance downloads.

**Prototype status:** all data is fictional. There is no backend, real login, email or secure attendance. `src/vnua-mock-api.js` simulates the server. Vnua-connect isn't affiliated with or endorsed by Hofstra, SHPE or AIAA, and appearing on it doesn't mean university recognition.

## Files
- `index.html`: a self-contained build that works offline. Open it directly or host it.
- `src/`: editable source. Serve this folder and open `Vnua-connect.dc.html`.
- `tests/`, `playwright.config.js`: Playwright wrapper around the in-page self-test.

## Run locally
```
cd src && python3 -m http.server 8000
# open http://localhost:8000/Vnua-connect.dc.html
# browser console: await vnuaSelfTest()
```
To run the Playwright tests, run them from the repo root after changing the config's `webServer` command to `cd src && python3 -m http.server 8000`:
```
npm i -D @playwright/test && npx playwright install chromium && npx playwright test
```

## Publish with GitHub Pages
1. Create an empty repo on github.com (for example `vnua-connect`).
2. Push this folder:
```
git init && git add . && git commit -m "Vnua-connect prototype"
git branch -M main
git remote add origin https://github.com/AdrielVent/vnua-connect.git
git push -u origin main
```
3. In the repo, go to Settings → Pages → Source: "Deploy from a branch", then pick `main` and `/ (root)`.
4. The site goes live at `https://AdrielVent.github.io/vnua-connect/`. To embed it in your website:
```html
<iframe src="https://AdrielVent.github.io/vnua-connect/" style="width:100%;height:900px;border:0" title="Vnua-connect"></iframe>
```

## Toward a publishable app
This site is a design prototype, not something ready for app stores. To get there:
1. Add a real backend and authentication, with per-club officer roles enforced on the server, following the API contract in `vnua-mock-api.js`.
2. Add email verification, plus privacy, retention and deletion policies.
3. Package it as an installable web app (PWA) or wrap it with Capacitor for the app stores.

## License
MIT. See `LICENSE`. The bundled QR library (qrcode-generator) is also MIT.

## Links
- Repo: https://github.com/AdrielVent/vnua-connect
- Live demo: https://adrielvent.github.io/vnua-connect/
- iPhone app mode: https://adrielvent.github.io/vnua-connect/?app=1 (Safari → Share → Add to Home Screen)
