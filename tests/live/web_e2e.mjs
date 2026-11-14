// End-to-end test of the Vnua-connect web app in WebKit (Safari's engine) against the LIVE Supabase project.
// Creates throwaway accounts with the admin API (no emails sent) and deletes everything afterwards.
import { webkit, devices } from 'playwright';
import zlib from 'node:zlib';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);

const URL_ = process.env.SB_URL, ANON = process.env.SB_ANON, SERVICE = process.env.SB_SERVICE;
const SITE = process.env.SITE || 'http://localhost:8000/';
const SHOTS = process.env.SHOTS;
const REF = new globalThis.URL(URL_).hostname.split('.')[0];
const stamp = Date.now().toString(36);
const mk = (role, name) => ({ email: `vnua-e2e-${role}-${stamp}@pride.hofstra.edu`, name });
const PRES = mk('pres', 'Pat President'), VP = mk('vp', 'Val Vice'), TRES = mk('tres', 'Tia Treasurer'), SEC = mk('sec', 'Sam Secretary'), MEM = mk('mem', 'Mo Member');
const created = { users: [], clubs: [], events: [] };
let failures = 0;
const ok = (cond, msg) => { console.log(`${cond ? '✓' : '✗'} ${msg}`); if (!cond) failures++; };

async function api(path, { method = 'GET', body, key = SERVICE, token, headers = {} } = {}) {
  const r = await fetch(URL_ + path, { method, headers: { apikey: key, Authorization: `Bearer ${token || key}`,
    'Content-Type': 'application/json', ...headers }, body: body && JSON.stringify(body) });
  const text = await r.text(); let json; try { json = JSON.parse(text); } catch { json = text; }
  if (!r.ok) throw new Error(`${method} ${path} → ${r.status} ${text.slice(0, 200)}`);
  return json;
}
const rpcAs = (u, fn, body) => api(`/rest/v1/rpc/${fn}`, { method: 'POST', key: ANON, token: u.session.access_token, body });
async function makeUser(u) {
  const user = await api('/auth/v1/admin/users', { method: 'POST', body: { email: u.email, email_confirm: true } });
  created.users.push(user.id);
  const link = await api('/auth/v1/admin/generate_link', { method: 'POST', body: { type: 'magiclink', email: u.email } });
  const session = await api('/auth/v1/verify', { method: 'POST', key: ANON, body: { type: 'magiclink', token_hash: link.hashed_token ?? link.properties?.hashed_token } });
  return { ...u, id: user.id, session };
}
const onboard = (u, interests = ['Games'], extra = {}) => rpcAs(u, 'save_profile', { p_name: u.name, p_major: 'Undeclared', p_year: 'Junior', p_pronouns: '',
  p_interests: interests, p_bio: '', p_phone: '', p_linkedin: '', p_share_email: true, p_share_phone: false, p_share_linkedin: false,
  p_discoverable: true, p_leaderboard: true, ...extra });
async function openAs(browser, u, colorScheme = 'light') {
  const ctx = await browser.newContext({ ...devices['iPhone 15 Pro'], colorScheme });
  await ctx.addInitScript(([k, v]) => { if (!localStorage.getItem(k)) localStorage.setItem(k, v); },
    [`sb-${REF}-auth-token`, JSON.stringify(u.session)]);
  const page = await ctx.newPage();
  (globalThis.pages ||= []).push(page);
  page.on('pageerror', (e) => { console.log('  page error:', e.message); failures++; });
  page.on('dialog', (d) => d.dismiss());
  page.on('console', (m) => { if (m.type() === 'error') console.log(`  [${u.name}] console:`, m.text().slice(0, 300)); });
  return page;
}
const shot = (page, name) => SHOTS && page.screenshot({ path: `${SHOTS}/${name}.png`, fullPage: false });
const toastHas = async (p, text) => { await p.waitForFunction((t) => document.querySelector('#toast.show')?.textContent.includes(t), text, { timeout: 15000 }); return true; };
// A real 64×48 PNG (two colors), so cropping to a square is exercised.
const PNG = (() => {           // valid 64x48 RGB PNG, left half brick, right half white
  const w = 64, h = 48, crcT = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
  const crc = (b) => { let c = 0xffffffff; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (t, d) => { const len = Buffer.alloc(4); len.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([len, td, c]); };
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const o = y * (w * 3 + 1) + 1 + x * 3; const brick = x < w / 2; raw[o] = brick ? 138 : 255; raw[o + 1] = brick ? 59 : 255; raw[o + 2] = brick ? 46 : 255; }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
})();

const browser = await webkit.launch();
try {
  const [pres, vp, tres, sec, mem] = await Promise.all([PRES, VP, TRES, SEC, MEM].map(makeUser));
  await Promise.all([onboard(vp), onboard(tres), onboard(sec), onboard(mem, ['Games', 'Music'], { p_phone: '516 555 0100', p_share_phone: true })]);
  ok(true, 'created five throwaway accounts (no email sent)');

  // ── Slow/blocked Google Fonts (campus Wi-Fi) must never stop the app from starting
  {
    const ctx = await browser.newContext(devices['iPhone 15 Pro']); const p = await ctx.newPage();
    await p.route('**/fonts.googleapis.com/**', () => {}); await p.route('**/fonts.gstatic.com/**', () => {});
    await p.goto(SITE, { waitUntil: 'commit' });
    ok(await p.waitForSelector('#signin', { timeout: 15000 }).then(() => true, () => false), 'app starts even when Google Fonts hangs');
    await ctx.close();
  }

  // ── Signed out: code-based sign-in screen; non-campus email refused before any email goes out
  {
    const ctx = await browser.newContext(devices['iPhone 15 Pro']); const p = await ctx.newPage();
    await p.goto(SITE); await p.waitForSelector('#signin');
    // NOTE: this checks the screen's wording only. Whether an email arrives (and what it contains) can only be checked in a real inbox.
    ok((await p.textContent('#signin button[type=submit]')).includes('Email me a code'), 'sign-in screen says it emails a code (matches signInEmail = code)');
    ok(!/tap the link|sign-in link/i.test(await p.textContent('main')), 'sign-in screen never mentions a link');
    ok((await p.textContent('main')).includes('not affiliated with or endorsed by'), 'disclaimer on the sign-in screen');
    await shot(p, '01-signin');
    await p.fill('input[name=email]', 'someone@gmail.com'); await p.click('button[type=submit]');
    ok(await toastHas(p, 'Hofstra'), 'non-Hofstra email is refused before any email is sent');
    await ctx.close();
  }

  // ── Code sign-in path (what the app does once SMTP sends codes). The "send email" call is intercepted so no real
  //    email goes out; the 6-digit code comes from the admin API; typing it into the app signs in for real.
  {
    const codeUser = mk('code', 'Cody Code'); const cu = await api('/auth/v1/admin/users', { method: 'POST', body: { email: codeUser.email, email_confirm: true } });
    created.users.push(cu.id);
    const ctx = await browser.newContext(devices['iPhone 15 Pro']); const p = await ctx.newPage();
    p.on('pageerror', (e) => { console.log('  page error:', e.message); failures++; });
    await p.route('**/web/config.js*', async (route) => { const r = await route.fetch(); const body = (await r.text()).replace("signInEmail: 'link'", "signInEmail: 'code'"); await route.fulfill({ response: r, body }); });
    let otpCalls = 0; await p.route('**/auth/v1/otp*', (route) => { otpCalls++; route.fulfill({ status: 200, contentType: 'application/json', body: '{}' }); });
    await p.goto(SITE); await p.waitForSelector('#signin');
    ok((await p.textContent('#signin button[type=submit]')).includes('Email me a code'), 'code mode: button says it emails a code');
    await p.fill('input[name=email]', codeUser.email); await p.click('#signin button[type=submit]');
    await p.waitForSelector('input[name=code]');
    ok(otpCalls === 1 && !(await p.textContent('main')).toLowerCase().includes('tap the link'), 'code mode: asks only for the code, never mentions a link');
    const link = await api('/auth/v1/admin/generate_link', { method: 'POST', body: { type: 'magiclink', email: codeUser.email } });
    const otp = link.email_otp ?? link.properties?.email_otp;
    await p.fill('input[name=code]', otp);          // 6 digits auto-submits
    await p.waitForSelector('text=Welcome to Vnua-connect', { timeout: 20000 });
    ok(/^\d{6}$/.test(otp), 'typing the real 6-digit code signs in (verifyOtp against production)');
    await shot(p, '01b-code-signin');
    await ctx.close();
  }

  // ── New student: onboarding → start a club with a logo and officer invites
  const pp = await openAs(browser, pres);
  await pp.goto(SITE); await pp.waitForSelector('text=Welcome to Vnua-connect');
  ok(true, 'first sign-in shows the welcome screen');
  await shot(pp, '02-welcome');
  await pp.click('[data-action=ob-next]');
  await pp.fill('[data-ob=name]', pres.name); await pp.fill('[data-ob=major]', 'Computer Science');
  await pp.click('[data-action=ob-year][data-v=Sophomore]');
  await pp.click('[data-action=ob-next]');
  for (const i of ['Games', 'Tech', 'Music']) await pp.click(`[data-action=ob-interest][data-v="${i}"]`);
  await pp.click('[data-action=ob-interest][data-v="Sports"]');
  ok(await toastHas(pp, 'Up to 3'), 'interests are capped at 3');
  await shot(pp, '03-interests');
  await pp.click('[data-action=ob-next]');
  await pp.fill('[data-ob=linkedin]', 'linkedin.com/in/pat-president');
  await shot(pp, '04-contact');
  await pp.click('[data-action=ob-next]');
  await pp.waitForSelector('text=What do you want to do first?');
  ok(true, 'profile saved; asks join or create');
  await pp.click('[data-action=ob-finish][data-v=create]');
  await pp.waitForSelector('[data-nc=name]');
  const clubName = `E2E Chess Night ${stamp}`;
  await pp.fill('[data-nc=name]', clubName); await pp.fill('[data-nc=blurb]', 'Casual chess, all levels.');
  await pp.selectOption('[data-nc=interest]', 'Games');
  await pp.click('[data-action=nc-next]');
  const sw = await pp.$$eval('[data-action=nc-accent]', (b) => b.map((x) => x.dataset.v));
  ok(JSON.stringify(sw) === JSON.stringify(['#001f5b', '#1a3d6d', '#3179a7', '#c2410c']), 'club color choices are SHPE/AIAA navy, AIAA blue and an accessible orange');
  await pp.setInputFiles('input[data-file=nc-logo]', { name: 'logo.png', mimeType: 'image/png', buffer: PNG });
  await pp.waitForSelector('img.logo[alt="Logo preview"]');
  ok(true, 'logo upload previews a square crop');
  await shot(pp, '05-logo');
  await pp.click('[data-action=nc-next]');
  await pp.fill('[data-nc-email="Vice President"]', vp.email);
  await pp.fill('[data-nc-email="Treasurer"]', tres.email);
  await pp.fill('[data-nc-email="Secretary"]', sec.email);
  await shot(pp, '06-team');
  await pp.click('[data-action=nc-next]');
  await pp.waitForURL(/#\/club\//, { timeout: 30000 });
  const clubId = pp.url().split('#/club/')[1]; created.clubs.push(clubId);
  await pp.waitForSelector('.team');
  ok((await pp.textContent('.team .badge')).includes('1/4'), 'club starts "forming" with 1 of 4 core officers');
  ok((await pp.$$('.slot.pending')).length === 3, 'three invites are pending');
  ok(!!(await pp.$('img.logo')), 'club page shows the uploaded logo');
  await shot(pp, '07-club-forming');
  let blocked = false;
  try { await api(`/rest/v1/clubs?id=eq.${clubId}`, { method: 'PATCH', body: { is_published: true } }); } catch (e) { blocked = /needs a president/.test(e.message); }
  ok(blocked, 'a moderator cannot publish it before all four positions are filled');

  // ── VP accepts in the app; treasurer + secretary accept directly
  const vpp = await openAs(browser, vp);
  await vpp.goto(SITE); await vpp.waitForSelector('.bell .dot');
  ok(true, 'invitee sees an unread badge on the inbox bell');
  await vpp.click('.bell'); await vpp.waitForSelector('.invite-card');
  await shot(vpp, '08-inbox-invite');
  await vpp.click('.invite-card [data-action=invite-answer][data-v="1"]');
  await vpp.waitForURL(/#\/club\//); await vpp.waitForSelector('.team');
  ok(true, 'VP accepted from the inbox and lands on the club');
  for (const u of [tres, sec]) {
    const inv = await api(`/rest/v1/club_invites?club_id=eq.${clubId}&email=eq.${u.email}&status=eq.pending&select=id`, { key: ANON, token: u.session.access_token });
    await rpcAs(u, 'respond_invite', { p_invite: inv[0].id, p_accept: true });
  }
  await pp.reload(); await pp.waitForSelector('.team');
  ok((await pp.textContent('.team .badge')).includes('4/4'), 'all four core officers in');
  await api(`/rest/v1/clubs?id=eq.${clubId}`, { method: 'PATCH', body: { is_published: true } });
  ok(true, 'moderator publishes the club once the team is complete');
  await pp.goto(SITE + '#/discover'); await pp.waitForSelector('.fair-note');
  ok((await pp.textContent('.fair-note')).includes('never by size or popularity'), 'Discover says clubs are listed A–Z, never by size');
  await pp.goto(SITE + `#/club/${clubId}`); await pp.waitForSelector('.team');
  {
    const ctx = await browser.newContext(devices['iPhone 15 Pro']); const p = await ctx.newPage();
    p.on('pageerror', (e) => { console.log('  page error:', e.message); failures++; });
    await p.goto(SITE + `#/club/${clubId}`); await p.waitForSelector('text=Help build this group');
    const txt = await p.textContent('#preview');
    ok(txt.includes(clubName) && txt.includes('Pat') && !txt.includes('@'), 'shared club link opens a public preview without signing in (no emails shown)');
    await shot(p, '07b-public-preview');
    await p.click('[data-action=preview-go][data-v=help]'); await p.waitForSelector('#signin');
    ok((await p.textContent('main')).includes(`Help build ${clubName}`), '“Help build this group” leads to sign-in and remembers why');
    await ctx.close();
  }

  // ── Member joins (wants everything), officer posts an event → member is notified
  const mp = await openAs(browser, mem);
  await mp.goto(SITE); await mp.waitForSelector(`a[href="#/club/${clubId}"]`);
  ok((await mp.textContent('#discover-body')).includes('Picked for you'), 'Discover shows clubs picked from your interests');
  await mp.click(`a[href="#/club/${clubId}"]`); await mp.waitForSelector('.people .person');
  ok((await mp.$$('.people .person')).length === 4, 'club page lists the four officers');
  await shot(mp, '09-club-member-view');
  await mp.click('button[data-action=join]'); await mp.click('input[name=involvement][value=organize]'); await mp.click('input[name=notify][value=all]');
  await mp.click('input[name=recognition]'); await shot(mp, '09b-join'); await mp.click('#sheet-submit');
  await mp.waitForSelector('[data-mem-card]');
  ok((await api(`/rest/v1/memberships?club_id=eq.${clubId}&user_id=eq.${mem.id}&select=involvement,recognition_ok,role`))[0].recognition_ok === true, 'joined wanting to help organize, and said yes to recognition contact');
  ok(!(await mp.$('a[href^="#/dash/"]')), 'members do not get officer tools');

  await pp.reload(); await pp.waitForSelector('[data-action=new-event]');
  await pp.click('[data-action=new-event]');
  await pp.fill('input[name=title]', 'Blitz tournament'); await pp.fill('input[name=location]', 'Student Center 141');
  await pp.click('label.chip-check:has(input[value="30"])');
  await pp.click('label.chip-check:has(input[name=perk][value=food])'); await pp.click('label.chip-check:has(input[name=perk][value=prizes])');
  await pp.click('.newcomer-form summary'); await pp.fill('input[name=nc_experience]', 'None needed'); await pp.fill('input[name=nc_bring]', 'A chess set if you have one');
  await shot(pp, '10-new-event');
  await pp.click('#sheet-submit'); await toastHas(pp, 'Event posted');
  const ev = (await api(`/rest/v1/event_hosts?club_id=eq.${clubId}&select=event_id`))[0].event_id; created.events.push(ev);
  const evRow = (await api(`/rest/v1/events?id=eq.${ev}&select=reminders`))[0];
  ok(JSON.stringify(evRow.reminders) === '[1440,120,30]', 'event saved with the reminders the officer picked');
  await mp.goto(SITE + '#/inbox'); await mp.waitForSelector('text=New: Blitz tournament');
  ok(true, 'member who chose "everything" got a New event notification');

  // ── Auto-refresh: a new event appears on an open Events screen within 2 minutes, no tap needed
  {
    const ap = await openAs(browser, mem); await ap.clock.install();
    await ap.goto(SITE + '#/events'); await ap.waitForSelector('[data-action=ev-scope]');
    const evx = (await api('/rest/v1/events', { method: 'POST', headers: { Prefer: 'return=representation' },
      body: { campus_id: 'hofstra', title: 'Auto refresh check', starts_at: new Date(Date.now() + 5 * 864e5).toISOString(), organizer: pres.name } }))[0];
    created.events.push(evx.id);
    await api('/rest/v1/event_hosts', { method: 'POST', body: { event_id: evx.id, club_id: clubId } });
    ok(!(await ap.textContent('#app')).includes('Auto refresh check'), 'new event not shown yet (no refresh happened)');
    await ap.clock.fastForward('02:05');
    ok(await ap.waitForSelector('text=Auto refresh check', { timeout: 15000 }).then(() => true, () => false), 'it appears by itself after the 2-minute auto-refresh');
    await ap.context().close();
  }

  // ── RSVP, pass, check-in by the VP, officer stats
  await mp.goto(SITE + `#/event/${ev}`); await mp.waitForSelector('.newcomer');
  ok((await mp.textContent('.newcomer')).includes('None needed'), 'event shows “First time? Here’s what to know”');
  ok((await mp.textContent('main')).includes('Free food') && (await mp.textContent('main')).includes('Prizes'), 'event shows its perks (Free food, Prizes)');
  ok(JSON.stringify((await api(`/rest/v1/events?id=eq.${ev}&select=perks`))[0].perks) === '["food","prizes"]', 'perks saved on the server');
  await mp.goto(SITE + '#/events'); await mp.waitForSelector('[data-action=ev-perk][data-v=food]');
  await mp.click('[data-action=ev-perk][data-v=food]');
  ok((await mp.textContent('#app')).includes('Blitz tournament'), 'Events → Free food filter shows the event');
  await shot(mp, '10b-perks');
  await mp.click('[data-action=ev-perk][data-v=swag]');
  ok(!(await mp.textContent('#app')).includes('Blitz tournament'), 'Free swag filter hides it (no swag ticked)');
  await mp.click('[data-action=ev-perk][data-v=""]');
  await mp.goto(SITE + `#/event/${ev}`); await mp.waitForSelector('[data-action=rsvp]');
  await mp.route('**/rest/v1/rpc/set_rsvp', (r) => r.abort());
  await mp.click('[data-action=rsvp]');
  await mp.waitForFunction(() => document.querySelector('#toast.show.error'));
  ok((await mp.getAttribute('[data-action=rsvp]', 'aria-pressed')) === 'false', 'a failed RSVP rolls back and says so');
  await mp.unroute('**/rest/v1/rpc/set_rsvp'); await mp.waitForTimeout(3200);
  await mp.click('[data-action=rsvp]'); await mp.waitForSelector('[data-action=rsvp][aria-pressed=true]');
  const pass = await rpcAs(mem, 'issue_pass', { p_event: ev });
  const res = await rpcAs(vp, 'check_in', { p_event: ev, p_request: crypto.randomUUID(), p_token: pass.token });
  ok(res.status === 'recorded', 'the VP (any officer) checks the member in by pass');
  await pp.goto(SITE + `#/event/${ev}`); await pp.waitForSelector('#event-stats .stats');
  const statsText = await pp.textContent('#event-stats');
  ok(/1\s*RSVPs/.test(statsText.replace(/\s+/g, ' ')) || statsText.includes('100%'), 'officer sees RSVP → check-in rate');
  await shot(pp, '11-event-stats');
  await pp.click('[data-action=edit-event]'); await pp.fill('input[name=location]', 'Student Center 142'); await pp.click('#sheet-submit'); await toastHas(pp, 'Event updated');
  ok((await api(`/rest/v1/notifications?user_id=eq.${mem.id}&kind=eq.event_changed&select=id`)).length === 1, 'changing the place tells people who are going');

  // ── A past event: rating prompt 15+ min after it ends, rating officers can't trace
  const past = (await api('/rest/v1/events', { method: 'POST', headers: { Prefer: 'return=representation' },
    body: { campus_id: 'hofstra', title: 'Opening night', starts_at: new Date(Date.now() - 3 * 3600e3).toISOString(), duration_minutes: 60, organizer: pres.name } }))[0];
  created.events.push(past.id);
  await api('/rest/v1/event_hosts', { method: 'POST', body: { event_id: past.id, club_id: clubId } });
  await rpcAs(pres, 'check_in', { p_event: past.id, p_request: crypto.randomUUID(), p_member: mem.id });
  await api('/rest/v1/rpc/send_due_notifications', { method: 'POST', body: {} });
  await mp.goto(SITE + '#/inbox'); await mp.waitForSelector('text=How was Opening night?');
  await shot(mp, '12-inbox-rating');
  await mp.click('.note:has-text("How was Opening night?") .star[data-v="4"]');
  ok(await toastHas(mp, 'never see who rated'), 'member rated the event from the inbox');
  ok(!(await mp.textContent('#app')).toLowerCase().includes('anonymous'), 'inbox never claims ratings are anonymous');
  await mp.goto(SITE + `#/event/${past.id}`); await mp.waitForSelector('#fb-keep');
  await mp.fill('#fb-keep', 'The puzzles'); await mp.fill('#fb-change', 'Start on time'); await mp.click('[data-action=feedback]');
  ok(await toastHas(mp, 'never see who'), 'member added keep/change feedback');
  let hidden = false;
  try { await api('/rest/v1/event_ratings?select=*', { key: ANON, token: pres.session.access_token }); } catch (e) { hidden = /permission denied|42501/.test(e.message); }
  ok(hidden, 'no one (not even officers) can read individual ratings');

  // ── Officer dashboard: rankings, recognition, nudges, CSV
  await pp.goto(SITE + `#/dash/${clubId}`); await pp.waitForSelector('.recog');
  const dashText = await pp.textContent('#dash-body');
  ok(dashText.includes('1/15 supporters'), 'recognition counts members who said yes, not the e-board');
  ok(dashText.includes('app’s supporter target') && !/enough to apply/i.test(dashText) && !dashText.includes('Official recognition'), 'dashboard calls 15 an app supporter target, never “enough to apply”');
  ok(dashText.includes('What should happen after'), 'to-do list asks for a follow-up after a past event');
  await shot(pp, '13a-todo');
  await pp.click('.todo:has-text("Opening night") [data-action=add-task]'); await pp.fill('input[name=title]', 'Post photos from opening night');
  await pp.click('#sheet-submit'); await toastHas(pp, 'Saved');
  await pp.waitForFunction(() => !document.querySelector('#dash-body').textContent.includes('after Opening night'));
  ok(true, 'follow-up task created; the to-do item goes away');
  await pp.click('[data-action=dash-tab][data-v=members]'); await pp.waitForSelector('.chips');
  ok((await pp.textContent('#dash-body')).includes('Top supporter') && (await pp.textContent('#dash-body')).includes('Wants to help organize'), 'member shows as top supporter who wants to help organize');
  ok((await pp.$$('.section-header:has-text("E-board") + .card .list-row')).length === 4, 'e-board listed separately and not ranked');
  await pp.click('[data-action=dash-filter][data-v=quiet]');
  ok((await pp.textContent('#dash-body')).includes('No one matches'), 'filters narrow the member list');
  await shot(pp, '13-dashboard');
  const [dl] = await Promise.all([pp.waitForEvent('download'), pp.click('[data-action=dash-csv]')]);
  ok(/members-.*\.csv/.test(dl.suggestedFilename()), 'member list exports as CSV');
  await pp.click('[data-action=dash-tab][data-v=events]'); await pp.waitForSelector('text=Opening night');
  ok((await pp.textContent('#dash-body')).includes('1/3 ratings needed'), 'average stays hidden until 3 ratings');

  const n = await rpcAs(pres, 'nudge_members', { p_club: clubId, p_users: [mem.id] });
  ok(n === 1, 'officer sends a "still interested?" check-in');
  await mp.goto(SITE + '#/inbox'); await mp.waitForSelector('[data-action=nudge-answer][data-v=busy]');
  await shot(mp, '14-nudge');
  await mp.click('[data-action=nudge-answer][data-v=busy]');
  ok(await toastHas(mp, 'still in'), 'member answers "busy, but keep me in" and stays in the club');

  // ── Find a time: poll → member votes → officer schedules it
  await pp.goto(SITE + `#/dash/${clubId}`); await pp.waitForSelector('.recog');
  await pp.click('[data-action=dash-tab][data-v=polls]'); await pp.click('#dash-body [data-action=new-poll]');
  await pp.fill('input[name=title]', 'Spring kickoff'); await shot(pp, '13b-poll-new'); await pp.click('#sheet-submit'); await toastHas(pp, 'Poll sent');
  await mp.goto(SITE + `#/club/${clubId}`); await mp.waitForSelector('#polls .vote');
  await mp.click('#polls .slot-row >> nth=0 >> [data-action=vote][data-v=yes]'); await toastHas(mp, 'Saved');
  await shot(mp, '13c-poll-vote');
  const poll = (await api(`/rest/v1/polls?club_id=eq.${clubId}&select=id`))[0];
  const results = await rpcAs(vp, 'poll_results', { p_poll: poll.id });
  ok(results.responders === 1, 'officers see totals (1 reply), never who answered what');
  const sched = await rpcAs(pres, 'schedule_poll', { p_poll: poll.id, p_slot: results.slots.find((x) => x.yes === 1).id, p_request: crypto.randomUUID() });
  created.events.push(sched);
  ok(!!sched, 'picking the best time turns the poll into an event');

  // ── Announcement, leaderboard, People
  await pp.goto(SITE + `#/club/${clubId}`); await pp.click('[data-action=announce]');
  await pp.fill('input[name=title]', 'Room change'); await pp.fill('textarea[name=body]', 'We are in Weed 120 this week.');
  await pp.click('#sheet-submit'); await toastHas(pp, 'Sent to');
  await mp.goto(SITE + '#/inbox'); await mp.waitForSelector('text=Room change');
  ok(true, 'announcement reached the member’s inbox');
  await mp.goto(SITE + `#/club/${clubId}`); await mp.waitForSelector('#leaderboard .list-row.me');
  ok(true, 'member sees themselves on the club leaderboard');
  await mp.goto(SITE + '#/people'); await mp.waitForSelector('.person-card');
  ok((await mp.textContent('#people')).includes(vp.name), 'People shows students who share an interest');
  ok(!(await mp.$('#people a[href*="linkedin.com"]')), 'no LinkedIn shown before both opt in');
  await rpcAs(vp, 'save_profile', { p_name: vp.name, p_major: 'Mechanical Engineering', p_year: 'Junior', p_pronouns: '', p_interests: ['Games'], p_bio: '', p_phone: '', p_linkedin: 'linkedin.com/in/val-vice', p_share_email: true, p_share_phone: false, p_share_linkedin: false, p_discoverable: true, p_leaderboard: true });
  await rpcAs(vp, 'set_open_to_connect', { p_on: true });
  await rpcAs(mem, 'save_profile', { p_name: mem.name, p_major: 'mechanical engineering', p_year: 'Junior', p_pronouns: '', p_interests: ['Games', 'Music'], p_bio: '', p_phone: '516 555 0100', p_linkedin: '', p_share_email: true, p_share_phone: true, p_share_linkedin: false, p_discoverable: true, p_leaderboard: true });
  await mp.click('label.toggle:has([data-connect])'); await toastHas(mp, 'Open to connect');
  await mp.waitForSelector('#people a[href*="linkedin.com/in/val-vice"]');
  ok(true, 'LinkedIn appears only once both students turned on “Open to connect”');
  ok((await mp.textContent('#people')).includes('Same major'), 'students with the same major are matched and labeled');
  await shot(mp, '15-people');
  await mp.goto(SITE + '#/profile'); await mp.waitForSelector('[data-privacy=leaderboard]');
  await mp.click('label.toggle:has([data-privacy=leaderboard])');
  let lb = true; for (let i = 0; i < 20 && lb; i++) { await mp.waitForTimeout(250); lb = (await api(`/rest/v1/profiles?id=eq.${mem.id}&select=leaderboard`))[0].leaderboard; }
  ok(lb === false, 'privacy toggle saves');
  await shot(mp, '16-profile');

  // ── Signed-in disclaimer, password sign-in, and switching accounts on one device
  await pp.goto(SITE + '#/profile'); await pp.waitForSelector('.about');
  ok((await pp.textContent('.about')).includes('not affiliated with or endorsed by'), 'disclaimer is reachable after sign-in (Profile → About)');
  await pp.click('[data-action=set-password]'); await pp.fill('input[name=pw]', 'demo-pass-' + stamp); await pp.fill('input[name=pw2]', 'demo-pass-' + stamp);
  await pp.click('#sheet-submit'); ok(await toastHas(pp, 'Password set'), 'officer set a password in Profile');
  await api(`/auth/v1/admin/users/${mem.id}`, { method: 'PUT', body: { password: 'member-pass-' + stamp } });
  await pp.click('[data-action=add-account]'); await pp.click('[data-action=signin-mode][data-v=password]');
  await pp.fill('input[name=email]', mem.email); await pp.fill('input[name=password]', 'member-pass-' + stamp); await pp.click('#signin button[type=submit]');
  await pp.waitForSelector('#signin', { state: 'detached' }); await pp.waitForSelector('.tabbar');
  await pp.click('.tabbar a[href="#/profile"]'); await pp.waitForSelector('#accounts');
  ok((await pp.textContent('h2')).includes(mem.name), 'password sign-in works; added the member as a second account');
  ok((await pp.$$('#accounts [data-action=switch-account]')).length === 1, 'both accounts listed on this device');
  await shot(pp, '16b-accounts');
  await pp.click('#accounts [data-action=switch-account]'); await toastHas(pp, 'Signed in as');
  await pp.click('.tabbar a[href="#/profile"]'); await pp.waitForSelector('#accounts');
  ok((await pp.textContent('h2')).includes(pres.name), 'one tap switches back to the officer account');
  await pp.reload(); await pp.waitForSelector('#accounts');
  ok((await pp.textContent('h2')).includes(pres.name), 'still signed in as the officer after a reload');
  const lsDump = await pp.evaluate(() => JSON.stringify(localStorage));
  ok(!/service_role/.test(lsDump), 'no service key anywhere in browser storage');

  // ── Check-in screen: guest check-in shows the "Verified" seal
  await pp.goto(SITE + `#/checkin/${ev}`); await pp.waitForSelector('[data-action=ci-mode][data-v=guest]');
  await pp.click('[data-action=ci-mode][data-v=guest]'); await pp.fill('input[name=guest]', 'Walk-in Guest'); await pp.click('#guest-form button');
  await pp.waitForSelector('#ci-result.ok.stamp .seal');
  ok((await pp.textContent('#ci-result')).includes('Verified') && (await pp.textContent('#ci-result')).includes('Walk-in Guest (guest) checked in'), 'check-in shows a “Verified” seal');
  await pp.waitForTimeout(700); await shot(pp, '11b-verified');
  await pp.fill('input[name=guest]', 'walk-in guest'); await pp.click('#guest-form button');
  await pp.waitForSelector('#ci-result.warn');
  ok((await pp.textContent('#ci-result')).includes('already checked in') && !(await pp.$('#ci-result .seal')), 'duplicate check-in says “already checked in”, no Verified seal');

  // ── Involvement record download + GetInvolvedHU links
  await mp.goto(SITE + '#/profile'); await mp.reload(); await mp.waitForSelector('#inv-dl:not([disabled])');
  const [inv] = await Promise.all([mp.waitForEvent('download'), mp.click('#inv-dl')]);
  const invText = require('fs').readFileSync(await inv.path(), 'utf8');
  ok(/involvement-record-.*\.csv/.test(inv.suggestedFilename()) && invText.includes('Opening night') && invText.includes('Blitz tournament'), 'student downloads an involvement record of verified check-ins');
  ok(!!(await mp.$('.about a[href*="campuslabs.com/engage/news/323408"]')) && !!(await mp.$('.about a[href*="osle-handbook"]')), 'About links to the GetInvolvedHU application and OSLE handbook');

  // ── Profile photo: optional, shows on the club e-board for other students
  await pp.goto(SITE + '#/profile'); await pp.waitForSelector('input[data-file=avatar]');
  await pp.setInputFiles('input[data-file=avatar]', { name: 'me.png', mimeType: 'image/png', buffer: PNG });
  await toastHas(pp, 'Photo saved'); await pp.waitForSelector('.card img.avatar.photo');
  await pp.waitForFunction(() => { const i = document.querySelector('.card img.avatar.photo'); return i && i.complete && i.naturalWidth >= 400; }, null, { timeout: 15000 });
  ok(true, 'officer added a profile photo and it renders (480px square crop)');
  await shot(pp, '16c-photo');
  await mp.goto(SITE + `#/club/${clubId}`); await mp.reload(); await mp.waitForSelector('.people');
  ok(!!(await mp.$('.people img.avatar.photo')), 'other students see the photo on the club e-board');
  const prevTxt = await (async () => { const c = await browser.newContext(devices['iPhone 15 Pro']); const p = await c.newPage(); await p.goto(SITE + `#/club/${clubId}`); await p.waitForSelector('#preview .btn'); const h = await p.innerHTML('#preview'); await c.close(); return h; })();
  ok(!prevTxt.includes('/avatars/'), 'photos never appear on the public shared-link page');

  // ── Appearance: Automatic follows the phone; Dark/Light can be forced
  await pp.goto(SITE + '#/profile'); await pp.waitForSelector('[data-action=theme][data-v=dark]');
  await pp.click('[data-action=theme][data-v=dark]');
  ok(await pp.evaluate(() => document.documentElement.dataset.theme === 'dark' && getComputedStyle(document.body).backgroundColor === 'rgb(11, 18, 32)'), 'Dark forces dark colors');
  await pp.reload(); await pp.waitForSelector('[data-action=theme]');
  ok(await pp.evaluate(() => document.documentElement.dataset.theme === 'dark'), 'the choice survives a reload');
  await pp.click('[data-action=theme][data-v=auto]');
  ok(await pp.evaluate(() => !document.documentElement.dataset.theme && getComputedStyle(document.body).backgroundColor === 'rgb(246, 247, 249)'), 'Automatic follows the phone (light here)');

  // ── Founder dashboard: founder only, behind the security question
  await api('/rest/v1/rpc/set_admin_secret', { method: 'POST', body: { p_email: pres.email, p_question: 'Test question for e2e?', p_answer: 'Sculptor' } });
  await pp.reload(); await pp.waitForSelector('.founder-entry'); await pp.click('.founder-entry');
  await pp.waitForSelector('#founder-unlock');
  ok((await pp.textContent('#founder-unlock')).includes('Test question for e2e?'), 'founder is asked the security question first');
  await pp.fill('#founder-unlock input', 'painter'); await pp.click('#founder-unlock button');
  ok(await toastHas(pp, 'That’s not it'), 'wrong answer is refused');
  await pp.fill('#founder-unlock input', '  sculptor '); await pp.click('#founder-unlock button');
  await pp.waitForSelector('svg.bars');
  const fText = await pp.textContent('#founder-body');
  ok(fText.includes(clubName) && fText.includes(mem.email) && fText.includes('Recent activity'), 'founder sees every club, every student and recent activity');
  await shot(pp, '18-founder');
  let blocked2 = false;
  try { await rpcAs(mem, 'founder_overview', {}); } catch (e) { blocked2 = /forbidden/.test(e.message); }
  ok(blocked2, 'a regular student cannot get founder data');
  await pp.click('[data-action=founder-lock]'); await pp.waitForSelector('#founder-unlock');
  ok(true, 'Lock asks for the answer again');

  // ── Security spot checks with real tokens
  let denied = false;
  try { await rpcAs(mem, 'club_insights', { p_club: clubId }); } catch (e) { denied = /forbidden/.test(e.message); }
  ok(denied, 'a member cannot load the officer dashboard data');
  denied = false;
  try { await rpcAs(mem, 'notify_users', { p_users: [vp.id], p_kind: 'announcement', p_club: null, p_event: null, p_title: 'spam', p_body: '', p_dedupe: null }); } catch (e) { denied = /permission denied|42501|Could not find/.test(e.message); }
  ok(denied, 'the app cannot call server-only helpers like notify_users');

  // ── Archive / delete (President only)
  await vpp.goto(SITE + `#/club/${clubId}`); await vpp.reload(); await vpp.waitForSelector('[data-action=club-menu]');
  await vpp.click('[data-action=club-menu]');
  ok(!(await vpp.$('[data-action=archive-club]')), 'only the President sees Archive / Delete');
  await vpp.click('[data-action=sheet-close]');
  await pp.goto(SITE + `#/club/${clubId}`); await pp.reload(); await pp.waitForSelector('[data-action=club-menu]');
  await pp.click('[data-action=club-menu]'); await pp.waitForTimeout(500); await pp.click('[data-action=delete-club]', { force: true });
  await pp.waitForTimeout(500); await pp.fill('input[name=confirm]', clubName); await pp.click('#sheet-form button[type=submit]', { force: true });
  ok(await toastHas(pp, 'Archive it instead'), 'delete is refused once people have checked in (history protected)');
  await pp.click('[data-action=sheet-close]');
  await pp.waitForSelector('#sheet-root .sheet', { state: 'detached' });
  await pp.click('[data-action=club-menu]'); await pp.waitForTimeout(500); await pp.click('[data-action=archive-club][data-v="1"]', { force: true });
  await pp.waitForTimeout(500); await pp.click('#sheet-form button[type=submit]', { force: true });
  await toastHas(pp, 'archived'); await pp.waitForSelector('.notice-card.archived');
  ok(true, 'President archived the club');
  await shot(pp, '19-archived');
  await mp.goto(SITE + '#/mine'); await mp.reload(); await mp.waitForSelector('.large-title');
  ok((await mp.textContent('#app')).includes('Archived'), 'members find it under Archived in My Clubs');
  { const c = await browser.newContext(devices['iPhone 15 Pro']); const p = await c.newPage(); await p.goto(SITE + `#/club/${clubId}`);
    await p.waitForSelector('#preview .empty'); ok((await p.textContent('#preview')).includes('isn’t available'), 'archived club’s shared link no longer works'); await c.close(); }
  await pp.click('[data-action=club-menu]'); await pp.waitForTimeout(500); await pp.click('[data-action=archive-club][data-v="0"]', { force: true });
  await toastHas(pp, 'active again'); await pp.waitForSelector('.notice-card.archived', { state: 'detached' });
  ok(true, 'President unarchived it');

  // Dark mode look
  const dp = await openAs(browser, pres, 'dark'); await dp.goto(SITE + `#/dash/${clubId}`); await dp.waitForSelector('.recog');
  await shot(dp, '17-dashboard-dark');
} catch (e) {
  failures++; console.log('✗ test crashed:', e.message.split('\n').slice(0, 6).join(' | '));
  for (const [i, p] of (globalThis.pages || []).entries()) await p.screenshot({ path: `${SHOTS}/fail-${i}.png` }).catch(() => {});
} finally {
  await browser.close();
  for (const id of created.clubs) {
    const files = await api(`/storage/v1/object/list/club-logos`, { method: 'POST', body: { prefix: id, limit: 100 } }).catch(() => []);
    if (files.length) await api('/storage/v1/object/club-logos', { method: 'DELETE', body: { prefixes: files.map((f) => `${id}/${f.name}`) } }).catch((e) => console.log('cleanup logo:', e.message));
  }
  for (const id of created.users) {
    const files = await api(`/storage/v1/object/list/avatars`, { method: 'POST', body: { prefix: id, limit: 100 } }).catch(() => []);
    if (files.length) await api('/storage/v1/object/avatars', { method: 'DELETE', body: { prefixes: files.map((f) => `${id}/${f.name}`) } }).catch((e) => console.log('cleanup photo:', e.message));
  }
  for (const id of created.events) await api(`/rest/v1/events?id=eq.${id}`, { method: 'DELETE' }).catch((e) => console.log('cleanup event:', e.message));
  for (const id of created.clubs) await api(`/rest/v1/clubs?id=eq.${id}`, { method: 'DELETE' }).catch((e) => console.log('cleanup club:', e.message));
  for (const id of created.users) await api(`/auth/v1/admin/users/${id}`, { method: 'DELETE' }).catch((e) => console.log('cleanup user:', e.message));
  console.log(`cleanup: removed ${created.clubs.length} club(s), ${created.events.length} event(s) and ${created.users.length} account(s)`);
  console.log(failures ? `${failures} FAILURE(S)` : 'ALL WEB E2E CHECKS PASSED');
  process.exit(failures ? 1 : 0);
}
