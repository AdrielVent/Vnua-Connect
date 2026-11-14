/* Vnua-connect web app. Same backend and rules as the iPhone app (supabase/migrations).
   Plain JavaScript, no build step: GitHub Pages serves these files as they are. */
(() => {
  'use strict';
  const CFG = window.VNUA_CONFIG;
  const sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey, {
    auth: { flowType: 'pkce', detectSessionInUrl: true, persistSession: true, autoRefreshToken: true },
  });
  const HERE = location.origin + location.pathname;          // email link comes back here

  // ───────────── State ─────────────
  const S = {
    booting: true, user: null, clubs: [], events: [], memberships: {}, rsvps: new Set(), blocked: new Set(),
    q: '', interest: null, evScope: 'all', signin: { name: '', email: '', sent: false, busy: false },
  };
  let cleanup = [];                    // timers / camera for the current screen
  const $ = (sel, root = document) => root.querySelector(sel);

  // ───────────── Helpers ─────────────
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0; return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  }));
  const fmt = {
    day: (d) => d.toLocaleDateString(undefined, { weekday: 'long', month: 'short', day: 'numeric' }),
    time: (d) => d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' }),
    full: (d) => d.toLocaleString(undefined, { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }),
    dow: (d) => d.toLocaleDateString(undefined, { weekday: 'short' }).toUpperCase(),
    rel: (d) => { const m = Math.round((Date.now() - d) / 60000); return m < 60 ? `${Math.max(m, 1)} min ago` : m < 1440 ? `${Math.round(m / 60)} hr ago` : `${Math.round(m / 1440)} d ago`; },
  };
  const sameDay = (a, b) => a.toDateString() === b.toDateString();

  /** Database functions raise 'code|Human message'. Show only the human part. */
  function errMsg(e) {
    const m = (e && (e.message || e.error_description || e.msg)) || String(e);
    if (/failed to fetch|network|load failed/i.test(m)) return 'No connection. Check your internet and try again.';
    const i = m.indexOf('|');
    return i > 0 ? m.slice(i + 1) : m;
  }
  async function q(promise) { const { data, error } = await promise; if (error) throw error; return data; }
  const rpc = (fn, params) => q(sb.rpc(fn, params));

  let toastTimer;
  function toast(msg, isError = false) {
    const t = $('#toast');
    t.textContent = msg; t.className = 'show' + (isError ? ' error' : '');
    clearTimeout(toastTimer); toastTimer = setTimeout(() => { t.className = isError ? 'error' : ''; }, 2800);
  }
  /** Runs an async action; shows any error as a toast. Returns undefined on failure. */
  async function run(fn) { try { return await fn(); } catch (e) { console.error(e); toast(errMsg(e), true); return undefined; } }

  // ───────────── Derived ─────────────
  const club = (id) => S.clubs.find((c) => c.id === id);
  const event = (id) => S.events.find((e) => e.id === id);
  const membership = (id) => S.memberships[id];
  const isOfficer = (clubId) => membership(clubId)?.role === 'officer' && membership(clubId)?.status === 'active';
  const runsEvent = (e) => e.hosts.some(isOfficer);
  const visibleClubs = () => S.clubs.filter((c) => !S.blocked.has(c.id));
  const visibleEvents = () => S.events.filter((e) => !e.hosts.every((h) => S.blocked.has(h)));
  const hostNames = (e) => e.hosts.map((h) => club(h)?.name).filter(Boolean).join(' + ');
  const interests = () => [...new Set(S.clubs.map((c) => c.interest))].sort();
  const recogLabel = { recognized: 'Recognized', not_recognized: 'Not yet recognized', not_stated: 'Status not stated' };
  const roleLabel = { member: 'Member', founding: 'Founding member', officer: 'Officer' };
  const contactLabel = { none: "Don't email me", events: 'Event updates only', organizing: 'Events and organizing' };

  // ───────────── Data ─────────────
  async function loadProfile(userId) {
    return q(sb.from('profiles').select('*').eq('id', userId).single());
  }
  async function loadAll() {
    const me = S.user.id, campus = S.user.campus_id;
    const [clubs, officers, events, ms, rs, bl] = await Promise.all([
      q(sb.from('clubs').select('*').eq('campus_id', campus).order('name')),
      q(sb.from('club_officers').select('*')),
      q(sb.from('events').select('*, event_hosts(club_id)').eq('campus_id', campus).order('starts_at')),
      q(sb.from('memberships').select('*').eq('user_id', me)),
      q(sb.from('rsvps').select('event_id').eq('user_id', me)),
      q(sb.from('club_blocks').select('club_id')),
    ]);
    S.clubs = clubs.map((c) => ({ ...c, officers: officers.filter((o) => o.club_id === c.id) }));
    S.events = events.map((e) => ({ ...e, start: new Date(e.starts_at), hosts: e.event_hosts.map((h) => h.club_id),
      end: new Date(new Date(e.starts_at).getTime() + e.duration_minutes * 60000) }));
    S.memberships = Object.fromEntries(ms.map((m) => [m.club_id, m]));
    S.rsvps = new Set(rs.map((r) => r.event_id));
    S.blocked = new Set(bl.map((b) => b.club_id));
  }
  async function refresh() { await run(loadAll); render(); }

  // ───────────── Icons ─────────────
  const icon = {
    discover: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m20 20-4.8-4.8"/></svg>',
    events: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3.5" y="5" width="17" height="15" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4"/></svg>',
    clubs: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="8" cy="9" r="3"/><circle cx="16.5" cy="9" r="3"/><path d="M2.5 19c.7-3 3-4.5 5.5-4.5s4.8 1.5 5.5 4.5M12 19c.6-2.6 2.4-4.3 4.5-4.3s3.9 1.7 4.5 4.3"/></svg>',
    profile: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="10" r="3"/><path d="M6.5 18.5c1.3-2 3.2-3 5.5-3s4.2 1 5.5 3"/></svg>',
  };

  // ───────────── Router ─────────────
  // #/discover  #/events  #/mine  #/profile  #/club/:id  #/event/:id  #/pass/:id  #/checkin/:id
  function route() {
    const [, name = 'discover', id] = (location.hash || '#/discover').split('/');
    return { name, id };
  }
  window.addEventListener('hashchange', () => { closeSheet(); render(); window.scrollTo(0, 0); });

  function render() {
    cleanup.forEach((f) => f()); cleanup = [];
    const app = $('#app');
    if (S.booting) { app.innerHTML = '<div class="boot"><div class="spinner" role="status" aria-label="Loading"></div></div>'; return; }
    if (!S.user) { app.innerHTML = signInView(); bindSignIn(); return; }
    const r = route();
    const views = { discover: discoverView, events: eventsView, mine: mineView, profile: profileView,
      club: clubView, event: eventView, pass: passView, checkin: checkinView };
    const view = views[r.name] || discoverView;
    const tabs = ['discover', 'events', 'mine', 'profile'].includes(r.name) || !views[r.name];
    app.innerHTML = `<main class="screen${tabs ? '' : ' no-tabs'}">${view(r.id)}</main>${tabs ? tabbar(r.name) : ''}`;
    after[r.name]?.(r.id);
  }
  const after = {};                    // per-screen setup after HTML is in the DOM

  function tabbar(active) {
    const t = (id, label) => `<a href="#/${id}" ${active === id ? 'aria-current="page"' : ''}>${icon[id === 'mine' ? 'clubs' : id]}<span>${label}</span></a>`;
    return `<nav class="tabbar" aria-label="Main">${t('discover', 'Discover')}${t('events', 'Events')}${t('mine', 'My Clubs')}${t('profile', 'Profile')}</nav>`;
  }
  const back = (href, label = 'Back') => `<div class="topbar"><a class="back" href="${href}">‹ ${esc(label)}</a><span class="spacer"></span>`;

  // ───────────── Pieces ─────────────
  const mono = (c, size = 48) => `<div class="mono" aria-hidden="true" style="width:${size}px;height:${size}px;font-size:${Math.round(size * .38)}px;background:${esc(c.accent_hex)}">${esc(c.monogram)}</div>`;
  const badge = (text, tone = '') => `<span class="badge ${tone}">${esc(text)}</span>`;
  function clubBadges(c) {
    const m = membership(c.id);
    return `<div class="badges">${badge(c.interest)}${!c.is_published ? badge('⏳ In review', 'warning') : ''}${
      m ? (m.status === 'pending' ? badge('Requested', 'warning') : badge('✓ ' + roleLabel[m.role], 'success')) : ''}</div>`;
  }
  const clubRow = (c) => `<a class="card club-row" href="#/club/${c.id}">${mono(c)}<div class="spacer"><div class="name">${esc(c.name)}</div>
    <div class="blurb">${esc(c.blurb)}</div>${clubBadges(c)}</div><span class="chev">›</span></a>`;
  function statusBadge(e) {
    return e.status === 'rescheduled' ? badge('↻ Rescheduled', 'warning') : e.status === 'cancelled' ? badge('✕ Cancelled', 'warning') : '';
  }
  const eventRow = (e) => `<a class="card row${e.status === 'cancelled' ? ' cancelled' : ''}" href="#/event/${e.id}" style="align-items:flex-start">
    <div class="date-chip"><span class="dow">${fmt.dow(e.start)}</span><span class="day">${e.start.getDate()}</span></div>
    <div class="spacer"><div class="event-title">${esc(e.title)}</div>
    <div class="muted" style="font-size:15px">${fmt.time(e.start)}${e.location ? ' · ' + esc(e.location) : ''}</div>
    <div class="footnote">${esc(hostNames(e))}</div>
    <div class="badges">${statusBadge(e)}${S.rsvps.has(e.id) ? badge('✓ Going', 'success') : ''}</div></div></a>`;
  const eventCard = (e) => `<a class="card" href="#/event/${e.id}"><div class="kicker">${esc(fmt.day(e.start))}</div>
    <div class="event-title" style="margin:6px 0;min-height:2.8em">${esc(e.title)}</div>
    <div class="footnote" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${fmt.time(e.start)} · ${esc(e.location)}</div>
    ${S.rsvps.has(e.id) ? `<div class="badges">${badge('✓ Going', 'success')}</div>` : ''}</a>`;

  // ───────────── Sign in ─────────────
  function signInView() {
    const s = S.signin;
    return `<main class="screen no-tabs" style="max-width:520px"><div class="stack-l" style="padding-top:48px">
      <div class="stack">
        <div style="width:56px;height:56px;color:var(--accent)" aria-hidden="true">${icon.clubs.replace('stroke-width="2"', 'stroke-width="2.2"')}</div>
        <h1 class="large-title" style="margin:0">Vnua-connect</h1>
        <p class="muted">Giving clubs a chance. Find new student groups at ${esc(CFG.campus.name)}, join or help found one, and check in at events.</p>
      </div>
      <form id="signin" class="stack" novalidate>
        <label class="field"><span>Your name</span><input class="input" name="name" autocomplete="name" value="${esc(s.name)}" ${s.sent ? 'disabled' : ''} required></label>
        <label class="field"><span>School email</span><input class="input" name="email" type="email" inputmode="email" autocomplete="email"
          autocapitalize="off" spellcheck="false" placeholder="you@pride.hofstra.edu" value="${esc(s.email)}" ${s.sent ? 'disabled' : ''} required></label>
        ${s.sent ? `<div class="card stack"><p><strong>Check ${esc(s.email)}.</strong></p>
          <p class="muted" style="font-size:15px">Open the email <strong>in this browser</strong> and tap the link. If your email shows a code instead, type it here.</p>
          <label class="field"><span>Code (optional)</span><input class="input" name="code" inputmode="numeric" autocomplete="one-time-code" maxlength="8"></label></div>` : ''}
        <button class="btn primary" type="submit" ${s.busy ? 'disabled' : ''}>${s.busy ? 'Working…' : s.sent ? 'Verify code' : 'Email me a sign-in link'}</button>
        ${s.sent ? '<button class="btn secondary" type="button" data-action="signin-reset">Use a different email</button>' : ''}
      </form>
      <p class="footnote">Vnua-connect is student-run and not affiliated with or endorsed by ${esc(CFG.campus.name)}.
        Use the email on the device you'll open it on. Codes and links expire after 10 minutes.</p>
    </div></main>`;
  }
  const campusAllows = (email) => {
    const d = (email.split('@')[1] || '').toLowerCase();
    return CFG.campus.emailDomains.some((x) => d === x || d.endsWith('.' + x));
  };
  function bindSignIn() {
    $('#signin').addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const f = ev.target, s = S.signin;
      if (!s.sent) {
        s.name = f.name.value.trim(); s.email = f.email.value.trim().toLowerCase();
        if (!s.name) return toast('Enter your name.', true);
        if (!campusAllows(s.email)) return toast(`Use your ${CFG.campus.name} email address.`, true);
        s.busy = true; render();
        const ok = await run(() => q(sb.auth.signInWithOtp({ email: s.email,
          options: { shouldCreateUser: true, data: { name: s.name }, emailRedirectTo: HERE } })).then(() => true));
        s.busy = false; if (ok) s.sent = true; render();
      } else {
        const code = (f.code?.value || '').trim();
        if (!/^\d{6,8}$/.test(code)) return toast('Tap the link in the email, or enter the code it shows.', true);
        s.busy = true; render();
        await run(() => q(sb.auth.verifyOtp({ email: s.email, token: code, type: 'email' })));
        s.busy = false; render();                 // onAuthStateChange signs in
      }
    });
  }

  // ───────────── Discover ─────────────
  function discoverView() {
    const chips = [`<button class="chip" data-action="interest" data-v="" aria-pressed="${!S.interest}">All</button>`]
      .concat(interests().map((i) => `<button class="chip" data-action="interest" data-v="${esc(i)}" aria-pressed="${S.interest === i}">${esc(i)}</button>`)).join('');
    return `<h1 class="large-title">Discover</h1><div class="stack-l">
      <label class="search"><span class="sr">Search clubs</span><input class="input" id="search" type="search" placeholder="Clubs and interests" value="${esc(S.q)}" autocomplete="off"></label>
      <div class="chips" role="group" aria-label="Interests">${chips}</div>
      <div id="discover-body" class="stack-l">${discoverBody()}</div></div>`;
  }
  function discoverBody() {
    const ql = S.q.toLowerCase();
    const list = visibleClubs().filter((c) => (!S.interest || c.interest === S.interest) &&
      (!ql || [c.name, c.blurb, c.interest].some((t) => t.toLowerCase().includes(ql))));
    const soon = visibleEvents().filter((e) => e.status !== 'cancelled' && e.end > new Date()).slice(0, 5);
    return `${!S.q && !S.interest && soon.length ? `<div class="section-header">Happening soon</div><div class="hscroll">${soon.map(eventCard).join('')}</div>` : ''}
      <div class="section-header">${esc(S.interest || 'All clubs')}</div>
      <div class="stack">${list.map(clubRow).join('') || `<div class="empty"><h2>${S.clubs.length ? 'No matches' : 'No clubs yet'}</h2>
        <p>${S.clubs.length ? 'Try a different search.' : 'Be the first: start a club from My Clubs.'}</p></div>`}</div>`;
  }
  after.discover = () => {
    const s = $('#search');
    s?.addEventListener('input', () => { S.q = s.value; $('#discover-body').innerHTML = discoverBody(); });
  };

  // ───────────── Club ─────────────
  function clubView(id) {
    const c = club(id);
    if (!c) return `${back('#/discover', 'Discover')}</div><div class="empty"><h2>Club not found</h2><p>It may have been removed or blocked.</p></div>`;
    const m = membership(c.id), officer = isOfficer(c.id);
    const evs = S.events.filter((e) => e.hosts.includes(c.id));
    const memberCard = m ? `<div class="card stack">
        ${m.status === 'pending' ? `<p class="notice warning">⏳ Join request sent. An officer will review it.</p>`
          : `<p style="color:var(--success);font-weight:600">✓ You're ${m.role === 'officer' ? 'an' : 'a'} ${esc(roleLabel[m.role].toLowerCase())}</p>`}
        <label class="field"><span>Emails from this club</span><select class="input" data-change="contact" data-club="${c.id}">
          ${Object.entries(contactLabel).map(([k, v]) => `<option value="${k}" ${m.contact === k ? 'selected' : ''}>${v}</option>`).join('')}</select></label>
        <button class="link-btn danger" data-action="leave" data-club="${c.id}" style="justify-self:start">${m.status === 'pending' ? 'Cancel request' : 'Leave club'}</button></div>`
      : `<div class="card stack"><button class="btn primary" data-action="join" data-club="${c.id}">${c.requires_approval ? 'Request to join' : 'Join club'}</button>
        ${c.requires_approval ? '<p class="footnote">Officers approve new members for this club.</p>' : ''}</div>`;
    return `${back('#/discover', 'Discover')}<button class="icon-btn" data-action="club-menu" data-club="${c.id}" aria-label="More">⋯</button></div>
      <div class="stack-l">
        <div class="stack" style="gap:10px">${mono(c, 72)}<h1 style="font-size:28px;font-weight:800">${esc(c.name)}</h1>
          <p class="muted">${esc(c.blurb)}</p><div class="badges">${badge(c.interest)}${badge((c.recognition === 'recognized' ? '✓ ' : '') + recogLabel[c.recognition], c.recognition === 'recognized' ? 'success' : '')}${c.funded ? badge('Funded', 'accent') : ''}</div></div>
        ${!c.is_published ? '<div class="card notice warning">⏳ Only you and your members can see this club until a moderator reviews it.</div>' : ''}
        ${memberCard}
        ${officer ? `<button class="btn primary" data-action="new-event" data-club="${c.id}">＋ New event</button><div class="card stack" id="join-requests"><div class="section-header">Join requests</div><p class="footnote">Loading…</p></div>` : ''}
        ${c.about || c.affiliation ? `<div class="card stack"><div class="section-header">About</div>${c.about ? `<p>${esc(c.about)}</p>` : ''}${c.affiliation ? `<p class="footnote">🔗 ${esc(c.affiliation)}</p>` : ''}</div>` : ''}
        ${c.officers.length ? `<div class="card stack"><div class="section-header">Officers</div>${c.officers.map((o) => `<div><div style="font-weight:600;font-size:15px">${esc(o.name)} · ${esc(o.title)}</div>${o.ask_about ? `<div class="footnote">Ask about: ${esc(o.ask_about)}</div>` : ''}</div>`).join('')}</div>` : ''}
        <div class="stack"><div class="section-header">Events</div>${evs.map(eventRow).join('') || '<p class="muted" style="font-size:15px">No upcoming events</p>'}</div>
      </div>`;
  }
  after.club = async (id) => {
    if (!isOfficer(id)) return;
    const box = $('#join-requests'); if (!box) return;
    const reqs = await run(() => rpc('join_requests', { p_club: id }));
    if (!reqs || !$('#join-requests')) return;
    box.innerHTML = `<div class="section-header">Join requests · ${reqs.length}</div>${reqs.length ? reqs.map((r) => `<div class="list-row">
      <div class="spacer"><div style="font-weight:600">${esc(r.name)}</div><div class="footnote">${esc(roleLabel[r.role])} · ${fmt.rel(new Date(r.requested_at))}</div></div>
      <button class="btn secondary small" data-action="review" data-club="${id}" data-user="${r.user_id}" data-approve="0" aria-label="Decline ${esc(r.name)}">✕</button>
      <button class="btn primary small" data-action="review" data-club="${id}" data-user="${r.user_id}" data-approve="1" aria-label="Approve ${esc(r.name)}">✓</button></div>`).join('')
      : '<p class="footnote">No one is waiting.</p>'}`;
  };

  // ───────────── Events ─────────────
  function eventsView() {
    const list = visibleEvents().filter((e) => S.evScope === 'all' ? true
      : S.evScope === 'mine' ? e.hosts.some((h) => membership(h)?.status === 'active') : S.rsvps.has(e.id));
    const days = [];
    list.forEach((e) => { const last = days[days.length - 1]; if (last && sameDay(last[0], e.start)) last[1].push(e); else days.push([e.start, [e]]); });
    const seg = (v, l) => `<button data-action="ev-scope" data-v="${v}" aria-pressed="${S.evScope === v}">${l}</button>`;
    return `<h1 class="large-title">Events</h1><div class="stack-l">
      <div class="segmented" role="group" aria-label="Show">${seg('all', 'All events')}${seg('mine', 'My clubs')}${seg('going', 'Going')}</div>
      ${days.map(([d, evs]) => `<div class="stack"><div class="section-header">${sameDay(d, new Date()) ? 'Today' : esc(fmt.day(d))}</div>${evs.map(eventRow).join('')}</div>`).join('')
        || '<div class="empty"><h2>No events</h2><p>Join a club or RSVP to see events here.</p></div>'}</div>`;
  }

  function eventView(id) {
    const e = event(id);
    if (!e) return `${back('#/events', 'Events')}</div><div class="empty"><h2>Event not found</h2></div>`;
    const going = S.rsvps.has(e.id), live = e.status !== 'cancelled';
    return `${back('#/events', 'Events')}<button class="icon-btn" data-action="report" data-type="event" data-id="${e.id}" data-name="${esc(e.title)}" aria-label="Report event">⚑</button></div>
      <div class="stack-l">
        <div class="stack" style="gap:8px">${statusBadge(e) ? `<div>${statusBadge(e)}</div>` : ''}
          <h1 style="font-size:28px;font-weight:800">${esc(e.title)}</h1>
          <div style="color:var(--accent);font-weight:600;font-size:15px">${e.hosts.map((h) => club(h) ? `<a href="#/club/${h}" style="text-decoration:none">${esc(club(h).name)}</a>` : '').join(' + ')}</div></div>
        ${e.status === 'rescheduled' && e.previous_start ? `<p class="notice warning">ℹ︎ Moved from ${esc(fmt.full(new Date(e.previous_start)))}</p>` : ''}
        ${!live ? '<p class="notice warning"><strong>This event was cancelled.</strong></p>' : ''}
        <div class="card stack"><div>🕒 ${esc(fmt.full(e.start))}</div>${e.location ? `<div>📍 ${esc(e.location)}</div>` : ''}<div>👤 Organized by ${esc(e.organizer)}</div></div>
        ${e.details ? `<p>${esc(e.details)}</p>` : ''}
        ${live ? `<div class="stack">
          <button class="btn ${going ? 'secondary' : 'primary'}" data-action="rsvp" data-id="${e.id}" aria-pressed="${going}">${going ? '✓ Going' : '✋ RSVP'}</button>
          <a class="btn secondary" href="#/pass/${e.id}">▦ Show my check-in pass</a>
          <button class="btn secondary" data-action="ics" data-id="${e.id}">📅 Add to Calendar</button></div>` : ''}
        ${runsEvent(e) ? `<div class="stack"><div class="section-header">Officer tools</div>
          <a class="btn primary" href="#/checkin/${e.id}">Run check-in</a>
          ${live ? `<button class="btn danger" data-action="cancel-event" data-id="${e.id}">Cancel event</button>` : ''}</div>` : ''}
      </div>`;
  }

  // ───────────── Pass ─────────────
  function passView(id) {
    const e = event(id);
    return `${back(`#/event/${id}`, 'Event')}</div><div class="stack-l" style="text-align:center;padding-top:16px">
      <div><h1 style="font-size:22px;font-weight:800">${esc(S.user.name)}</h1><p class="muted" style="font-size:15px">${esc(e?.title || '')}</p></div>
      <div class="qr" id="qr"><div class="spinner"></div></div>
      <p class="footnote" id="pass-timer" style="font-variant-numeric:tabular-nums">&nbsp;</p>
      <p class="footnote">Show this to an officer at the door. It refreshes every 45 seconds and only works for this event.</p></div>`;
  }
  after.pass = (id) => {
    let pass = null, alive = true;
    const draw = (token) => {
      const qr = window.qrcode(0, 'M'); qr.addData(token); qr.make();
      $('#qr').innerHTML = `<img alt="Check-in code" src="${qr.createDataURL(10, 0)}">`;
    };
    const issue = async () => {
      const p = await run(() => rpc('issue_pass', { p_event: id }));
      if (!alive) return;
      if (p) { pass = { token: p.token, exp: new Date(p.expires_at) }; draw(pass.token); }
    };
    const tick = setInterval(() => {
      if (!pass) return;
      const left = Math.max(0, Math.ceil((pass.exp - Date.now()) / 1000));
      const t = $('#pass-timer'); if (t) t.textContent = `↻ Refreshes in ${left}s`;
      if (left <= 2) { pass = null; issue(); }
    }, 1000);
    issue();
    cleanup.push(() => { alive = false; clearInterval(tick); });
  };

  // ───────────── Officer check-in ─────────────
  let ci = { mode: 'scan', records: [], last: null };
  function checkinView(id) {
    const e = event(id);
    if (!e || !runsEvent(e)) return `${back(`#/event/${id}`, 'Event')}</div><div class="empty"><h2>Officers only</h2><p>Only this club's officers can run check-in.</p></div>`;
    const seg = (v, l) => `<button data-action="ci-mode" data-v="${v}" aria-pressed="${ci.mode === v}">${l}</button>`;
    return `${back(`#/event/${id}`, 'Event')}<button class="link-btn" data-action="csv" data-id="${id}">Export CSV</button></div>
      <h1 style="font-size:28px;font-weight:800;margin:8px 0 4px">Check-in</h1><p class="muted" style="font-size:15px;margin-bottom:16px">${esc(e?.title || '')}</p>
      <div class="stack-l"><div class="segmented" role="group" aria-label="Mode">${seg('scan', 'Scan')}${seg('lookup', 'Look up')}${seg('guest', 'Guest')}</div>
        <div id="ci-mode">${ciModeHTML()}</div>
        <p class="result" id="ci-result" aria-live="assertive"></p>
        <div class="card"><div class="section-header" id="ci-count">Checked in</div><div id="ci-list"><p class="footnote" style="padding-top:12px">Loading…</p></div></div>
        <p class="footnote">Corrections need a reason, and the original record is kept.</p></div>`;
  }
  function ciModeHTML() {
    if (ci.mode === 'scan') return `<div class="scanner"><video id="cam" playsinline muted></video><div class="frame"></div></div>
      <p class="footnote" id="cam-note" style="margin-top:8px">Point the camera at a member's pass. Safari will ask for camera access.</p>`;
    if (ci.mode === 'lookup') return `<label class="search"><span class="sr">Search members</span><input class="input" id="lookup" type="search" placeholder="Search members and RSVPs" autocomplete="off"></label><div id="lookup-results" class="card" style="margin-top:12px;padding-top:4px;padding-bottom:4px"><p class="footnote" style="padding:12px 0">Type a name.</p></div>`;
    return `<form id="guest-form" class="row"><label class="spacer"><span class="sr">Guest's name</span><input class="input" name="guest" placeholder="Guest's name" autocomplete="off"></label><button class="btn primary small" style="min-height:48px">Check in</button></form>`;
  }
  async function ciReload(id) {
    const rows = await run(() => q(sb.from('attendance').select('*').eq('event_id', id).order('recorded_at', { ascending: false })));
    if (!rows) return;
    ci.records = rows;
    const live = rows.filter((r) => !r.removed_at);
    const count = $('#ci-count'), list = $('#ci-list'); if (!list) return;
    count.textContent = `Checked in · ${live.length}`;
    list.innerHTML = rows.map((r) => `<div class="list-row"><div class="spacer"><div class="${r.removed_at ? 'removed' : ''}" style="font-weight:600">${esc(r.attendee_name)}</div>
      <div class="footnote">${esc({ pass: 'Pass', lookup: 'Lookup', guest: 'Guest' }[r.mode])} · ${fmt.time(new Date(r.recorded_at))} · by ${esc(r.recorded_by_name)}</div>
      ${r.removed_reason ? `<div class="footnote" style="color:var(--warning)">Removed: ${esc(r.removed_reason)}</div>` : ''}</div>
      ${r.removed_at ? '' : `<button class="link-btn danger" data-action="correct" data-id="${r.id}" data-name="${esc(r.attendee_name)}" data-event="${id}">Correct</button>`}</div>`).join('')
      || '<p class="footnote" style="padding-top:12px">No one yet.</p>';
  }
  async function ciCheckIn(id, params) {
    const res = await run(() => rpc('check_in', { p_event: id, p_request: uuid(), ...params }));
    const out = $('#ci-result'); if (!res || !out) return;
    const name = res.record.attendee_name;
    out.className = 'result ' + (res.status === 'recorded' ? 'ok' : 'warn');
    out.textContent = res.status === 'recorded' ? `✓ ${name} checked in` : `${name} was already checked in`;
    if (res.status === 'recorded' && navigator.vibrate) navigator.vibrate(30);
    ciReload(id);
  }
  after.checkin = (id) => {
    if (!event(id) || !runsEvent(event(id))) return;
    ciReload(id);
    if (ci.mode === 'scan') startScanner(id);
    if (ci.mode === 'lookup') {
      const input = $('#lookup'); let t;
      const search = async () => {
        const rows = await run(() => rpc('search_attendees', { p_event: id, p_query: input.value }));
        const box = $('#lookup-results'); if (!rows || !box) return;
        const inNames = new Set(ci.records.filter((r) => !r.removed_at).map((r) => r.attendee_name));
        box.innerHTML = rows.map((m) => `<button class="list-row" style="width:100%;background:none;border:0;border-bottom:.5px solid var(--divider);text-align:left;cursor:pointer" data-action="ci-member" data-event="${id}" data-user="${m.user_id}">
          <span class="spacer">${esc(m.name)}</span><span style="color:${inNames.has(m.name) ? 'var(--success)' : 'var(--accent)'}">${inNames.has(m.name) ? '✓' : '＋'}</span></button>`).join('')
          || '<p class="footnote" style="padding:12px 0">No members or RSVPs match.</p>';
      };
      input.addEventListener('input', () => { clearTimeout(t); t = setTimeout(search, 250); });
      search(); input.focus();
    }
    if (ci.mode === 'guest') {
      $('#guest-form').addEventListener('submit', async (ev) => {
        ev.preventDefault(); const v = ev.target.guest.value.trim(); if (!v) return;
        await ciCheckIn(id, { p_guest_name: v }); ev.target.guest.value = '';
      });
    }
  };
  async function startScanner(id) {
    const video = $('#cam'), note = $('#cam-note');
    if (!navigator.mediaDevices?.getUserMedia) { note.textContent = 'This browser can’t use the camera. Use Look up instead.'; return; }
    let stream, raf, stopped = false, lastCode = '', lastAt = 0, busy = false;
    cleanup.push(() => { stopped = true; cancelAnimationFrame(raf); stream?.getTracks().forEach((t) => t.stop()); });
    try { stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false }); }
    catch { note.textContent = 'Camera access was blocked. Allow it in Safari settings (aA → Website Settings), or use Look up.'; return; }
    if (stopped) { stream.getTracks().forEach((t) => t.stop()); return; }
    video.srcObject = stream; await video.play().catch(() => {});
    const canvas = document.createElement('canvas'), ctx = canvas.getContext('2d', { willReadFrequently: true });
    let lastScan = 0;
    const loop = async (now) => {
      if (stopped) return;
      raf = requestAnimationFrame(loop);
      if (now - lastScan < 200 || busy || video.readyState < 2) return;
      lastScan = now;
      const w = 480, h = Math.round(480 * video.videoHeight / video.videoWidth) || 360;
      canvas.width = w; canvas.height = h; ctx.drawImage(video, 0, 0, w, h);
      const code = window.jsQR(ctx.getImageData(0, 0, w, h).data, w, h, { inversionAttempts: 'dontInvert' });
      if (code?.data && !(code.data === lastCode && Date.now() - lastAt < 3000)) {
        lastCode = code.data; lastAt = Date.now(); busy = true;
        await ciCheckIn(id, { p_token: code.data }); busy = false;
      }
    };
    raf = requestAnimationFrame(loop);
  }

  // ───────────── My clubs ─────────────
  function mineView() {
    const by = (f) => visibleClubs().filter((c) => membership(c.id) && f(membership(c.id)));
    const lead = by((m) => m.role === 'officer' && m.status === 'active'), mem = by((m) => m.role !== 'officer' && m.status === 'active'), pend = by((m) => m.status === 'pending');
    const group = (t, l) => l.length ? `<div class="stack"><div class="section-header">${t}</div>${l.map(clubRow).join('')}</div>` : '';
    return `<div class="row"><h1 class="large-title spacer">My Clubs</h1><button class="icon-btn" data-action="start-club" aria-label="Start a club" style="margin-top:16px">＋</button></div>
      <div class="stack-l">${lead.length + mem.length + pend.length ? group('Clubs you lead', lead) + group('Member', mem) + group('Waiting for approval', pend)
        : `<div class="empty"><h2>No clubs yet</h2><p style="margin-bottom:16px">Find a club in Discover and join, or help found one.</p><button class="btn primary" style="max-width:240px" data-action="start-club">Start a club</button></div>`}</div>`;
  }

  // ───────────── Profile ─────────────
  function profileView() {
    const u = S.user, active = Object.values(S.memberships).filter((m) => m.status === 'active').length;
    const blocked = S.clubs.filter((c) => S.blocked.has(c.id));
    return `<h1 class="large-title">Profile</h1><div class="stack-l">
      <div class="card"><h2 style="font-size:22px;font-weight:800">${esc(u.name)}</h2><p class="muted" style="font-size:15px">${esc(u.email)}</p><p class="footnote">${esc(CFG.campus.name)}</p></div>
      <div class="stack"><div class="section-header">Involvement record</div><div class="card" id="involvement">
        <div class="list-row"><span class="spacer">Clubs</span><strong>${active}</strong></div>
        <div class="list-row"><span class="spacer">Events attended</span><strong id="inv-count">…</strong></div><div id="inv-list"></div></div>
        <p class="footnote">Your check-ins, kept so you can show what you've been part of.</p></div>
      ${blocked.length ? `<div class="stack"><div class="section-header">Blocked clubs</div><div class="card">${blocked.map((c) => `<div class="list-row"><span class="spacer">${esc(c.name)}</span><button class="link-btn" data-action="unblock" data-club="${c.id}">Unblock</button></div>`).join('')}</div></div>` : ''}
      <div class="stack"><div class="section-header">Help</div><div class="card">
        <div class="list-row"><a href="mailto:support@vnuaconnect.example">Contact support</a></div>
        <div class="list-row"><a href="prototype/">Original design prototype</a></div>
        <div class="list-row"><span class="spacer muted" style="font-size:15px">Add to Home Screen: Share → Add to Home Screen</span></div></div></div>
      <div class="card stack"><button class="btn secondary" data-action="signout">Sign out</button><button class="btn danger" data-action="delete-account">Delete account</button></div></div>`;
  }
  after.profile = async () => {
    const rows = await run(() => q(sb.from('attendance').select('*').eq('user_id', S.user.id).is('removed_at', null).order('recorded_at', { ascending: false })));
    if (!rows || !$('#inv-count')) return;
    $('#inv-count').textContent = rows.length;
    $('#inv-list').innerHTML = rows.map((r) => `<div class="list-row"><div><div style="font-weight:600;font-size:15px">${esc(event(r.event_id)?.title || 'Event')}</div><div class="footnote">${esc(fmt.day(new Date(r.recorded_at)))}</div></div></div>`).join('');
  };

  // ───────────── Sheets ─────────────
  function openSheet(title, body, { action = '', onSubmit, cancel = 'Cancel' } = {}) {
    $('#sheet-root').innerHTML = `<div class="sheet-backdrop" data-action="sheet-close-bg"><form class="sheet" role="dialog" aria-modal="true" aria-label="${esc(title)}" id="sheet-form" novalidate>
      <div class="sheet-head"><div class="left"><button type="button" data-action="sheet-close">${esc(cancel)}</button></div><h2>${esc(title)}</h2>
      <div class="right">${action ? `<button type="submit" id="sheet-submit">${esc(action)}</button>` : ''}</div></div>${body}</form></div>`;
    document.body.style.overflow = 'hidden';
    const form = $('#sheet-form');
    form.addEventListener('submit', async (ev) => {
      ev.preventDefault(); const btn = $('#sheet-submit'); if (btn) btn.disabled = true;
      const ok = await onSubmit?.(new FormData(form), form);
      if (ok) closeSheet(); else if (btn) btn.disabled = false;
    });
    setTimeout(() => form.querySelector('input:not([type=radio]):not([type=hidden]), textarea')?.focus(), 250);
    return form;
  }
  function closeSheet() { $('#sheet-root').innerHTML = ''; document.body.style.overflow = ''; }
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && $('#sheet-root').innerHTML) closeSheet(); });

  function confirmSheet(title, message, actionLabel, fn) {
    openSheet(title, `<div class="stack" style="padding:8px 0"><p>${esc(message)}</p>
      <button class="btn primary" type="submit" style="background:var(--danger)">${esc(actionLabel)}</button></div>`,
      { onSubmit: async () => (await run(fn)) !== undefined });
  }
  const radios = (name, options, selected) => `<div class="card" style="padding-top:0;padding-bottom:0">${options.map(([v, label, sub]) => `<label class="choice">
    <input type="radio" name="${name}" value="${esc(v)}" ${v === selected ? 'checked' : ''}><span><span style="font-weight:600">${esc(label)}</span>${sub ? `<br><span class="footnote">${esc(sub)}</span>` : ''}</span></label>`).join('')}</div>`;

  function joinSheet(c) {
    openSheet(c.name, `<div class="stack-l"><div class="stack"><div class="section-header">Join as</div>${radios('role', [
        ['member', 'Member', ''], ['founding', 'Founding member', c.recognition === 'recognized' ? 'Help run the club day to day.' : 'Counts toward the students a club needs to apply for recognition.']], 'member')}</div>
      <div class="stack"><div class="section-header">Emails from ${esc(c.name)}</div>${radios('contact', Object.entries(contactLabel).map(([k, v]) => [k, v, '']), 'events')}</div></div>`,
    { action: c.requires_approval ? 'Request' : 'Join', onSubmit: async (fd) => {
      const m = await run(() => rpc('join_club', { p_club: c.id, p_role: fd.get('role'), p_contact: fd.get('contact'), p_request: uuid() }));
      if (!m) return false;
      S.memberships[c.id] = m; toast(m.status === 'pending' ? `Request sent to ${c.name}'s officers` : `You joined ${c.name}`); render(); return true;
    } });
  }
  const REASONS = [['impersonation', 'Pretending to be another group'], ['duplicate', 'Duplicate of an existing club or event'],
    ['unsafe', 'Inappropriate or unsafe content'], ['wrong_status', 'Status claim looks wrong'], ['other', 'Something else']];
  function reportSheet(type, id, name) {
    openSheet('Report', `<div class="stack-l"><div class="stack"><div class="section-header">What's wrong with ${esc(name)}?</div>${radios('reason', REASONS.map(([k, v]) => [k, v, '']), '')}</div>
      <label class="field"><span>Details (optional)</span><textarea class="input" name="detail" maxlength="1000" placeholder="Anything that helps a moderator"></textarea></label></div>`,
    { action: 'Send', onSubmit: async (fd) => {
      if (!fd.get('reason')) { toast('Pick a reason.', true); return false; }
      const ok = await run(() => rpc('report_content', { p_type: type, p_target: id, p_reason: fd.get('reason'), p_detail: fd.get('detail') || '' }).then(() => true));
      if (ok) toast('Report sent. A moderator will review it.'); return !!ok;
    } });
  }
  function clubMenu(c) {
    openSheet(c.name, `<div class="card stack">
      <button type="button" class="btn secondary" data-action="share" data-club="${c.id}">Share club</button>
      <button type="button" class="btn secondary" data-action="report" data-type="club" data-id="${c.id}" data-name="${esc(c.name)}">⚑ Report club</button>
      <button type="button" class="btn danger" data-action="block" data-club="${c.id}">Block club</button></div>`, { cancel: 'Close' });
  }

  const INTERESTS = ['Academic', 'Creative', 'Cultural', 'Engineering', 'Games', 'Media', 'Performing arts', 'Professional', 'Service', 'Sports', 'Wellness'];
  const ACCENTS = [['#1f5a6b', 'Harbor'], ['#8a3b2e', 'Brick'], ['#2c455d', 'Steel'], ['#2f5d3a', 'Pine'], ['#4a3a6b', 'Plum'], ['#7a4f12', 'Clay']];
  const monogramOf = (name) => {
    const w = name.split(/\s+/).filter((x) => x && !['&', 'and', 'the', 'of'].includes(x.toLowerCase()));
    return (w.slice(0, 2).map((x) => x[0]).join('') || '?').toUpperCase();
  };
  function startClubSheet() {
    const form = openSheet('Start a club', `<div class="stack-l">
      <div class="row"><div class="mono" id="sc-mono" style="width:52px;height:52px;font-size:20px;background:${ACCENTS[0][0]}">?</div>
        <label class="spacer"><span class="sr">Club name</span><input class="input" name="name" placeholder="Club name" maxlength="80" required></label></div>
      <label class="field"><span>One line about the club</span><input class="input" name="blurb" maxlength="160" required></label>
      <label class="field"><span>Interest</span><select class="input" name="interest">${INTERESTS.map((i) => `<option>${i}</option>`).join('')}</select></label>
      <div class="field"><span>Color</span><div class="swatches">${ACCENTS.map(([h, n], i) => `<button type="button" class="swatch" style="background:${h}" data-action="swatch" data-v="${h}" aria-label="${n}" aria-pressed="${i === 0}"></button>`).join('')}</div>
        <input type="hidden" name="accent" value="${ACCENTS[0][0]}"></div>
      <label class="field"><span>About</span><textarea class="input" name="about" maxlength="2000" placeholder="What you do, who it's for, how often you meet"></textarea></label>
      <label class="choice card" style="border:0"><input type="checkbox" name="approval"><span><span style="font-weight:600">Officers approve new members</span></span></label>
      <p class="footnote">You'll be the club's first officer. Other students see it after a quick review, usually within a day.</p></div>`,
    { action: 'Create', onSubmit: async (fd) => {
      const name = (fd.get('name') || '').trim();
      if (name.length < 2 || !(fd.get('blurb') || '').trim()) { toast('Add a name and a one-line description.', true); return false; }
      const id = await run(() => rpc('create_club', { p_name: name, p_interest: fd.get('interest'), p_blurb: fd.get('blurb').trim(),
        p_about: (fd.get('about') || '').trim(), p_monogram: monogramOf(name), p_accent: fd.get('accent'), p_requires_approval: fd.get('approval') === 'on' }));
      if (!id) return false;
      await refresh(); toast(`${name} created. It's waiting for review.`); location.hash = `#/club/${id}`; return true;
    } });
    form.name.addEventListener('input', () => { $('#sc-mono').textContent = monogramOf(form.name.value); });
  }
  function newEventSheet(c) {
    const t = new Date(); t.setDate(t.getDate() + 1); t.setHours(18, 0, 0, 0);
    const local = (d) => new Date(d - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
    const others = S.clubs.filter((x) => x.id !== c.id && isOfficer(x.id));
    const rid = uuid();
    openSheet(c.name, `<div class="stack-l">
      <label class="field"><span>Event title</span><input class="input" name="title" maxlength="140" required></label>
      <label class="field"><span>Starts</span><input class="input" name="start" type="datetime-local" value="${local(t)}" min="${local(new Date())}" required></label>
      <label class="field"><span>Length</span><select class="input" name="duration">${[30, 45, 60, 90, 120, 180, 240].map((m) => `<option value="${m}" ${m === 60 ? 'selected' : ''}>${m < 60 ? m + ' min' : m % 60 ? `${Math.floor(m / 60)} hr ${m % 60} min` : m / 60 + ' hr'}</option>`).join('')}</select></label>
      <label class="field"><span>Where</span><input class="input" name="location" maxlength="140"></label>
      <label class="field"><span>Details</span><textarea class="input" name="details" maxlength="2000" placeholder="What to expect, what to bring"></textarea></label>
      ${others.length ? `<div class="stack"><div class="section-header">Co-host with</div><div class="card" style="padding-top:0;padding-bottom:0">${others.map((o) => `<label class="choice"><input type="checkbox" name="cohost" value="${o.id}"><span>${esc(o.name)}</span></label>`).join('')}</div>
        <p class="footnote">Joint events show up for both clubs. Each person is counted once.</p></div>` : ''}</div>`,
    { action: 'Post', onSubmit: async (fd) => {
      const title = (fd.get('title') || '').trim(); if (title.length < 2) { toast('Give the event a title.', true); return false; }
      const start = new Date(fd.get('start')); if (isNaN(start)) { toast('Pick a start time.', true); return false; }
      const id = await run(() => rpc('create_event', { p_hosts: [c.id, ...fd.getAll('cohost')], p_title: title, p_starts_at: start.toISOString(),
        p_duration: Number(fd.get('duration')), p_location: (fd.get('location') || '').trim(), p_details: (fd.get('details') || '').trim(), p_request: rid }));
      if (!id) return false;
      await refresh(); toast('Event posted'); return true;
    } });
  }
  function correctSheet(recordId, name, eventId) {
    openSheet('Correct attendance', `<div class="stack-l"><p>Remove <strong>${esc(name)}</strong> from attendance?</p>
      <label class="field"><span>Reason (required)</span><textarea class="input" name="reason" maxlength="300" placeholder="e.g. Scanned the wrong person" required></textarea></label>
      <p class="footnote">The original record is kept with your reason so the club's history stays honest.</p></div>`,
    { action: 'Remove', onSubmit: async (fd) => {
      const reason = (fd.get('reason') || '').trim(); if (!reason) { toast('A reason is required.', true); return false; }
      const ok = await run(() => rpc('correct_attendance', { p_record: recordId, p_reason: reason, p_request: uuid() }).then(() => true));
      if (ok) ciReload(eventId); return !!ok;
    } });
  }

  // ───────────── Files ─────────────
  function download(name, type, text) {
    const url = URL.createObjectURL(new Blob([text], { type }));
    const a = Object.assign(document.createElement('a'), { href: url, download: name });
    document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 2000);
  }
  function icsFor(e) {
    const d = (x) => x.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
    const t = (s) => String(s || '').replace(/[\\,;]/g, (m) => '\\' + m).replace(/\n/g, '\\n');
    return ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Vnua-connect//EN', 'BEGIN:VEVENT', `UID:${e.id}@vnuaconnect`, `DTSTAMP:${d(new Date())}`,
      `DTSTART:${d(e.start)}`, `DTEND:${d(e.end)}`, `SUMMARY:${t(e.title)}`, `LOCATION:${t(e.location)}`,
      `DESCRIPTION:${t(hostNames(e) + '\n\n' + e.details)}`, 'END:VEVENT', 'END:VCALENDAR'].join('\r\n');
  }
  function csvFor(rows) {
    const c = (s) => `"${String(s ?? '').replace(/"/g, '""')}"`;
    return ['name,mode,recorded_at,recorded_by,removed_reason', ...rows.slice().reverse().map((r) =>
      [c(r.attendee_name), r.mode, r.recorded_at, c(r.recorded_by_name), c(r.removed_reason)].join(','))].join('\n');
  }

  // ───────────── Actions (event delegation) ─────────────
  document.addEventListener('click', async (ev) => {
    const el = ev.target.closest('[data-action]');
    if (!el) return;
    const a = el.dataset.action, d = el.dataset;
    if (!a) return;
    const c = d.club && club(d.club);
    switch (a) {
      case 'sheet-close': closeSheet(); break;
      case 'sheet-close-bg': if (ev.target === el) closeSheet(); break;
      case 'signin-reset': S.signin.sent = false; render(); break;
      case 'interest': S.interest = d.v || null; render(); break;
      case 'ev-scope': S.evScope = d.v; render(); break;
      case 'join': joinSheet(c); break;
      case 'leave': confirmSheet(`Leave ${c.name}?`, 'You can join again later.', 'Leave club', async () => {
        await rpc('leave_club', { p_club: c.id }); delete S.memberships[c.id]; toast(`You left ${c.name}`); render(); return true; }); break;
      case 'review': {
        const ok = await run(() => rpc('review_join_request', { p_club: d.club, p_user: d.user, p_approve: d.approve === '1' }).then(() => true));
        if (ok) { toast(d.approve === '1' ? 'Approved' : 'Request declined'); after.club(d.club); } break; }
      case 'club-menu': clubMenu(c); break;
      case 'share': {
        const url = `${HERE}#/club/${c.id}`;
        if (navigator.share) navigator.share({ title: c.name, text: `Check out ${c.name} on Vnua-connect`, url }).catch(() => {});
        else { await navigator.clipboard?.writeText(url); toast('Link copied'); }
        break; }
      case 'report': reportSheet(d.type, d.id, d.name); break;
      case 'block': confirmSheet(`Block ${c.name}?`, "You won't see this club or its events. You can undo this in Profile.", 'Block', async () => {
        await rpc('block_club', { p_club: c.id, p_blocked: true }); S.blocked.add(c.id); toast(`You won't see ${c.name} anymore`); location.hash = '#/discover'; return true; }); break;
      case 'unblock': if (await run(() => rpc('block_club', { p_club: d.club, p_blocked: false }).then(() => true))) { S.blocked.delete(d.club); render(); } break;
      case 'rsvp': {
        const going = !S.rsvps.has(d.id);
        going ? S.rsvps.add(d.id) : S.rsvps.delete(d.id); render();           // optimistic
        const ok = await run(() => rpc('set_rsvp', { p_event: d.id, p_going: going, p_request: uuid() }).then(() => true));
        if (!ok) { going ? S.rsvps.delete(d.id) : S.rsvps.add(d.id); render(); }
        break; }
      case 'ics': { const e = event(d.id); download(`${e.title.slice(0, 40)}.ics`, 'text/calendar', icsFor(e)); break; }
      case 'cancel-event': confirmSheet('Cancel this event?', 'Members will see it as cancelled. RSVPs and check-ins are kept.', 'Cancel event', async () => {
        await rpc('cancel_event', { p_event: d.id }); await refresh(); toast('Event cancelled'); return true; }); break;
      case 'new-event': newEventSheet(c); break;
      case 'start-club': startClubSheet(); break;
      case 'swatch': {
        const form = $('#sheet-form'); form.accent.value = d.v; $('#sc-mono').style.background = d.v;
        form.querySelectorAll('.swatch').forEach((s) => s.setAttribute('aria-pressed', s === el)); break; }
      case 'ci-mode': ci.mode = d.v; render(); break;
      case 'ci-member': await ciCheckIn(d.event, { p_member: d.user }); $('#lookup')?.dispatchEvent(new Event('input')); break;
      case 'correct': correctSheet(d.id, d.name, d.event); break;
      case 'csv': { const e = event(d.id); download(`attendance-${(e?.title || 'event').slice(0, 30).replace(/[^\w]+/g, '-')}.csv`, 'text/csv', csvFor(ci.records)); break; }
      case 'signout': await sb.auth.signOut(); break;
      case 'delete-account': confirmSheet('Delete your account?', "This removes your profile, memberships and RSVPs. It can't be undone.", 'Delete account', async () => {
        await rpc('delete_account'); await sb.auth.signOut({ scope: 'local' }); return true; }); break;
    }
  });
  document.addEventListener('change', async (ev) => {
    const el = ev.target;
    if (el.dataset.change === 'contact') {
      const ok = await run(() => rpc('update_contact', { p_club: el.dataset.club, p_contact: el.value }).then(() => true));
      if (ok) { S.memberships[el.dataset.club].contact = el.value; toast('Saved'); }
    }
  });

  // ───────────── Boot ─────────────
  async function signedIn(session) {
    const profile = await run(() => loadProfile(session.user.id));
    if (!profile) { S.booting = false; render(); return; }
    S.user = profile;
    await run(loadAll);
    S.booting = false; render();
  }
  async function boot() {
    const params = new URLSearchParams(location.search);
    const err = params.get('error_description') || new URLSearchParams(location.hash.slice(1)).get('error_description');
    const { data: { session } } = await sb.auth.getSession();       // also finishes a sign-in link (?code=…)
    if (params.has('code') || params.has('error') || location.hash.includes('error=')) history.replaceState(null, '', HERE + (location.hash.startsWith('#/') ? location.hash : ''));
    if (err) toast(/code verifier|both auth code/i.test(err) ? 'Open the sign-in link in the same browser you requested it from.' : err.replace(/\+/g, ' '), true);
    if (!session && params.has('code') && !err) toast('That link was opened in a different browser. Request a new one here, or enter the code.', true);
    if (session) await signedIn(session); else { S.booting = false; render(); }
    sb.auth.onAuthStateChange((evt, s) => {
      if (evt === 'SIGNED_IN' && s && !S.user) { S.booting = true; render(); signedIn(s); }
      if (evt === 'SIGNED_OUT') { Object.assign(S, { user: null, clubs: [], events: [], memberships: {}, rsvps: new Set(), blocked: new Set() });
        S.signin = { name: '', email: '', sent: false, busy: false }; location.hash = ''; render(); }
    });
  }
  window.addEventListener('pageshow', (e) => { if (e.persisted && S.user) refresh(); });
  boot().catch((e) => { console.error(e); S.booting = false; render(); toast(errMsg(e), true); });
})();
