// The Nov 20 demo path, driven in REAL iOS Mobile Safari (iPhone 17 Pro Simulator, iOS 26.5) through Apple's safaridriver.
// Not a physical device. Throwaway accounts + a throwaway fully-staffed club; everything is deleted at the end.
// Sign-in uses the password fallback (an email link can't be opened inside the simulator from a real inbox).
import fs from 'node:fs';
const URL_ = process.env.SB_URL, ANON = process.env.SB_ANON, SERVICE = process.env.SB_SERVICE, SITE = process.env.SITE, OUT = process.env.SHOTS;
const WD = 'http://localhost:4444', UDID = '4BAE1C8D-D1FD-434C-AA4E-30BA06817AFC';
const stamp = Date.now().toString(36);
let failures = 0, sid, n = 0;
const ok = (c, m) => { console.log(`${c ? '✓' : '✗'} ${m}`); if (!c) failures++; };
const created = { users: [], clubs: [] };

async function api(path, { method = 'GET', body, key = SERVICE, token, headers = {} } = {}) {
  const r = await fetch(URL_ + path, { method, headers: { apikey: key, Authorization: `Bearer ${token || key}`, 'Content-Type': 'application/json', ...headers }, body: body && JSON.stringify(body) });
  const t = await r.text(); let j; try { j = JSON.parse(t); } catch { j = t; }
  if (!r.ok) throw new Error(`${method} ${path} → ${r.status} ${t.slice(0, 200)}`); return j;
}
async function makeUser(email, password) {
  const u = await api('/auth/v1/admin/users', { method: 'POST', body: { email, password, email_confirm: true } });
  created.users.push(u.id);
  const s = await api('/auth/v1/token?grant_type=password', { method: 'POST', key: ANON, body: { email, password } });
  return { id: u.id, email, password, token: s.access_token };
}
const rpcAs = (u, fn, body) => api(`/rest/v1/rpc/${fn}`, { method: 'POST', key: ANON, token: u.token, body });

async function wd(method, path, body) {
  const r = await fetch(`${WD}/session/${sid}${path}`, { method, headers: { 'Content-Type': 'application/json' }, body: body && JSON.stringify(body) });
  const j = await r.json(); if (j.value?.error) throw new Error(`${path}: ${j.value.message}`); return j.value;
}
const js = (script, ...args) => wd('POST', '/execute/sync', { script, args });
const go = (url) => wd('POST', '/url', { url });
async function waitFor(cond, ms = 20000, label = cond) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) { if (await js(`try { return !!(${cond}); } catch (e) { return false; }`)) return true; await new Promise((r) => setTimeout(r, 300)); }
  throw new Error('timed out waiting for: ' + label);
}
const text = (sel) => js(`return document.querySelector(${JSON.stringify(sel)})?.textContent || ''`);
async function el(sel) { const v = await wd('POST', '/element', { using: 'css selector', value: sel }); return Object.values(v)[0]; }
// Tap = a W3C touch action (finger down/up on the element's center) — the closest WebDriver gets to a real finger.
// If iOS doesn't turn it into a click, fall back to element.click() and count it, so the report can say so.
let fallbackTaps = 0;
async function tap(sel) {
  const id = await el(sel);
  // Only a click that lands ON the intended element counts (a tap that hits a neighbour after a scroll doesn't).
  await js(`const t = document.querySelector(arguments[0]); window.__clicked = 0;
    document.addEventListener('click', (e) => { if (t.contains(e.target) || e.target.closest('label')?.contains(t)) window.__clicked++; }, { capture: true, once: true });
    document.activeElement?.blur?.(); t.scrollIntoView({ block: 'center' }); return 1`, sel);
  await new Promise((r) => setTimeout(r, 400));   // let iOS finish scrolling before measuring the element
  await wd('POST', '/actions', { actions: [{ type: 'pointer', id: 'finger', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, origin: { 'element-6066-11e4-a52e-4f735466cecf': id }, x: 0, y: 0 },
    { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 60 }, { type: 'pointerUp', button: 0 }] }] });
  await wd('DELETE', '/actions').catch(() => {});
  await new Promise((r) => setTimeout(r, 350));
  if (!(await js('return window.__clicked'))) { fallbackTaps++; await js(`document.querySelector(${JSON.stringify(sel)}).click(); return 1`); }
}
// Typing: real WebDriver keystrokes first; if iOS didn't put the text in the field, set it with JS and count it.
let fallbackTypes = 0;
async function type(sel, t) {
  const id = await el(sel);
  await tap(sel).catch(() => {});
  await wd('POST', `/element/${id}/clear`, {}).catch(() => {});
  await wd('POST', `/element/${id}/value`, { text: t }).catch(() => {});
  const got = await js(`return document.querySelector(${JSON.stringify(sel)}).value`);
  if (got !== t) {
    fallbackTypes++;
    await js(`const e = document.querySelector(${JSON.stringify(sel)}); e.value = arguments[0]; e.dispatchEvent(new Event('input', { bubbles: true })); return 1`, t);
  }
}
async function shot(name) { const b64 = await wd('GET', '/screenshot'); fs.writeFileSync(`${OUT}/${String(++n).padStart(2, '0')}-${name}.png`, Buffer.from(b64, 'base64')); }

const s0 = await (await fetch(`${WD}/session`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ capabilities: { alwaysMatch: { browserName: 'Safari', platformName: 'iOS', 'safari:useSimulator': true, 'safari:deviceUDID': UDID } } }) })).json();
sid = s0.value.sessionId; if (!sid) throw new Error(JSON.stringify(s0));
const ua = await js('return navigator.userAgent');
console.log('browser:', ua);
try {
  // Fixture: a fully staffed, published club (4 officers) + a brand-new student who has never used the app.
  const pw = 'Sim-' + stamp;
  const [pres, vp, tres, sec, student] = await Promise.all(['pres', 'vp', 'tres', 'sec', 'new'].map((r) => makeUser(`vnua-sim-${r}-${stamp}@pride.hofstra.edu`, pw)));
  await Promise.all([[pres, 'Ana Ruiz'], [vp, 'Marco Diaz'], [tres, 'Priya Shah'], [sec, 'Leo Kim']].map(([u, nm]) => rpcAs(u, 'save_profile', { p_name: nm, p_major: 'Aerospace Engineering', p_year: 'Junior', p_pronouns: '', p_interests: ['Engineering'], p_bio: '', p_phone: '', p_linkedin: '', p_share_email: true, p_share_phone: false, p_share_linkedin: false, p_discoverable: false, p_leaderboard: true })));
  const club = await rpcAs(pres, 'create_club', { p_name: `Sim Rocketry ${stamp}`, p_interest: 'Engineering', p_blurb: 'Build and launch high-power rockets.', p_about: '', p_monogram: 'SR', p_accent: '#2c455d', p_requires_approval: false });
  created.clubs.push(club);
  for (const [u, pos] of [[vp, 'Vice President'], [tres, 'Treasurer'], [sec, 'Secretary']]) {
    const inv = await rpcAs(pres, 'invite_officer', { p_club: club, p_email: u.email, p_position: pos });
    await rpcAs(u, 'respond_invite', { p_invite: inv, p_accept: true });
  }
  await api(`/rest/v1/clubs?id=eq.${club}`, { method: 'PATCH', body: { is_published: true } });
  ok(true, 'fixture: published club with all four officers; a brand-new student account');

  // 1. Cold shared link, no account
  await go(`${SITE}?fresh=${stamp}`); await js('localStorage.clear(); sessionStorage.clear(); return 1');   // a phone that has never used the app
  await go(`${SITE}?link=${stamp}#/club/${club}`);
  await waitFor(`document.querySelector('[data-action=preview-go][data-v=join]')`, 30000, 'public preview');
  const pv = await text('#preview');
  ok(pv.includes(`Sim Rocketry ${stamp}`) && pv.includes('Ana') && !pv.includes('@'), 'shared link → public preview, no account, no emails shown');
  await shot('preview');
  // 2. Join → sign in (password fallback)
  await js(`window.__log = []; addEventListener('error', (e) => __log.push('error: ' + e.message)); addEventListener('unhandledrejection', (e) => __log.push('rejection: ' + (e.reason && e.reason.message)));
    document.addEventListener('click', (e) => __log.push('click on ' + e.target.tagName + '.' + e.target.className), true);
    document.addEventListener('touchend', () => __log.push('touchend'), true); return 1`);
  await tap('[data-action=preview-go][data-v=join]');
  await new Promise((r) => setTimeout(r, 2500));
  if (process.env.DEBUG) console.log('  after tap:', JSON.stringify(await js('return { log: window.__log, signin: !!document.querySelector("#signin"), hash: location.hash, intent: sessionStorage.getItem("vnua-intent") }')));
  await waitFor(`document.querySelector('#signin')`);
  ok((await text('main')).includes('Join Sim Rocketry'), 'sign-in remembers the student came to join this club');
  ok((await text('main')).includes('Email me a code') && !/sign-in link/i.test(await text('main')), 'sign-in copy says code (matches what the email really contains)');
  await shot('signin');
  await tap('[data-action=signin-mode][data-v=password]');
  await type('input[name=email]', student.email); await type('input[name=password]', pw); await tap('#signin button[type=submit]');
  await new Promise((r) => setTimeout(r, 4000));
  if (process.env.DEBUG) console.log('  after sign-in tap:', JSON.stringify(await js('return { toast: document.querySelector("#toast")?.textContent, cls: document.querySelector("#toast")?.className, log: window.__log, email: document.querySelector("input[name=email]")?.value, pwlen: document.querySelector("input[name=password]")?.value.length, title: document.querySelector("h1")?.textContent }')), 'expected pw length', pw.length);
  // 3. Onboarding
  await waitFor(`document.body.textContent.includes('Welcome to Vnua-connect')`, 30000, 'welcome');
  await shot('welcome'); await tap('[data-action=ob-next]');
  await type('[data-ob=name]', 'Jordan Lee'); await type('[data-ob=major]', 'Mechanical Engineering'); await tap('[data-action=ob-year][data-v=Freshman]');
  await tap('[data-action=ob-next]');
  await tap('[data-action=ob-interest][data-v=Engineering]'); await tap('[data-action=ob-interest][data-v="Tech"]'); await shot('interests');
  await tap('[data-action=ob-next]'); await tap('[data-action=ob-next]');
  await waitFor(`document.querySelector('[data-action=ob-finish][data-v=intent]')`, 20000, 'continue to club');
  ok(true, 'onboarding: name, major, year, interests saved');
  await shot('continue'); await tap('[data-action=ob-finish][data-v=intent]');
  // 4. Join sheet opens on the club
  await waitFor(`document.querySelector('#sheet-form input[name=involvement]')`, 20000, 'join sheet');
  await tap('input[name=recognition]'); await shot('join-sheet'); await tap('#sheet-submit');
  await waitFor(`document.querySelector('[data-mem-card]')`, 20000, 'joined');
  ok(true, 'joined the club from the shared link');
  await shot('joined');
  // 5. Picked for you on Discover
  await tap('.topbar .back'); await waitFor(`document.querySelector('.fair-note')`);
  const disc = await text('#app');
  ok(disc.includes('never by size or popularity'), 'Discover shows the “same spot for every club” note');
  await shot('discover');
  // 6. Officer on the same phone: add account → dashboard shows the new member
  await tap('.tabbar a[href="#/profile"]'); await waitFor(`document.querySelector('.about')`);
  ok((await text('.about')).includes('not affiliated with or endorsed by'), 'disclaimer visible after sign-in (Profile → About)');
  await tap('[data-action=add-account]'); await tap('[data-action=signin-mode][data-v=password]');
  await type('input[name=email]', pres.email); await type('input[name=password]', pw); await tap('#signin button[type=submit]');
  await waitFor(`!document.querySelector('#signin') && document.querySelector('.tabbar')`, 30000, 'officer signed in');
  await go(`${SITE}#/dash/${club}`); await waitFor(`document.querySelector('.recog')`, 30000, 'dashboard');
  await tap('[data-action=dash-tab][data-v=members]');
  const dash = await text('#dash-body');
  ok(dash.includes('Jordan Lee') && dash.includes('1/15 supporters'), 'officer dashboard shows the new member and counts their recognition consent');
  await shot('dashboard');
  // 7. One-tap switch back to the student
  await tap('.topbar .back'); await waitFor(`document.querySelector('.topbar .back[href="#/discover"]')`); await tap('.topbar .back');
  await waitFor(`document.querySelector('.tabbar')`); await tap('.tabbar a[href="#/profile"]');
  await waitFor(`document.querySelector('#accounts [data-action=switch-account]')`);
  await tap('#accounts [data-action=switch-account]');
  await waitFor(`document.querySelector('#toast.show')?.textContent.includes('Signed in as Jordan Lee')`, 30000, 'switched');
  ok(true, 'one tap switches between the student and officer accounts');
  await shot('switched');
} catch (e) {
  failures++; console.log('✗ crashed:', e.message.slice(0, 300)); await shot('FAIL').catch(() => {});
} finally {
  await fetch(`${WD}/session/${sid}`, { method: 'DELETE' }).catch(() => {});
  for (const id of created.clubs) await api(`/rest/v1/clubs?id=eq.${id}`, { method: 'DELETE' }).catch((e) => console.log('cleanup club', e.message));
  for (const id of created.users) await api(`/auth/v1/admin/users/${id}`, { method: 'DELETE' }).catch((e) => console.log('cleanup user', e.message));
  console.log(`cleanup: ${created.clubs.length} club, ${created.users.length} accounts deleted`);
  console.log(`taps that needed the JS click() fallback: ${fallbackTaps}; text fields that needed JS fill: ${fallbackTypes}`);
  console.log(failures ? `${failures} FAILURE(S)` : 'DEMO PATH PASSED (iOS Simulator Safari, not a physical device)');
  process.exit(failures ? 1 : 0);
}
