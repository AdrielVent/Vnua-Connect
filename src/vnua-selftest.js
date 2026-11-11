// In-browser regression checks (pass 4). Console: await vnuaSelfTest()   — resets the prototype.
// Preview-browser simulation only: not physical-device or assistive-technology testing.
window.vnuaSelfTest = async function () {
  const R = [];
  const ok = (n, c, d) => { R.push((c ? 'PASS' : 'FAIL') + ' · ' + n + (d !== undefined ? ' · ' + d : '')); try { sessionStorage.setItem('vnua_selftest_progress', JSON.stringify(R)); } catch (e) {} };
  const w = (ms) => new Promise((r) => setTimeout(r, ms));
  try { sessionStorage.setItem('vnua_selftest_progress', '["begin"]'); } catch (e) {}
  const all = () => [...document.querySelectorAll('button')];
  const btn = (t) => all().find((b) => b.textContent.trim().startsWith(t));
  const ex = (t) => all().find((b) => b.textContent.trim() === t);
  const inc = (t) => all().find((b) => b.textContent.includes(t));
  const txt = () => document.body.textContent;
  const until = async (fn, ms = 6000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (fn()) return true; await w(100); } return false; };
  const api = window.VnuaMockApi;
  const setVal = (el, v) => {
    const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  };
  const key = (k, shift) => document.dispatchEvent(new KeyboardEvent('keydown', { key: k, shiftKey: !!shift, bubbles: true }));
  const unnamed = () => [...document.querySelectorAll('button,input,select,textarea')].filter((e) => {
    const n = (e.getAttribute('aria-label') || e.textContent || '').trim();
    return !n && !(e.id && document.querySelector('label[for="' + e.id + '"]')) && !e.closest('label');
  }).length;
  const lum = (rgb) => { const c = rgb.match(/\d+/g).slice(0, 3).map((x) => { x /= 255; return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4); }); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
  const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
  const screen = () => document.querySelector('[aria-label="Screen content"]');
  const noOverflow = () => { const s = screen(); return s.scrollWidth <= s.clientWidth + 1; };
  const status = () => (document.querySelector('[aria-live=assertive]') || {}).textContent || '';
  const nav = (i) => [...document.querySelectorAll('nav[aria-label=Primary] button')][i].click();
  const trap = async (label) => {
    const d = document.querySelector('[role=dialog]');
    ok(label + ': opens', !!d);
    if (!d) return;
    await w(120);
    ok(label + ': focus moves inside', d.contains(document.activeElement));
    const f = [...d.querySelectorAll('button:not([disabled]),input:not([disabled]),select,textarea,a[href]')];
    f[f.length - 1].focus(); key('Tab'); ok(label + ': Tab wraps last→first', document.activeElement === f[0]);
    f[0].focus(); key('Tab', true); ok(label + ': Shift+Tab wraps first→last', document.activeElement === f[f.length - 1]);
  };
  try {
    for (const t of ['Review notes', 'Member app', 'Officer · 1280', 'Handoff']) { btn(t).click(); await w(250); const n = unnamed(); ok('No unnamed controls · ' + t, n === 0, n); }
    btn('Member app').click(); await w(200); btn('Reset prototype').click(); await w(250); btn('Member app').click(); await w(200);
    for (const px of ['320', '390', '430']) {
      btn(px + ' px').click(); await w(150);
      if (btn('Browse clubs and events')) { btn('Browse clubs and events').click(); await w(250); }
      ok(px + 'px Discover: no horizontal overflow', noOverflow());
    }
    btn('320 px').click(); await w(150);
    inc('Lowlight Drama Collective').click(); await w(250);
    ok('Club page leads with concise status, details collapsed', txt().includes('Student-led interest group') && !!document.querySelector('details:not([open])'));
    ex('Join club').click(); await w(250);
    ok('Join without account → sign-up', !!document.querySelector('#nm'));
    setVal(document.querySelector('#nm'), 'Test Student'); setVal(document.querySelector('#em'), 'not-an-email'); await w(60);
    btn('Send code').click(); await w(150);
    ok('Invalid email: text error + aria-invalid', /⚠/.test(document.querySelector('#emh').textContent) && document.querySelector('#em').getAttribute('aria-invalid') === 'true');
    setVal(document.querySelector('#em'), 'test@school.example'); await w(60); btn('Send code').click(); await w(250);
    btn('Verify').click(); await w(120); ok('Empty code error', /6-digit/.test(document.querySelector('#cdm').textContent));
    setVal(document.querySelector('#cd'), '111111'); await w(60); btn('Verify').click(); await w(120); ok('Wrong code error', /isn’t right/.test(document.querySelector('#cdm').textContent));
    setVal(document.querySelector('#cd'), '123456'); await w(60); btn('Verify').click(); await w(250);
    btn('Skip').click(); await w(250);
    inc('Harbor Street Pottery Circle').click(); await w(250);
    const help = () => inc('Help start or run this club');
    ok('“Join club” and “Help start or run” are separate actions', !!help() && !!ex('Join club'));
    help().click(); await w(200); await trap('Join dialog');
    key('Escape'); await w(250);
    ok('Esc closes dialog', !document.querySelector('[role=dialog]'));
    ok('Focus returns to trigger', document.activeElement === help());
    help().click(); await w(200); btn('Confirm').click(); await until(() => txt().includes('✓ Founding volunteer'));
    ok('Founding interest saved via adapter', txt().includes('✓ Founding volunteer'));
    const fr = await api.join({ clubId: 'x', userId: 't', role: 'officer', contact: 'events' });
    ok('Adapter rejects self-granted officer role', !fr.ok && fr.error.code === 'forbidden_role');
    nav(1); await w(250);
    api.failNext = true; ex('RSVP').click(); await until(() => txt().includes('Couldn’t save your RSVP'));
    ok('RSVP failure leaves state unchanged', !ex('Cancel RSVP') && !!ex('RSVP'));
    ex('RSVP').click(); await until(() => !!ex('Cancel RSVP'));
    ok('RSVP retry succeeds', !!ex('Cancel RSVP'));
    ok('320px Events: long title no overflow', noOverflow());
    const pb = document.querySelector('.btn-primary'); if (pb) { const r = ratio(getComputedStyle(pb).color, getComputedStyle(pb).backgroundColor); ok('Primary button contrast ≥ 4.5', r >= 4.5, r.toFixed(2)); }
    const a1 = await api.checkIn({ eventId: 'tx', attendeeKey: 'A', requestId: 'q1' });
    const a2 = await api.checkIn({ eventId: 'tx', attendeeKey: 'A', requestId: 'q1' });
    ok('Idempotency: same requestId returns same record', a1.ok && a2.ok && a1.data.recordId === a2.data.recordId && a2.data.status === 'recorded');
    const a3 = await api.checkIn({ eventId: 'tx', attendeeKey: 'A', requestId: 'q2' });
    ok('Uniqueness: new requestId, same attendee → duplicate', a3.ok && a3.data.status === 'duplicate');
    await api.setRsvp({ eventId: 'tx', userId: 'A', going: false, requestId: 'r1' });
    const a4 = await api.checkIn({ eventId: 'tx', attendeeKey: 'A', requestId: 'q3' });
    ok('Canceling RSVP does not erase attendance', a4.data.status === 'duplicate');
    nav(2); await w(200);
    ok('Officer tools only for the officer’s club', !!inc('Officer tools · Lowlight') && !inc('Officer tools · Harbor'));
    nav(0); await w(200); inc('Lowlight Drama Collective').click(); await w(250);
    btn('Check in arrivals').click(); await w(250);
    ok('Mobile officer check-in opens', txt().includes('Find member by name'));
    ok('320px mobile check-in: no overflow', noOverflow());
    inc('Scan a member').click(); await until(() => status().includes('✓ Recorded'));
    ok('Mobile scan → Recorded after adapter', status().includes('✓ Recorded'));
    setVal(document.querySelector('#mlm'), 'Rowan'); await w(100); ex('Check in').click(); await until(() => status().includes('Already checked in'));
    ok('Manual check-in of same person → Already checked in', status().includes('Already checked in'));
    btn('Make next request fail').click(); await w(50); inc('Scan a member').click(); await until(() => !!ex('Retry'));
    ok('Failed request → Not confirmed + Retry', status().includes('Not confirmed') && !!ex('Retry'));
    ex('Retry').click(); await until(() => status().includes('✓ Recorded'));
    ok('Retry with same requestId → Recorded', status().includes('✓ Recorded'));
    btn('Camera denied').click(); await w(150);
    ok('Camera denied → manual fallback message', status().includes('Camera unavailable'));
    btn('Go offline').click(); await w(100); inc('Scan a member').click(); await w(150);
    ok('Offline → not recorded, paper fallback', status().includes('Offline')); btn('Go online').click(); await w(100);
    btn('Officer · 1280').click(); await w(250);
    if (document.querySelector('#clubsel').value !== 'drama') { const s = document.querySelector('#clubsel'); Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set.call(s, 'drama'); s.dispatchEvent(new Event('change', { bubbles: true })); await w(200); }
    btn('Attendance & download').click(); await w(200);
    const before = document.querySelectorAll('table tbody tr').length;
    btn('Event scanner').click(); await w(150);
    btn('Recorded').click(); btn('Recorded').click(); await w(200); await until(() => !status().includes('Recording…'));
    btn('Attendance & download').click(); await w(200);
    const after = document.querySelectorAll('table tbody tr').length;
    ok('Double-click scan records exactly once', after === before + 1, before + '→' + after);
    all().find((b) => b.textContent.includes('Correct') && !b.disabled).click(); await w(250);
    btn('Remove record').click(); await w(200);
    ok('Correction without reason is blocked', /reason/i.test(document.querySelector('#fxe').textContent));
    setVal(document.querySelector('#fxr'), 'Scanned wrong person'); await w(60); btn('Remove record').click(); await until(() => !document.querySelector('[role=dialog]'));
    ok('Correction saved via adapter, audit kept', txt().includes('Reason: Scanned wrong person') && txt().includes('Removed'));
    btn('Download attendance').click(); await w(200); await trap('Download dialog'); key('Escape'); await w(200);
    ok('Download dialog: focus returns', !!document.activeElement && document.activeElement.textContent.includes('Download attendance'));
    const sel = document.querySelector('#clubsel'); Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set.call(sel, 'rocket'); sel.dispatchEvent(new Event('change', { bubbles: true })); await w(200);
    ok('Non-officer club → restricted', txt().includes('Restricted access'));
  } catch (e) { R.push('ERROR · ' + e.message); }
  console.log('VNUA SELFTEST ' + R.filter((r) => r.startsWith('PASS')).length + '/' + R.length + '\n' + R.join('\n'));
  return R;
};
