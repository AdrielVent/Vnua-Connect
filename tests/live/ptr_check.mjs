// Pull-to-refresh in "Home Screen app" mode: success says "Up to date", a failed reload says so, a sideways swipe does nothing,
// and the indicator never gets stuck. (Emulates standalone mode + touch events in WebKit; not a physical iPhone.)
import { webkit, devices } from 'playwright';
const U = process.env.SB_URL, A = process.env.SB_ANON, S = process.env.SB_SERVICE, SITE = process.env.SITE;
const REF = new URL(U).hostname.split('.')[0];
const api = async (p, o = {}) => { const r = await fetch(U + p, { method: o.method || 'GET', headers: { apikey: o.key || S, Authorization: `Bearer ${o.token || o.key || S}`, 'Content-Type': 'application/json' }, body: o.body && JSON.stringify(o.body) }); const t = await r.text(); if (!r.ok) throw new Error(t); return t ? JSON.parse(t) : null; };
let fails = 0; const ok = (c, m) => { console.log(`${c ? '✓' : '✗'} ${m}`); if (!c) fails++; };
const email = `vnua-ptr-${Date.now().toString(36)}@pride.hofstra.edu`;
const user = await api('/auth/v1/admin/users', { method: 'POST', body: { email, email_confirm: true } });
const browser = await webkit.launch();
try {
  const link = await api('/auth/v1/admin/generate_link', { method: 'POST', body: { type: 'magiclink', email } });
  const session = await api('/auth/v1/verify', { method: 'POST', key: A, body: { type: 'magiclink', token_hash: link.hashed_token ?? link.properties?.hashed_token } });
  await api('/rest/v1/rpc/save_profile', { method: 'POST', key: A, token: session.access_token, body: { p_name: 'Pull Tester', p_major: '', p_year: 'Junior', p_pronouns: '', p_interests: ['Games'], p_bio: '', p_phone: '', p_linkedin: '', p_share_email: false, p_share_phone: false, p_share_linkedin: false, p_discoverable: false, p_leaderboard: true } });
  const ctx = await browser.newContext({ ...devices['iPhone 15 Pro'] });
  await ctx.addInitScript(([k, v]) => { localStorage.setItem(k, v); Object.defineProperty(navigator, 'standalone', { get: () => true }); }, [`sb-${REF}-auth-token`, JSON.stringify(session)]);
  const p = await ctx.newPage(); p.on('pageerror', (e) => { console.log('page error', e.message); fails++; });
  await p.goto(SITE + '#/events'); await p.waitForSelector('[data-action=ev-scope]');
  const gesture = (dx, dy) => p.evaluate(([dx, dy]) => {
    // Desktop WebKit can't construct Touch objects, so dispatch events carrying the same touch data the app reads.
    const fire = (type, x, y) => { const ev = new Event(type, { bubbles: true });
      Object.defineProperty(ev, 'touches', { value: type === 'touchend' ? [] : [{ clientX: x, clientY: y }] }); document.dispatchEvent(ev); };
    fire('touchstart', 150, 120); fire('touchmove', 150 + dx / 2, 120 + dy / 2); fire('touchmove', 150 + dx, 120 + dy); fire('touchend', 150 + dx, 120 + dy);
  }, [dx, dy]);
  const toastText = async () => { await p.waitForFunction(() => document.querySelector('#toast.show'), null, { timeout: 15000 }); return p.textContent('#toast'); };
  await gesture(0, 140);
  ok((await toastText()).includes('Up to date'), 'pull down → reloads → "Up to date"');
  await p.waitForFunction(() => !document.querySelector('.ptr'));
  ok(true, 'indicator removed after success');
  await p.waitForTimeout(3500);
  await p.route('**/rest/v1/**', (r) => r.abort());
  await gesture(0, 140);
  ok((await toastText()).includes('Couldn’t refresh'), 'failed reload → says it couldn’t refresh (never "Up to date")');
  await p.waitForFunction(() => !document.querySelector('.ptr'));
  ok(true, 'indicator removed after failure');
  await p.unroute('**/rest/v1/**'); await p.waitForTimeout(3500);
  await gesture(160, 60);
  await p.waitForTimeout(800);
  ok(!(await p.$('.ptr')) && !(await p.$('#toast.show')), 'sideways swipe is not a pull (no indicator, no refresh)');
} catch (e) { fails++; console.log('✗ crashed:', e.message.slice(0, 300)); }
finally { await browser.close(); await api(`/auth/v1/admin/users/${user.id}`, { method: 'DELETE' }).catch(() => {}); console.log(fails ? `${fails} FAILURE(S)` : 'PULL-TO-REFRESH CHECKS PASSED'); process.exit(fails ? 1 : 0); }
