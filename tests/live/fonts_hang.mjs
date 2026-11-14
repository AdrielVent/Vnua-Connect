// Simulates campus Wi-Fi where Google Fonts never answers: the app must still start.
import { webkit, devices } from 'playwright';
const b = await webkit.launch(); const ctx = await b.newContext(devices['iPhone 15 Pro']); const p = await ctx.newPage();
await p.route('**/fonts.googleapis.com/**', () => {});      // never fulfilled = hangs forever
await p.route('**/fonts.gstatic.com/**', () => {});
const t0 = Date.now();
await p.goto(process.env.SITE, { waitUntil: 'commit' });
try { await p.waitForSelector('#signin', { timeout: 15000 }); console.log(`✓ app started in ${Date.now() - t0} ms with Google Fonts hanging`); }
catch { console.log('✗ app did NOT start while Google Fonts hangs'); process.exitCode = 1; }
await b.close();
