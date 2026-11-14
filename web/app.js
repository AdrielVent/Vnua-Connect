/* Vnua-connect web app. Same backend and rules as the iPhone app (supabase/migrations).
   Plain JavaScript, no build step: GitHub Pages serves these files as they are. */
(() => {
  'use strict';
  const CFG = window.VNUA_CONFIG;
  // persistSession + autoRefreshToken: you stay signed in on this device until you sign out.
  const sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey, {
    auth: { flowType: 'pkce', detectSessionInUrl: true, persistSession: true, autoRefreshToken: true },
  });
  const HERE = location.origin + location.pathname;          // email link comes back here

  // ───────────── State ─────────────
  const blankSignin = () => ({ email: '', sent: false, busy: false, sentAt: 0, show: false });
  const S = {
    booting: true, user: null, clubs: [], events: [], memberships: {}, rsvps: new Set(), blocked: new Set(),
    notifs: [], invites: [], q: '', interest: null, evScope: 'all', signin: blankSignin(), ob: null, nc: null,
  };
  let cleanup = [];                    // timers / camera for the current screen
  const $ = (sel, root = document) => root.querySelector(sel);

  // ───────────── Constants ─────────────
  const INTERESTS = ['Academic', 'Business', 'Creative', 'Cultural', 'Engineering', 'Faith', 'Food', 'Games', 'Media', 'Music',
    'Outdoors', 'Performing arts', 'Professional', 'Service', 'Social justice', 'Sports', 'Tech', 'Wellness'];
  const YEARS = ['Freshman', 'Sophomore', 'Junior', 'Senior', 'Grad student', 'Alum', 'Faculty/Staff'];
  const CORE = ['President', 'Vice President', 'Treasurer', 'Secretary'];
  const ACCENTS = [['#1f5a6b', 'Harbor'], ['#8a3b2e', 'Brick'], ['#2c455d', 'Steel'], ['#2f5d3a', 'Pine'], ['#4a3a6b', 'Plum'], ['#7a4f12', 'Clay']];
  const REMINDERS = [[20160, '2 weeks'], [10080, '1 week'], [4320, '3 days'], [1440, '24 hours'], [120, '2 hours'], [60, '1 hour'], [30, '30 min']];
  const NOTIFY = [['all', 'Everything', 'New events, announcements, and reminders for every event'],
    ['rsvp', 'Just what I RSVP to', 'Announcements, plus reminders for events you said you’re going to'],
    ['none', 'Nothing', 'No notifications. You’ll check the app yourself']];
  const RECOGNITION_GOAL = 15;
  const INVOLVE = [['updates', 'Keep me updated', 'You mostly want to hear what’s going on'],
    ['attend', 'I’ll come when I can', 'You plan to show up to events'],
    ['organize', 'I want to help build it', 'Officers may reach out about planning and running things']];
  const NEWCOMER = [['who', 'Who it’s for', 'e.g. Anyone curious, no experience needed'], ['experience', 'Experience needed', 'e.g. None'],
    ['bring', 'What to bring', 'e.g. Nothing, or a laptop'], ['cost', 'Cost', 'e.g. Free'], ['meet', 'Where exactly to go', 'e.g. Room 141, second floor, door on the left'],
    ['happens', 'What happens', 'e.g. 10 min intros, then we split into teams'], ['contact', 'Questions before you come', 'e.g. Text Pat, or email the club']];
  const HELP = ['Event setup', 'Design', 'Outreach', 'Social media', 'Tech projects', 'Fundraising', 'Writing', 'Photography', 'Running meetings'];
  const LOOKING = ['Community', 'Friends', 'Leadership experience', 'A project', 'Mentorship', 'Career connections'];

  // ───────────── Helpers ─────────────
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0; return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  }));
  const fmt = {
    day: (d) => d.toLocaleDateString(undefined, { weekday: 'long', month: 'short', day: 'numeric' }),
    short: (d) => d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }),
    time: (d) => d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' }),
    full: (d) => d.toLocaleString(undefined, { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }),
    dow: (d) => d.toLocaleDateString(undefined, { weekday: 'short' }).toUpperCase(),
    rel: (d) => { const m = Math.round((Date.now() - d) / 60000); return m < 1 ? 'just now' : m < 60 ? `${m} min ago` : m < 1440 ? `${Math.round(m / 60)} hr ago` : m < 10080 ? `${Math.round(m / 1440)} d ago` : fmt.short(d); },
  };
  const sameDay = (a, b) => a.toDateString() === b.toDateString();
  const pct = (a, b) => (b ? Math.round((a / b) * 100) + '%' : '–');
  const plural = (n, w, ws = w + 's') => `${n} ${n === 1 ? w : ws}`;

  /** Database functions raise 'code|Human message'. Show only the human part. */
  function errMsg(e) {
    const m = (e && (e.message || e.error_description || e.msg)) || String(e);
    if (/failed to fetch|network|load failed/i.test(m)) return 'No connection. Check your internet and try again.';
    if (/token has expired or is invalid|otp.*(expired|invalid)/i.test(m)) return 'That code didn’t work. Check it, or send a new one.';
    if (/for security purposes|rate limit/i.test(m)) return 'Wait a minute before asking for another code.';
    const i = m.indexOf('|');
    return i > 0 ? m.slice(i + 1) : m;
  }
  async function q(promise) { const { data, error } = await promise; if (error) throw error; return data; }
  const rpc = (fn, params) => q(sb.rpc(fn, params));

  let toastTimer;
  function toast(msg, isError = false) {
    const t = $('#toast');
    t.textContent = msg; t.className = 'show' + (isError ? ' error' : '');
    clearTimeout(toastTimer); toastTimer = setTimeout(() => { t.className = isError ? 'error' : ''; }, 3000);
  }
  /** Runs an async action; shows any error as a toast. Returns undefined on failure. */
  async function run(fn) { try { return await fn(); } catch (e) { console.error(e); toast(errMsg(e), true); return undefined; } }
  async function copy(text, what) {
    try { await navigator.clipboard.writeText(text); toast(`${what} copied`); }
    catch { window.prompt(`Copy ${what.toLowerCase()}:`, text); }
  }

  // ───────────── Derived ─────────────
  const club = (id) => S.clubs.find((c) => c.id === id);
  const event = (id) => S.events.find((e) => e.id === id);
  const membership = (id) => S.memberships[id];
  const isMember = (id) => membership(id)?.status === 'active';
  const isOfficer = (clubId) => membership(clubId)?.role === 'officer' && membership(clubId)?.status === 'active';
  const runsEvent = (e) => e.hosts.some(isOfficer);
  const visibleClubs = () => S.clubs.filter((c) => !S.blocked.has(c.id));
  const visibleEvents = () => S.events.filter((e) => !e.hosts.every((h) => S.blocked.has(h)));
  const hostNames = (e) => e.hosts.map((h) => club(h)?.name).filter(Boolean).join(' + ');
  const coreFilled = (c) => CORE.filter((t) => c.officers.some((o) => o.title.toLowerCase() === t.toLowerCase())).length;
  const myInvites = () => S.invites.filter((i) => i.email === S.user.email);
  const clubInvites = (id) => S.invites.filter((i) => i.club_id === id);
  const unread = () => S.notifs.filter((n) => !n.read_at).length + myInvites().length;
  const recogLabel = { recognized: 'Recognized', not_recognized: 'Not yet recognized', not_stated: 'Status not stated' };
  const roleLabel = { member: 'Member', founding: 'Founding member', officer: 'Officer' };

  // ───────────── Data ─────────────
  async function loadProfile(userId) { return q(sb.from('profiles').select('*').eq('id', userId).single()); }
  async function loadInbox() {
    const [notifs, invites] = await Promise.all([
      q(sb.from('notifications').select('*').order('created_at', { ascending: false }).limit(100)),
      q(sb.from('club_invites').select('*').eq('status', 'pending').order('created_at')),
    ]);
    S.notifs = notifs; S.invites = invites;
  }
  async function loadAll() {
    const me = S.user.id, campus = S.user.campus_id;
    const [clubs, officers, events, ms, rs, bl] = await Promise.all([
      q(sb.from('clubs').select('*').eq('campus_id', campus).order('name')),
      q(sb.from('club_officers').select('*').order('rank')),
      q(sb.from('events').select('*, event_hosts(club_id)').eq('campus_id', campus).order('starts_at')),
      q(sb.from('memberships').select('*').eq('user_id', me)),
      q(sb.from('rsvps').select('event_id').eq('user_id', me)),
      q(sb.from('club_blocks').select('club_id')),
      loadInbox(),
    ]);
    S.clubs = clubs.map((c) => ({ ...c, officers: officers.filter((o) => o.club_id === c.id) }));
    S.events = events.map((e) => ({ ...e, start: new Date(e.starts_at), hosts: e.event_hosts.map((h) => h.club_id),
      end: new Date(new Date(e.starts_at).getTime() + e.duration_minutes * 60000) }));
    S.memberships = Object.fromEntries(ms.map((m) => [m.club_id, m]));
    S.rsvps = new Set(rs.map((r) => r.event_id));
    S.blocked = new Set(bl.map((b) => b.club_id));
  }
  let lastLoad = 0;
  async function refresh() { await run(loadAll); lastLoad = Date.now(); render(); }

  // Feels like an app: fresh data when you come back to it, and the inbox badge stays current.
  const busyTyping = () => $('#sheet-root').innerHTML || ['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement?.tagName)
    || ['new-club', 'dash'].includes(route().name) || S.ob;
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && S.user && Date.now() - lastLoad > 20000) {
      run(loadAll).then(() => { lastLoad = Date.now(); if (!busyTyping()) render(); else updateBell(); });
    }
  });
  setInterval(() => { if (S.user && document.visibilityState === 'visible') run(loadInbox).then(updateBell); }, 60000);
  function updateBell() {
    document.querySelectorAll('[data-bell]').forEach((b) => {
      const n = unread(); b.querySelector('.dot')?.remove();
      if (n) b.insertAdjacentHTML('beforeend', `<span class="dot">${n > 9 ? '9+' : n}</span>`);
      b.setAttribute('aria-label', n ? `Inbox, ${n} new` : 'Inbox');
    });
  }

  // ───────────── Icons ─────────────
  const svg = (p) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${p}</svg>`;
  const icon = {
    discover: svg('<circle cx="10.5" cy="10.5" r="6.5"/><path d="m20 20-4.8-4.8"/>'),
    events: svg('<rect x="3.5" y="5" width="17" height="15" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4"/>'),
    clubs: svg('<circle cx="8" cy="9" r="3"/><circle cx="16.5" cy="9" r="3"/><path d="M2.5 19c.7-3 3-4.5 5.5-4.5s4.8 1.5 5.5 4.5M12 19c.6-2.6 2.4-4.3 4.5-4.3s3.9 1.7 4.5 4.3"/>'),
    people: svg('<path d="M4 20c.8-3.6 3.9-6 8-6s7.2 2.4 8 6"/><circle cx="12" cy="8" r="4"/>'),
    profile: svg('<circle cx="12" cy="12" r="9"/><circle cx="12" cy="10" r="3"/><path d="M6.5 18.5c1.3-2 3.2-3 5.5-3s4.2 1 5.5 3"/>'),
    bell: svg('<path d="M6 9a6 6 0 1 1 12 0c0 5 2 6.5 2 6.5H4S6 14 6 9"/><path d="M10 19a2 2 0 0 0 4 0"/>'),
    mail: svg('<rect x="3" y="5" width="18" height="14" rx="2.5"/><path d="m4 7 8 6 8-6"/>'),
    phone: svg('<path d="M5 4h3l1.5 4.5-2 1.3a11 11 0 0 0 6.7 6.7l1.3-2L20 16v3a1.5 1.5 0 0 1-1.6 1.5C10.6 20 4 13.4 3.5 5.6A1.5 1.5 0 0 1 5 4"/>'),
    link: svg('<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>'),
    star: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 3.2l2.6 5.5 6 .7-4.4 4.1 1.2 5.9L12 16.5l-5.4 2.9 1.2-5.9L3.4 9.4l6-.7z"/></svg>',
  };

  // ───────────── Router ─────────────
  // #/discover #/events #/mine #/people #/profile #/inbox #/club/:id #/event/:id #/pass/:id #/checkin/:id #/dash/:id #/new-club
  function route() {
    const [, name = 'discover', id] = (location.hash || '#/discover').split('/');
    return { name, id };
  }
  window.addEventListener('hashchange', () => { inboxFresh = false; closeSheet(); render(); window.scrollTo(0, 0); });

  const triedFetch = new Set();       // ids we already refetched for, so a truly missing item shows "not found"
  const TABS = ['discover', 'events', 'mine', 'people', 'profile'];
  function render() {
    cleanup.forEach((f) => f()); cleanup = [];
    const app = $('#app');
    if (S.booting) { app.innerHTML = '<div class="boot"><div class="spinner" role="status" aria-label="Loading"></div></div>'; return; }
    if (!S.user) {
      const pr = route();
      if (!S.signin.show && (pr.name === 'club' || pr.name === 'event') && pr.id) { app.innerHTML = previewShell(); loadPreview(pr); return; }
      app.innerHTML = signInView(); bindSignIn(); return;
    }
    if (S.ob) { app.innerHTML = obView(); after.ob?.(); return; }
    const r = route();
    const views = { discover: discoverView, events: eventsView, mine: mineView, people: peopleView, profile: profileView, inbox: inboxView,
      club: clubView, event: eventView, pass: passView, checkin: checkinView, dash: dashView, 'new-club': newClubView };
    const view = views[r.name] || discoverView;
    // Opened something we haven't loaded yet (a shared link, or it was just created)? Fetch once, then show it.
    const missing = (r.name === 'club' || r.name === 'dash') ? !club(r.id) : ['event', 'pass', 'checkin'].includes(r.name) ? !event(r.id) : false;
    if (missing && r.id && !triedFetch.has(r.id)) {
      triedFetch.add(r.id);
      app.innerHTML = '<div class="boot"><div class="spinner" role="status" aria-label="Loading"></div></div>';
      run(loadAll).then(() => { lastLoad = Date.now(); render(); }); return;
    }
    const tabs = TABS.includes(r.name) || !views[r.name];
    app.innerHTML = `<main class="screen${tabs ? '' : ' no-tabs'}">${view(r.id)}</main>${tabs ? tabbar(r.name) : ''}`;
    after[r.name]?.(r.id);
  }
  const after = {};                    // per-screen setup after HTML is in the DOM

  function tabbar(active) {
    const t = (id, label, ic) => `<a href="#/${id}" ${active === id ? 'aria-current="page"' : ''}>${icon[ic]}<span>${label}</span></a>`;
    return `<nav class="tabbar" aria-label="Main">${t('discover', 'Discover', 'discover')}${t('events', 'Events', 'events')}${t('mine', 'My Clubs', 'clubs')}${t('people', 'People', 'people')}${t('profile', 'Profile', 'profile')}</nav>`;
  }
  function titleBar(title, extra = '') {
    const n = unread();
    return `<div class="title-row"><h1 class="large-title">${esc(title)}</h1>${extra}<a class="icon-btn bell" href="#/inbox" data-bell aria-label="${n ? `Inbox, ${n} new` : 'Inbox'}">${icon.bell}${n ? `<span class="dot">${n > 9 ? '9+' : n}</span>` : ''}</a></div>`;
  }
  const back = (href, label = 'Back') => `<div class="topbar"><a class="back" href="${href}">‹ ${esc(label)}</a><span class="spacer"></span>`;

  // ───────────── Pieces ─────────────
  const mono = (c, size = 48) => c.logo_url
    ? `<img class="logo" src="${esc(c.logo_url)}" alt="" width="${size}" height="${size}" loading="lazy">`
    : `<div class="mono" aria-hidden="true" style="width:${size}px;height:${size}px;font-size:${Math.round(size * .38)}px;background:${esc(c.accent_hex)}">${esc(c.monogram)}</div>`;
  const initials = (name) => (name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
  const hue = (s) => [...String(s)].reduce((h, ch) => (h * 31 + ch.charCodeAt(0)) % 360, 7);
  const avatar = (name, size = 44) => `<div class="avatar" aria-hidden="true" style="width:${size}px;height:${size}px;font-size:${Math.round(size * .38)}px;--h:${hue(name)}">${esc(initials(name))}</div>`;
  const badge = (text, tone = '') => `<span class="badge ${tone}">${esc(text)}</span>`;
  function clubStatusBadge(c) {
    if (c.is_published) return '';
    const n = coreFilled(c);
    return n < 4 ? badge(`Forming · ${n}/4 officers`, 'warning') : badge('In review', 'warning');
  }
  function clubBadges(c) {
    const m = membership(c.id);
    return `<div class="badges">${badge(c.interest)}${clubStatusBadge(c)}${
      m ? (m.status === 'pending' ? badge('Requested', 'warning') : badge(m.role === 'officer' ? (m.officer_title || 'Officer') : roleLabel[m.role], 'success')) : ''}</div>`;
  }
  const clubRow = (c) => `<a class="card club-row" href="#/club/${c.id}">${mono(c)}<div class="spacer"><div class="name">${esc(c.name)}</div>
    <div class="blurb">${esc(c.blurb)}</div>${clubBadges(c)}</div><span class="chev">›</span></a>`;
  function statusBadge(e) {
    return e.status === 'rescheduled' ? badge('Rescheduled', 'warning') : e.status === 'cancelled' ? badge('Cancelled', 'warning') : '';
  }
  const eventRow = (e) => `<a class="card row${e.status === 'cancelled' ? ' cancelled' : ''}" href="#/event/${e.id}" style="align-items:flex-start">
    <div class="date-chip"><span class="dow">${fmt.dow(e.start)}</span><span class="day">${e.start.getDate()}</span></div>
    <div class="spacer"><div class="event-title">${esc(e.title)}</div>
    <div class="muted" style="font-size:15px">${fmt.time(e.start)}${e.location ? ' · ' + esc(e.location) : ''}</div>
    <div class="footnote">${esc(hostNames(e))}</div>
    <div class="badges">${statusBadge(e)}${S.rsvps.has(e.id) ? badge('Going', 'success') : ''}</div></div></a>`;
  const eventCard = (e) => `<a class="card" href="#/event/${e.id}"><div class="kicker">${esc(fmt.day(e.start))}</div>
    <div class="event-title" style="margin:6px 0;min-height:2.8em">${esc(e.title)}</div>
    <div class="footnote" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${fmt.time(e.start)}${e.location ? ' · ' + esc(e.location) : ''}</div>
    ${S.rsvps.has(e.id) ? `<div class="badges">${badge('Going', 'success')}</div>` : ''}</a>`;
  function newcomerHTML(n) {
    const rows = NEWCOMER.filter(([k]) => n?.[k]);
    if (!rows.length) return '';
    return `<div class="card stack newcomer"><strong>First time? Here’s what to know</strong><dl class="facts stacked">${rows.map(([k, l]) =>
      `<div><dt>${esc(l)}</dt><dd>${esc(n[k])}</dd></div>`).join('')}</dl></div>`;
  }
  /** Email / text / LinkedIn buttons for whatever a person chose to share. */
  function contactButtons(p) {
    const b = [];
    if (p.email) b.push(`<a class="btn secondary small" href="mailto:${esc(p.email)}">${icon.mail}Email</a>`);
    const tel = (p.phone || '').replace(/[^\d+]/g, '');
    if (tel) b.push(`<a class="btn secondary small" href="sms:${esc(tel)}">${icon.phone}Text</a>`);
    if (/^https:\/\/([a-z]+\.)?linkedin\.com\//i.test(p.linkedin || '')) b.push(`<a class="btn secondary small" href="${esc(p.linkedin)}" target="_blank" rel="noopener noreferrer">${icon.link}LinkedIn</a>`);
    return b.length ? `<div class="contact-row">${b.join('')}</div>` : '';
  }
  const stat = (value, label, sub = '') => `<div class="stat"><div class="stat-v">${esc(value)}</div><div class="stat-l">${esc(label)}</div>${sub ? `<div class="footnote">${esc(sub)}</div>` : ''}</div>`;
  const stars = (eventId, value, size = '') => `<div class="stars ${size}" role="group" aria-label="Rate this event">${[1, 2, 3, 4, 5].map((v) =>
    `<button type="button" class="star${value >= v ? ' on' : ''}" data-action="rate" data-event="${eventId}" data-v="${v}" aria-label="${v} star${v > 1 ? 's' : ''}" aria-pressed="${value === v}">${icon.star}</button>`).join('')}</div>`;

  // ───────────── Shared links: public preview before signing up ─────────────
  // What someone sees when a club or event link is opened from a group chat, email or poster.
  const INTENT_KEY = 'vnua-intent';
  const saveIntent = (it) => { try { sessionStorage.setItem(INTENT_KEY, JSON.stringify(it)); } catch {} };
  const peekIntent = () => { try { return JSON.parse(sessionStorage.getItem(INTENT_KEY) || 'null'); } catch { return null; } };
  const takeIntent = () => { const it = peekIntent(); try { sessionStorage.removeItem(INTENT_KEY); } catch {} return it; };
  function applyIntent() {
    const it = takeIntent(); if (!it) return false;
    if (it.type === 'event') { location.hash = `#/event/${it.id}`; render(); return true; }
    location.hash = `#/club/${it.id}`; render();
    const c = club(it.id);
    if (c && !membership(c.id)) setTimeout(() => joinSheet(c, it.type === 'help' ? 'organize' : 'attend'), 120);
    return true;
  }
  const previewShell = () => '<main class="screen no-tabs narrow" id="preview"><div class="spinner" style="margin:80px auto"></div></main>';
  async function loadPreview(r) {
    let data = null;
    try { data = await rpc(r.name === 'club' ? 'club_preview' : 'event_preview', r.name === 'club' ? { p_club: r.id } : { p_event: r.id }); } catch (e) { console.error(e); }
    const box = $('#preview'); if (!box || route().id !== r.id) return;
    const signInBar = `<p class="footnote" style="text-align:center">Already on Vnua-connect? <button class="link-btn" data-action="preview-go" data-v="signin">Sign in</button></p>`;
    if (!data) { box.innerHTML = `<div class="empty"><h2>This link isn’t available</h2><p>The ${r.name} may be private, still forming, or removed.</p>
      <button class="btn primary" style="max-width:260px;margin:16px auto 0" data-action="preview-go" data-v="signin">Sign in to Vnua-connect</button></div>`; return; }
    if (r.name === 'club') {
      const c = data, ne = c.next_event;
      box.innerHTML = `<div class="stack-l" style="padding-top:24px">
        <div class="stack" style="gap:10px">${mono(c, 76)}<h1 style="font-size:30px;font-weight:800">${esc(c.name)}</h1>
          <p class="muted">${esc(c.blurb)}</p>
          <div class="badges">${badge(c.interest)}${badge(recogLabel[c.recognition], c.recognition === 'recognized' ? 'success' : '')}${badge(plural(c.members, 'member'))}</div></div>
        <div class="card stack"><button class="btn primary" data-action="preview-go" data-v="join" data-id="${c.id}" data-name="${esc(c.name)}">Join ${esc(c.name)}</button>
          <button class="btn secondary" data-action="preview-go" data-v="help" data-id="${c.id}" data-name="${esc(c.name)}">Help build this group</button>
          <p class="footnote">You’ll sign in with your ${esc(c.campus || CFG.campus.name)} email. No password.</p></div>
        ${ne ? `<div class="stack"><div class="section-header">Next up</div><div class="card"><div class="event-title">${esc(ne.title)}</div>
          <div class="muted" style="font-size:15px">${esc(fmt.full(new Date(ne.starts_at)))}${ne.location ? ' · ' + esc(ne.location) : ''}</div></div></div>` : ''}
        ${c.about ? `<div class="card stack"><div class="section-header">About</div><p>${esc(c.about)}</p></div>` : ''}
        ${c.officers.length ? `<div class="card stack"><div class="section-header">E-board</div>${c.officers.map((o) => `<div class="row">${avatar(o.name, 36)}<div><strong>${esc(o.name)}</strong> <span class="footnote">· ${esc(o.title || 'Officer')}</span></div></div>`).join('')}</div>` : ''}
        ${signInBar}<p class="footnote" style="text-align:center">Student-run. Not affiliated with or endorsed by ${esc(c.campus || CFG.campus.name)}.</p></div>`;
    } else {
      const e = data, st = new Date(e.starts_at), host = e.hosts?.[0];
      box.innerHTML = `<div class="stack-l" style="padding-top:24px">
        <div class="stack" style="gap:8px">${e.status === 'cancelled' ? badge('Cancelled', 'warning') : e.status === 'rescheduled' ? badge('Rescheduled', 'warning') : ''}
          <h1 style="font-size:30px;font-weight:800">${esc(e.title)}</h1>
          <div style="color:var(--accent);font-weight:600">${esc((e.hosts || []).map((h) => h.name).join(' + '))}</div></div>
        <dl class="card facts"><div><dt>When</dt><dd>${esc(fmt.full(st))}</dd></div>${e.location ? `<div><dt>Where</dt><dd>${esc(e.location)}</dd></div>` : ''}</dl>
        ${newcomerHTML(e.newcomer)}
        ${e.details ? `<p>${esc(e.details)}</p>` : ''}
        ${e.status !== 'cancelled' ? `<div class="card stack"><button class="btn primary" data-action="preview-go" data-v="event" data-id="${e.id}" data-name="${esc(e.title)}">RSVP</button>
          ${host ? `<a class="btn secondary" href="#/club/${host.id}">About ${esc(host.name)}</a>` : ''}
          <p class="footnote">You’ll sign in with your ${esc(CFG.campus.name)} email. No password.</p></div>` : ''}
        ${signInBar}</div>`;
    }
  }

  // ───────────── Sign in (6-digit code) ─────────────
  function signInView() {
    const s = S.signin;
    const wait = Math.max(0, 60 - Math.floor((Date.now() - s.sentAt) / 1000));
    const intro = `<div class="stack"><div class="app-mark" aria-hidden="true">${icon.clubs}</div>
        <h1 class="large-title" style="margin:0">Vnua-connect</h1>
        <p class="muted">Find new student clubs at ${esc(CFG.campus.name)}, join or start one, and check in at events.</p></div>`;
    const it = peekIntent();
    const ctx = it ? `<div class="card notice-card"><strong>${it.type === 'event' ? 'RSVP to' : it.type === 'help' ? 'Help build' : 'Join'} ${esc(it.name || '')}</strong><span class="muted">Sign in first. It takes a minute, and we’ll bring you right back.</span></div>` : '';
    const backBtn = s.show ? '<div class="topbar"><button class="back" data-action="preview-back">‹ Back</button></div>' : '';
    if (!s.sent) return `<main class="screen no-tabs narrow">${backBtn}<div class="stack-l" style="padding-top:${backBtn ? 8 : 48}px">${ctx}${intro}
      <form id="signin" class="stack" novalidate>
        <label class="field"><span>School email</span><input class="input" name="email" type="email" inputmode="email" autocomplete="email"
          autocapitalize="off" spellcheck="false" placeholder="you@pride.hofstra.edu" value="${esc(s.email)}" required></label>
        <button class="btn primary" type="submit" ${s.busy ? 'disabled' : ''}>${s.busy ? 'Sending…' : 'Send me a code'}</button>
      </form>
      <p class="footnote">No password. We email you a 6-digit code, and you stay signed in on this device until you sign out.
        Vnua-connect is student-run and not affiliated with or endorsed by ${esc(CFG.campus.name)}.</p></div></main>`;
    return `<main class="screen no-tabs narrow"><div class="stack-l" style="padding-top:48px">
      <div class="stack"><h1 class="large-title" style="margin:0">Check your email</h1>
        <p class="muted">We sent a code to <strong>${esc(s.email)}</strong>. It can take a minute, and it might land in junk.</p></div>
      <form id="signin" class="stack" novalidate>
        <label class="field"><span>6-digit code</span><input class="input code-input" name="code" inputmode="numeric" pattern="[0-9]*"
          autocomplete="one-time-code" maxlength="8" placeholder="••••••" required></label>
        <button class="btn primary" type="submit" ${s.busy ? 'disabled' : ''}>${s.busy ? 'Checking…' : 'Sign in'}</button>
        <div class="row" style="justify-content:space-between">
          <button class="link-btn" type="button" data-action="signin-reset">Different email</button>
          <button class="link-btn" type="button" data-action="signin-resend" id="resend" ${wait ? 'disabled' : ''}>${wait ? `Resend in ${wait}s` : 'Resend code'}</button>
        </div>
      </form>
      <p class="footnote">If the email has a link instead of a code, open it in this browser. Codes expire after 10 minutes.</p></div></main>`;
  }
  const campusAllows = (email) => {
    const d = (email.split('@')[1] || '').toLowerCase();
    return CFG.campus.emailDomains.some((x) => d === x || d.endsWith('.' + x));
  };
  async function sendCode() {
    const s = S.signin;
    s.busy = true; render();
    const ok = await run(() => q(sb.auth.signInWithOtp({ email: s.email, options: { shouldCreateUser: true, emailRedirectTo: HERE } })).then(() => true));
    s.busy = false; if (ok) { s.sent = true; s.sentAt = Date.now(); } render();
  }
  function bindSignIn() {
    const form = $('#signin');
    form.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const s = S.signin;
      if (!s.sent) {
        s.email = form.email.value.trim().toLowerCase();
        if (!campusAllows(s.email)) return toast(`Use your ${CFG.campus.name} email address.`, true);
        return sendCode();
      }
      const code = form.code.value.replace(/\D/g, '');
      if (!/^\d{6,8}$/.test(code)) return toast('Enter the 6-digit code from the email.', true);
      s.busy = true; render();
      const ok = await run(() => q(sb.auth.verifyOtp({ email: s.email, token: code, type: 'email' })).then(() => true));
      if (!ok) { s.busy = false; render(); $('#signin')?.code?.focus(); }   // on success onAuthStateChange signs in
    });
    if (S.signin.sent) {
      const input = form.code; input.focus();
      input.addEventListener('input', () => { if (input.value.replace(/\D/g, '').length === 6 && !S.signin.busy) form.requestSubmit(); });
      const t = setInterval(() => {
        const b = $('#resend'); if (!b) return clearInterval(t);
        const wait = Math.max(0, 60 - Math.floor((Date.now() - S.signin.sentAt) / 1000));
        b.disabled = wait > 0; b.textContent = wait ? `Resend in ${wait}s` : 'Resend code';
        if (!wait) clearInterval(t);
      }, 1000);
      cleanup.push(() => clearInterval(t));
    } else form.email.focus();
  }

  // ───────────── Onboarding ─────────────
  function startOnboarding() {
    const u = S.user, local = (u.email || '').split('@')[0];
    S.ob = { step: 0, name: u.name === local ? '' : u.name, major: u.major || '', year: u.class_year || '', pronouns: u.pronouns || '',
      interests: [...(u.interests || [])], phone: u.phone || '', linkedin: u.linkedin || '', bio: u.bio || '',
      share_email: u.share_email, share_phone: u.share_phone, share_linkedin: u.share_linkedin ?? true, discoverable: true };
  }
  function obView() {
    const o = S.ob, st = o.step;
    const dots = `<div class="dots" aria-label="Step ${st} of 3">${[1, 2, 3].map((i) => `<span class="${i <= st ? 'on' : ''}"></span>`).join('')}</div>`;
    const nav = (next = 'Continue') => `<div class="ob-nav"><button class="btn primary" data-action="ob-next">${next}</button>
      ${st > 0 ? '<button class="link-btn" data-action="ob-back">Back</button>' : ''}</div>`;
    let body;
    if (st === 0) body = `<div class="stack-l ob-hero"><div class="app-mark" aria-hidden="true">${icon.clubs}</div>
        <h1 class="large-title" style="margin:0">Welcome to Vnua-connect</h1>
        <p class="muted" style="font-size:19px">The place for the clubs that are just getting started. First, a quick profile so clubs and people with the same interests can find you.</p>
        <p class="footnote">Takes about a minute. You can change all of it later in Profile.</p>
        <div class="ob-nav"><button class="btn primary" data-action="ob-next">Let’s go</button></div></div>`;
    else if (st === 1) body = `${dots}<h1 class="ob-title">About you</h1><div class="stack-l">
        <label class="field"><span>Name</span><input class="input" data-ob="name" value="${esc(o.name)}" autocomplete="name" maxlength="80" placeholder="First and last name"></label>
        <label class="field"><span>Major</span><input class="input" data-ob="major" value="${esc(o.major)}" maxlength="80" placeholder="e.g. Computer Science, Undeclared"></label>
        <div class="field"><span>Year</span><div class="chip-wrap">${YEARS.map((y) => `<button type="button" class="chip" data-action="ob-year" data-v="${esc(y)}" aria-pressed="${o.year === y}">${esc(y)}</button>`).join('')}</div></div>
        <label class="field"><span>Pronouns <span class="muted" style="font-weight:400">(optional)</span></span><input class="input" data-ob="pronouns" value="${esc(o.pronouns)}" maxlength="30" placeholder="e.g. she/her"></label>
      </div>${nav()}`;
    else if (st === 2) body = `${dots}<h1 class="ob-title">What are you into?</h1>
      <p class="muted" style="margin-bottom:16px">Pick up to 3. We’ll show you clubs and people that match.</p>
      <div class="chip-wrap big">${INTERESTS.map((i) => `<button type="button" class="chip" data-action="ob-interest" data-v="${esc(i)}" aria-pressed="${o.interests.includes(i)}">${esc(i)}</button>`).join('')}</div>
      <p class="footnote" style="margin-top:12px">${o.interests.length} of 3 picked</p>${nav()}`;
    else if (st === 3) body = `${dots}<h1 class="ob-title">How people can reach you</h1>
      <p class="muted" style="margin-bottom:16px">All optional. Only what you switch on is shown, and only to students here.</p>
      <div class="stack-l">
        <label class="field"><span>Phone</span><input class="input" data-ob="phone" type="tel" inputmode="tel" autocomplete="tel" value="${esc(o.phone)}" maxlength="30" placeholder="(516) 555-0100"></label>
        <label class="field"><span>LinkedIn</span><input class="input" data-ob="linkedin" type="url" inputmode="url" autocapitalize="off" value="${esc(o.linkedin)}" maxlength="200" placeholder="linkedin.com/in/your-name"></label>
        <label class="field"><span>A line about you</span><input class="input" data-ob="bio" value="${esc(o.bio)}" maxlength="280" placeholder="e.g. Looking for people to start a climbing club"></label>
        <div class="card toggles">
          ${toggle('discoverable', 'Let students with the same interests find me', 'You’ll show up in People, and you’ll see them too.', o.discoverable, 'ob')}
          ${toggle('share_email', 'Show my school email', '', o.share_email, 'ob')}
          ${toggle('share_phone', 'Show my phone number', '', o.share_phone, 'ob')}
          ${toggle('share_linkedin', 'Show my LinkedIn', '', o.share_linkedin, 'ob')}
        </div>
        <p class="footnote">Officers of clubs you join always see your name and school email, the same as a club roster.</p>
      </div>${nav('Save profile')}`;
    else if (peekIntent()) body = `<div class="stack-l ob-hero"><h1 class="large-title" style="margin:0">You’re all set${o.name ? ', ' + esc(o.name.split(' ')[0]) : ''}.</h1>
        <button class="card choice-card" data-action="ob-finish" data-v="intent"><strong>Continue to ${esc(peekIntent().name || 'where you were')}</strong><span class="muted">Pick up where you left off.</span></button></div>`;
    else body = `<div class="stack-l ob-hero"><h1 class="large-title" style="margin:0">You’re all set${o.name ? ', ' + esc(o.name.split(' ')[0]) : ''}.</h1>
        <p class="muted" style="font-size:19px">What do you want to do first?</p>
        <button class="card choice-card" data-action="ob-finish" data-v="join"><strong>Join a club</strong><span class="muted">See clubs that match ${o.interests.length ? esc(o.interests.join(', ')) : 'what you like'}.</span></button>
        <button class="card choice-card" data-action="ob-finish" data-v="create"><strong>Start a club</strong><span class="muted">Name it, add a logo, and invite your president, VP, treasurer and secretary.</span></button>
        <button class="link-btn" data-action="ob-finish" data-v="look" style="justify-self:start">Just look around</button></div>`;
    return `<main class="screen no-tabs narrow ob">${body}</main>`;
  }
  function toggle(key, label, sub, on, scope) {
    return `<label class="toggle"><span class="spacer"><span style="font-weight:600">${esc(label)}</span>${sub ? `<br><span class="footnote">${esc(sub)}</span>` : ''}</span>
      <input type="checkbox" role="switch" ${scope === 'ob' ? `data-ob="${key}"` : `name="${key}"`} ${on ? 'checked' : ''}></label>`;
  }
  after.ob = () => { $('[data-ob]:not([type=checkbox])')?.focus({ preventScroll: true }); };
  async function obNext() {
    const o = S.ob;
    if (o.step === 1) {
      if (!o.name.trim()) return toast('Add your name.', true);
      if (!o.year) return toast('Pick your year.', true);
    }
    if (o.step === 2 && !o.interests.length) return toast('Pick at least one interest.', true);
    if (o.step === 3) {
      const ok = await run(() => rpc('save_profile', { p_name: o.name.trim(), p_major: o.major.trim(), p_year: o.year, p_pronouns: o.pronouns.trim(),
        p_interests: o.interests, p_bio: o.bio.trim(), p_phone: o.phone.trim(), p_linkedin: o.linkedin.trim(), p_share_email: o.share_email,
        p_share_phone: o.share_phone, p_share_linkedin: o.share_linkedin, p_discoverable: o.discoverable, p_leaderboard: true }).then(() => true));
      if (!ok) return;
      S.user = await run(() => loadProfile(S.user.id)) || S.user;
    }
    o.step++; render(); window.scrollTo(0, 0);
  }

  // ───────────── Discover ─────────────
  function discoverView() {
    const chips = [`<button class="chip" data-action="interest" data-v="" aria-pressed="${!S.interest}">All</button>`]
      .concat([...new Set(S.clubs.map((c) => c.interest))].sort().map((i) => `<button class="chip" data-action="interest" data-v="${esc(i)}" aria-pressed="${S.interest === i}">${esc(i)}</button>`)).join('');
    return `${titleBar('Discover')}<div class="stack-l">
      ${myInvites().length ? `<a class="card notice-card" href="#/inbox"><strong>You’re invited to an officer team</strong><span class="muted">${esc(myInvites().map((i) => `${i.position} of ${club(i.club_id)?.name || 'a club'}`).join(' · '))}</span></a>` : ''}
      <label class="search"><span class="sr">Search clubs</span><input class="input" id="search" type="search" placeholder="Clubs and interests" value="${esc(S.q)}" autocomplete="off"></label>
      <div class="chips" role="group" aria-label="Interests">${chips}</div>
      <div id="discover-body" class="stack-l">${discoverBody()}</div></div>`;
  }
  function discoverBody() {
    const ql = S.q.toLowerCase();
    const list = visibleClubs().filter((c) => (!S.interest || c.interest === S.interest) &&
      (!ql || [c.name, c.blurb, c.interest].some((t) => t.toLowerCase().includes(ql))));
    const soon = visibleEvents().filter((e) => e.status !== 'cancelled' && e.end > new Date()).slice(0, 5);
    const mine = S.user.interests || [];
    const forYou = !S.q && !S.interest ? visibleClubs().filter((c) => mine.includes(c.interest) && !membership(c.id)).slice(0, 4) : [];
    return `${forYou.length ? `<div class="section-header">Picked for you</div><div class="stack">${forYou.map(clubRow).join('')}</div>` : ''}
      ${!S.q && !S.interest && soon.length ? `<div class="section-header">Happening soon</div><div class="hscroll">${soon.map(eventCard).join('')}</div>` : ''}
      <div class="section-header">${esc(S.interest || 'All clubs')}</div>
      <div class="stack">${list.map(clubRow).join('') || `<div class="empty"><h2>${S.clubs.length ? 'No matches' : 'No clubs yet'}</h2>
        <p>${S.clubs.length ? 'Try a different search.' : 'Be the first.'}</p>${S.clubs.length ? '' : '<a class="btn primary" href="#/new-club" style="max-width:240px;margin:16px auto 0">Start a club</a>'}</div>`}</div>`;
  }
  after.discover = () => {
    const s = $('#search');
    s?.addEventListener('input', () => { S.q = s.value; $('#discover-body').innerHTML = discoverBody(); });
  };

  // ───────────── Club ─────────────
  function clubView(id) {
    const c = club(id);
    if (!c) return `${back('#/discover', 'Discover')}</div><div class="empty"><h2>Club not found</h2><p>It may have been removed or blocked.</p></div>`;
    const m = membership(c.id), officer = isOfficer(c.id), invite = myInvites().find((i) => i.club_id === c.id);
    const now = new Date();
    const upcoming = S.events.filter((e) => e.hosts.includes(c.id) && e.end > now);
    const past = S.events.filter((e) => e.hosts.includes(c.id) && e.end <= now).reverse().slice(0, 5);
    const memberCard = m ? `<div class="card stack">
        ${m.status === 'pending' ? `<p class="notice warning">Join request sent. An officer will review it.</p>`
          : `<p style="color:var(--success);font-weight:600">${m.role === 'officer' ? `You’re the ${esc(m.officer_title || 'officer')}` : `You’re ${m.role === 'founding' ? 'a founding member' : 'a member'}`}</p>`}
        ${m.status === 'active' ? `<div class="stack" data-mem-card="${c.id}">
          <label class="field"><span>How involved</span><select class="input" data-mem="involvement">${INVOLVE.map(([k, v]) => `<option value="${k}" ${m.involvement === k ? 'selected' : ''}>${v}</option>`).join('')}</select></label>
          <label class="field"><span>Notifications from this club</span><select class="input" data-mem="notify">
            ${NOTIFY.map(([k, v]) => `<option value="${k}" ${m.notify === k ? 'selected' : ''}>${v}</option>`).join('')}</select></label>
          ${m.role !== 'officer' ? `<label class="toggle"><span class="spacer"><span style="font-weight:600">Count me for the recognition request</span><br><span class="footnote">Officers may include your name and school email.</span></span>
            <input type="checkbox" role="switch" data-mem="recognition" ${m.recognition_ok ? 'checked' : ''}></label>` : ''}</div>` : ''}
        <button class="link-btn danger" data-action="leave" data-club="${c.id}" style="justify-self:start">${m.status === 'pending' ? 'Cancel request' : 'Leave club'}</button></div>`
      : invite ? '' : `<div class="card stack"><button class="btn primary" data-action="join" data-club="${c.id}">${c.requires_approval ? 'Request to join' : 'Join club'}</button>
        ${c.requires_approval ? '<p class="footnote">Officers approve new members for this club.</p>' : ''}</div>`;
    const officers = c.officers.map((o) => `<div class="person">${avatar(o.name)}<div class="spacer">
        <div style="font-weight:700">${esc(o.name)}</div><div class="footnote" style="color:var(--accent);font-weight:600">${esc(o.title)}</div>
        ${o.major || o.class_year ? `<div class="footnote">${esc([o.major, o.class_year].filter(Boolean).join(' · '))}</div>` : ''}
        ${o.ask_about ? `<div class="ask">Contact me about ${esc(o.ask_about.replace(/^about\s+/i, ''))}</div>` : ''}
        ${contactButtons(o)}</div></div>`).join('');
    return `${back('#/discover', 'Discover')}<button class="icon-btn" data-action="club-menu" data-club="${c.id}" aria-label="More">⋯</button></div>
      <div class="stack-l">
        <div class="stack" style="gap:10px">${mono(c, 76)}<h1 style="font-size:28px;font-weight:800">${esc(c.name)}</h1>
          <p class="muted">${esc(c.blurb)}</p><div class="badges">${badge(c.interest)}${clubStatusBadge(c)}${badge(recogLabel[c.recognition], c.recognition === 'recognized' ? 'success' : '')}${c.funded ? badge('Funded', 'accent') : ''}</div></div>
        ${invite ? `<div class="card stack invite-card"><strong>You’re invited to be ${esc(invite.position)}</strong>
          <p class="muted" style="font-size:15px">If you accept, your name, position and school email show on this page so students can reach you.</p>
          <div class="row"><button class="btn secondary" data-action="invite-answer" data-id="${invite.id}" data-v="0">Decline</button><button class="btn primary" data-action="invite-answer" data-id="${invite.id}" data-v="1">Accept</button></div></div>` : ''}
        ${!c.is_published && !officer ? `<div class="card notice warning">This club is still forming. Students see it once its four officers are in and a moderator has reviewed it.</div>` : ''}
        ${officer ? teamCard(c) : ''}
        ${memberCard}
        ${officer ? `<div class="officer-actions"><a class="btn primary" href="#/dash/${c.id}">Officer dashboard</a>
          <button class="btn secondary" data-action="new-event" data-club="${c.id}">New event</button>
          <div class="row"><button class="btn secondary" data-action="new-poll" data-club="${c.id}">Find a time</button><button class="btn secondary" data-action="announce" data-club="${c.id}">Announcement</button></div>
          ${c.is_published ? `<button class="btn secondary" data-action="share" data-club="${c.id}">Share the club link</button>` : ''}</div>
          ${c.requires_approval ? `<div class="card stack" id="join-requests"><div class="section-header">Join requests</div><p class="footnote">Loading…</p></div>` : ''}` : ''}
        ${c.about || c.affiliation ? `<div class="card stack"><div class="section-header">About</div>${c.about ? `<p>${esc(c.about)}</p>` : ''}${c.affiliation ? `<p class="footnote">${esc(c.affiliation)}</p>` : ''}</div>` : ''}
        ${c.officers.length ? `<div class="stack"><div class="section-header">E-board</div><div class="card people">${officers}</div></div>` : ''}
        ${isMember(c.id) ? `<div class="stack" id="polls"></div><div class="stack" id="leaderboard"></div>` : ''}
        <div class="stack"><div class="section-header">Upcoming</div>${upcoming.map(eventRow).join('') || '<p class="muted" style="font-size:15px">Nothing scheduled yet.</p>'}</div>
        ${past.length ? `<div class="stack"><div class="section-header">Past events</div>${past.map(eventRow).join('')}</div>` : ''}
      </div>`;
  }
  /** Officers see who holds each of the four core positions, open slots, and pending invites. */
  function teamCard(c) {
    const inv = clubInvites(c.id), n = coreFilled(c);
    const row = (title) => {
      const o = c.officers.find((x) => x.title.toLowerCase() === title.toLowerCase());
      if (o) return `<div class="slot filled"><span class="slot-t">${esc(title)}</span><span class="spacer">${esc(o.name)}</span><span class="tick">✓</span></div>`;
      const i = inv.find((x) => x.position.toLowerCase() === title.toLowerCase());
      if (i) return `<div class="slot pending"><span class="slot-t">${esc(title)}</span><span class="spacer footnote">Invited ${esc(i.email)}</span>
        <button class="link-btn danger" data-action="revoke-invite" data-id="${i.id}">Cancel</button></div>`;
      return `<div class="slot open"><span class="slot-t">${esc(title)}</span><span class="spacer footnote">Open</span>
        <button class="btn primary small" data-action="invite" data-club="${c.id}" data-v="${esc(title)}">Invite</button></div>`;
    };
    const extras = [...c.officers.filter((o) => !CORE.some((t) => t.toLowerCase() === o.title.toLowerCase())).map((o) => o.title),
      ...inv.filter((i) => !CORE.some((t) => t.toLowerCase() === i.position.toLowerCase())).map((i) => i.position)];
    return `<div class="card stack team"><div class="row"><div class="section-header spacer" style="margin:0">Officer team</div>
        <span class="badge ${n === 4 ? 'success' : 'warning'}">${n}/4 core</span></div>
      ${n < 4 ? `<p class="footnote">A club goes live once a president, vice president, treasurer and secretary have all accepted. ${c.is_published ? '' : 'Then a moderator reviews it, usually within a day.'}</p>` : c.is_published ? '' : '<p class="footnote">All four are in. A moderator will review the club next, usually within a day.</p>'}
      <div>${CORE.map(row).join('')}${extras.map(row).join('')}</div>
      <button class="link-btn" data-action="invite" data-club="${c.id}" data-v="" style="justify-self:start">＋ Add another position</button></div>`;
  }
  after.club = async (id) => {
    if (isMember(id)) {
      const [polls, votes] = await Promise.all([
        run(() => q(sb.from('polls').select('*, poll_slots(*)').eq('club_id', id).is('closed_at', null).gt('deadline', new Date().toISOString()))),
        run(() => q(sb.from('poll_votes').select('*').eq('user_id', S.user.id))),
      ]);
      const pbox = $('#polls');
      if (pbox && polls?.length) {
        const mine = Object.fromEntries((votes || []).map((v) => [v.slot_id, v.answer]));
        pbox.innerHTML = `<div class="section-header">When works for you?</div>${polls.map((p) => `<div class="card stack"><strong>${esc(p.title)}</strong>
          <p class="footnote">Reply by ${esc(fmt.full(new Date(p.deadline)))}. Only totals are shared with officers.</p>
          ${p.poll_slots.sort((a, b) => a.starts_at.localeCompare(b.starts_at)).map((sl) => `<div class="slot-row"><span class="spacer" style="font-weight:600">${esc(fmt.full(new Date(sl.starts_at)))}</span>
            <div class="vote segmented" role="group" aria-label="Can you make it?">${[['yes', 'Yes'], ['maybe', 'Maybe'], ['no', 'No']].map(([v, l]) => `<button data-action="vote" data-slot="${sl.id}" data-v="${v}" aria-pressed="${mine[sl.id] === v}">${l}</button>`).join('')}</div></div>`).join('')}</div>`).join('')}`;
      }
      const rows = await run(() => rpc('club_leaderboard', { p_club: id }));
      const box = $('#leaderboard');
      if (rows && box) box.innerHTML = rows.length ? `<div class="section-header">Most involved</div><div class="card">${rows.slice(0, 10).map((r) =>
        `<div class="list-row${r.is_me ? ' me' : ''}"><span class="rank">${r.rank}</span><span class="spacer">${esc(r.name)}${r.is_me ? ' <span class="footnote">(you)</span>' : ''}</span><span class="footnote">${plural(r.attended, 'event')}</span></div>`).join('')}
        ${rows.length > 10 && rows.slice(10).some((r) => r.is_me) ? `<div class="list-row me"><span class="rank">${rows.find((r) => r.is_me).rank}</span><span class="spacer">You</span></div>` : ''}</div>
        <p class="footnote">Counts check-ins. Officers aren’t ranked. You can hide yourself in Profile.</p>` : '';
    }
    if (!isOfficer(id) || !club(id)?.requires_approval) return;
    const box = $('#join-requests'); if (!box) return;
    const reqs = await run(() => rpc('join_requests', { p_club: id }));
    if (!reqs || !$('#join-requests')) return;
    box.innerHTML = `<div class="section-header">Join requests · ${reqs.length}</div>${reqs.length ? reqs.map((r) => `<div class="list-row">
      <div class="spacer"><div style="font-weight:600">${esc(r.name)}</div><div class="footnote">${esc(roleLabel[r.role])} · ${fmt.rel(new Date(r.requested_at))}</div></div>
      <button class="btn secondary small" data-action="review" data-club="${id}" data-user="${r.user_id}" data-approve="0" aria-label="Decline ${esc(r.name)}">✕</button>
      <button class="btn primary small" data-action="review" data-club="${id}" data-user="${r.user_id}" data-approve="1" aria-label="Approve ${esc(r.name)}">✓</button></div>`).join('')
      : '<p class="footnote">No one is waiting.</p>'}`;
  };

  // ───────────── Start a club (full page, 3 steps) ─────────────
  function newClub() {
    S.nc = { step: 1, name: '', blurb: '', interest: (S.user.interests || [])[0] || INTERESTS[0], about: '', approval: false,
      accent: ACCENTS[0][0], logoBlob: null, logoPreview: '', position: 'President', emails: {}, extra: [], busy: '' };
  }
  const monogramOf = (name) => {
    const w = name.split(/\s+/).filter((x) => x && !['&', 'and', 'the', 'of', 'club'].includes(x.toLowerCase()));
    return (w.slice(0, 2).map((x) => x[0]).join('') || '?').toUpperCase();
  };
  function newClubView() {
    if (!S.nc) newClub();
    const n = S.nc, st = n.step;
    const steps = ['The basics', 'Logo', 'Officer team'];
    const head = `${back('#/mine', 'Cancel')}</div><div class="dots" aria-label="Step ${st} of 3">${[1, 2, 3].map((i) => `<span class="${i <= st ? 'on' : ''}"></span>`).join('')}</div>
      <h1 class="ob-title">${steps[st - 1]}</h1>`;
    if (n.busy) return `${head}<div class="empty"><div class="spinner" style="margin:0 auto 16px"></div><h2>${esc(n.busy)}</h2></div>`;
    const navBtns = (label) => `<div class="ob-nav"><button class="btn primary" data-action="nc-next">${label}</button>${st > 1 ? '<button class="link-btn" data-action="nc-back">Back</button>' : ''}</div>`;
    if (st === 1) return `${head}<div class="stack-l">
      <label class="field"><span>Club name</span><input class="input" data-nc="name" value="${esc(n.name)}" maxlength="80" placeholder="e.g. Hofstra Climbing Club"></label>
      <label class="field"><span>What’s the point?</span><input class="input" data-nc="blurb" value="${esc(n.blurb)}" maxlength="160" placeholder="One line. e.g. Bouldering trips and beginner nights"></label>
      <label class="field"><span>Interest</span><select class="input" data-nc="interest">${INTERESTS.map((i) => `<option ${n.interest === i ? 'selected' : ''}>${esc(i)}</option>`).join('')}</select></label>
      <label class="field"><span>More about it <span class="muted" style="font-weight:400">(optional)</span></span><textarea class="input" data-nc="about" maxlength="2000" placeholder="Who it’s for, how often you meet, what a first meeting looks like">${esc(n.about)}</textarea></label>
      <div class="card toggles">${toggle('approval', 'Officers approve new members', 'Leave off so anyone can join right away.', n.approval, 'nc').replace('name="approval"', 'data-nc="approval"')}</div>
      ${navBtns('Next')}</div>`;
    if (st === 2) return `${head}<div class="stack-l">
      <p class="muted">Upload your logo, or use your initials and a color for now. You can change it later.</p>
      <div class="logo-pick">
        ${n.logoPreview ? `<img class="logo" src="${esc(n.logoPreview)}" alt="Logo preview" width="120" height="120">`
          : `<div class="mono" style="width:120px;height:120px;font-size:44px;background:${esc(n.accent)}">${esc(monogramOf(n.name))}</div>`}
        <div class="stack" style="gap:8px">
          <label class="btn secondary small file-btn">${n.logoPreview ? 'Choose a different image' : 'Upload logo'}<input type="file" accept="image/png,image/jpeg,image/webp,image/heic" data-file="nc-logo" class="sr"></label>
          ${n.logoPreview ? '<button class="link-btn danger" data-action="nc-clear-logo" style="text-align:left">Remove</button>' : ''}
          <span class="footnote">Square works best. We crop it to a square.</span></div></div>
      ${n.logoPreview ? '' : `<div class="field"><span>Color</span><div class="swatches">${ACCENTS.map(([h, nm]) => `<button type="button" class="swatch" style="background:${h}" data-action="nc-accent" data-v="${h}" aria-label="${nm}" aria-pressed="${n.accent === h}"></button>`).join('')}</div></div>`}
      ${navBtns('Next')}</div>`;
    const others = CORE.filter((t) => t !== n.position);
    return `${head}<div class="stack-l">
      <p class="muted">Every club on Vnua-connect has a president, vice president, treasurer and secretary. Invite them with their school email. The club goes live once all four accept.</p>
      <label class="field"><span>Your position</span><select class="input" data-nc="position">${CORE.map((t) => `<option ${n.position === t ? 'selected' : ''}>${t}</option>`).join('')}</select></label>
      <div class="stack">${others.map((t) => `<label class="field"><span>${t}</span><input class="input" type="email" inputmode="email" autocapitalize="off" spellcheck="false"
          data-nc-email="${t}" value="${esc(n.emails[t] || '')}" placeholder="their school email"></label>`).join('')}</div>
      ${n.extra.map((x, i) => `<div class="card stack extra"><label class="field"><span>Position</span><input class="input" data-nc-extra="${i}" data-k="title" value="${esc(x.title)}" maxlength="40" placeholder="e.g. Social media chair"></label>
        <label class="field"><span>Email</span><input class="input" type="email" inputmode="email" autocapitalize="off" data-nc-extra="${i}" data-k="email" value="${esc(x.email)}" placeholder="their school email"></label>
        <button class="link-btn danger" data-action="nc-del-extra" data-v="${i}" style="justify-self:start">Remove</button></div>`).join('')}
      <button class="link-btn" data-action="nc-add-extra" style="justify-self:start">＋ Add another position</button>
      <p class="footnote">Don’t have everyone yet? Leave a spot blank and invite them later from the club page.</p>
      ${navBtns('Create club')}</div>`;
  }
  /** Center-crop to a 512px square JPEG. Also strips photo metadata (location etc.). */
  async function squareImage(file, size = 512) {
    const url = URL.createObjectURL(file);
    try {
      const img = await new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => rej(new Error('validation|That image couldn’t be opened. Try a PNG or JPEG.')); i.src = url; });
      const s = Math.min(img.naturalWidth, img.naturalHeight);
      const cv = Object.assign(document.createElement('canvas'), { width: size, height: size });
      const cx = cv.getContext('2d'); cx.fillStyle = '#fff'; cx.fillRect(0, 0, size, size);
      cx.drawImage(img, (img.naturalWidth - s) / 2, (img.naturalHeight - s) / 2, s, s, 0, 0, size, size);
      return await new Promise((res) => cv.toBlob(res, 'image/jpeg', 0.86));
    } finally { URL.revokeObjectURL(url); }
  }
  async function uploadLogo(clubId, blob) {
    const path = `${clubId}/logo-${Date.now()}.jpg`;
    await q(sb.storage.from('club-logos').upload(path, blob, { contentType: 'image/jpeg', upsert: false }));
    const url = sb.storage.from('club-logos').getPublicUrl(path).data.publicUrl;
    await rpc('set_club_logo', { p_club: clubId, p_url: url });
  }
  async function ncNext() {
    const n = S.nc;
    if (n.step === 1) {
      if (n.name.trim().length < 2) return toast('Give the club a name.', true);
      if (!n.blurb.trim()) return toast('Say what the club is for, in one line.', true);
      if (S.clubs.some((c) => c.name.toLowerCase() === n.name.trim().toLowerCase())) return toast('A club with that name already exists.', true);
    }
    if (n.step < 3) { n.step++; render(); window.scrollTo(0, 0); return; }
    const invites = [...CORE.filter((t) => t !== n.position).map((t) => ({ title: t, email: (n.emails[t] || '').trim().toLowerCase() })),
      ...n.extra.map((x) => ({ title: x.title.trim(), email: x.email.trim().toLowerCase() }))].filter((x) => x.email);
    const bad = invites.find((x) => !campusAllows(x.email) || x.email === S.user.email || (x.title.length < 2));
    if (bad) return toast(bad.title.length < 2 ? 'Name each extra position.' : bad.email === S.user.email ? 'You can’t invite yourself.' : `${bad.email} isn’t a ${CFG.campus.name} email.`, true);
    if (new Set(invites.map((x) => x.email)).size !== invites.length) return toast('Each person can hold one position.', true);
    n.busy = 'Creating your club…'; render();
    const name = n.name.trim();
    const id = await run(() => rpc('create_club', { p_name: name, p_interest: n.interest, p_blurb: n.blurb.trim(), p_about: n.about.trim(),
      p_monogram: monogramOf(name), p_accent: n.accent, p_requires_approval: n.approval, p_position: n.position }));
    if (!id) { n.busy = ''; render(); return; }
    if (n.logoBlob) { n.busy = 'Uploading the logo…'; render(); await run(() => uploadLogo(id, n.logoBlob)); }
    const failed = [];
    if (invites.length) { n.busy = 'Sending invites…'; render(); }
    for (const x of invites) {
      try { await rpc('invite_officer', { p_club: id, p_email: x.email, p_position: x.title }); } catch (e) { failed.push(`${x.email}: ${errMsg(e)}`); }
    }
    if (n.logoPreview) URL.revokeObjectURL(n.logoPreview);
    S.nc = null; await run(loadAll);
    location.hash = `#/club/${id}`;
    if (failed.length) toast(`Club created, but some invites didn’t go out. ${failed[0]}`, true);
    else toast(invites.length ? `${name} created. Invites sent.` : `${name} created. Invite your officers next.`);
  }

  // ───────────── Officer dashboard ─────────────
  const dash = { tab: 'members', filter: 'all', data: null, tasks: [], polls: [], results: {}, requests: 0 };
  function dashView(id) {
    const c = club(id);
    if (!c || !isOfficer(id)) return `${back(`#/club/${id}`, 'Club')}</div><div class="empty"><h2>Officers only</h2><p>Only this club’s officers can see its dashboard.</p></div>`;
    return `${back(`#/club/${id}`, c.name)}<button class="link-btn" data-action="dash-csv" data-club="${id}">Export CSV</button></div>
      <h1 style="font-size:28px;font-weight:800;margin:8px 0 4px">Officer dashboard</h1><p class="muted" style="font-size:15px;margin-bottom:16px">${esc(c.name)} · every officer sees this</p>
      <div id="dash-body"><div class="spinner" style="margin:40px auto"></div></div>`;
  }
  // Top supporters = members who said yes to being counted for recognition, ranked by check-ins. E-board never included.
  const supportersOf = (members) => members.filter((m) => !m.is_officer && m.recognition_ok).slice(0, RECOGNITION_GOAL);
  const DAY = 864e5;
  /** Things that need an officer's attention, each with a way to deal with it. Only facts, no guesses. */
  function actionItems(id) {
    const c = club(id), d = dash.data, now = Date.now(), items = [];
    const item = (text, btn = '') => items.push(`<div class="todo"><span class="spacer">${text}</span>${btn}</div>`);
    const inv = clubInvites(id);
    CORE.forEach((t) => {
      if (c.officers.some((o) => o.title.toLowerCase() === t.toLowerCase())) return;
      const i = inv.find((x) => x.position.toLowerCase() === t.toLowerCase());
      if (!i) item(`No ${esc(t.toLowerCase())} yet`, `<button class="btn primary small" data-action="invite" data-club="${id}" data-v="${t}">Invite</button>`);
      else if (now - new Date(i.created_at) > 3 * DAY) item(`${esc(i.email)} hasn’t answered the ${esc(t.toLowerCase())} invite (${fmt.rel(new Date(i.created_at))})`, `<a class="btn secondary small" href="#/club/${id}">Manage</a>`);
    });
    if (dash.requests) item(`${plural(dash.requests, 'join request')} waiting`, `<a class="btn secondary small" href="#/club/${id}">Review</a>`);
    const upcoming = d.events.filter((e) => e.status !== 'cancelled' && new Date(e.starts_at) > now);
    upcoming.filter((e) => new Date(e.starts_at) - now < 14 * DAY).forEach((e) => {
      if (!e.location) item(`<strong>${esc(e.title)}</strong> has no location`, `<button class="btn secondary small" data-action="edit-event" data-id="${e.id}">Add</button>`);
      else if (!e.has_newcomer) item(`Add “First time?” info to <strong>${esc(e.title)}</strong>`, `<button class="btn secondary small" data-action="edit-event" data-id="${e.id}">Add</button>`);
    });
    const followed = new Set(dash.tasks.map((t) => t.event_id).filter(Boolean));
    d.events.filter((e) => e.status !== 'cancelled' && new Date(e.starts_at) < now && now - new Date(e.starts_at) < 14 * DAY && !followed.has(e.id))
      .forEach((e) => item(`What should happen after <strong>${esc(e.title)}</strong>?`, `<button class="btn secondary small" data-action="add-task" data-club="${id}" data-event="${e.id}">Follow up</button>`));
    dash.tasks.filter((t) => !t.done_at && t.due_on && new Date(t.due_on + 'T23:59') - now < 2 * DAY).forEach((t) =>
      item(`${new Date(t.due_on + 'T23:59') < now ? 'Overdue' : 'Due soon'}: ${esc(t.title)}${t.owner_id ? ` · ${esc(ownerName(id, t.owner_id))}` : ''}`,
        `<button class="btn secondary small" data-action="task-done" data-id="${t.id}" data-v="1">Done</button>`));
    dash.polls.filter((p) => !p.closed_at && new Date(p.deadline) < now).forEach((p) =>
      item(`Replies are in for “${esc(p.title)}”`, `<button class="btn secondary small" data-action="dash-tab" data-v="polls">Pick a time</button>`));
    if (!upcoming.length && !dash.polls.some((p) => !p.closed_at)) item('Nothing scheduled yet',
      `<button class="btn secondary small" data-action="new-event" data-club="${id}">Post event</button><button class="btn secondary small" data-action="new-poll" data-club="${id}">Find a time</button>`);
    return items;
  }
  const ownerName = (clubId, uid) => club(clubId)?.officers.find((o) => o.user_id === uid)?.name || 'Unassigned';
  function dashBody(id) {
    const d = dash.data, now = Date.now();
    const members = d.members.filter((m) => !m.is_officer), eboard = d.members.filter((m) => m.is_officer);
    const past = d.events.filter((e) => e.status !== 'cancelled' && new Date(e.starts_at) < now);
    const turnout = past.length ? Math.round(past.reduce((s, e) => s + e.checked_in, 0) / past.length) : 0;
    const rs = past.reduce((s, e) => s + e.rsvps, 0), sh = past.reduce((s, e) => s + e.showed, 0);
    const rated = past.filter((e) => e.rating_avg != null);
    const rating = rated.length ? (rated.reduce((s, e) => s + Number(e.rating_avg) * e.ratings, 0) / rated.reduce((s, e) => s + e.ratings, 0)).toFixed(1) : '–';
    const consented = members.filter((m) => m.recognition_ok);
    const supporters = supportersOf(d.members), supporterIds = new Set(supporters.map((m) => m.user_id));
    const fading = members.filter((m) => m.fading && !(m.nudged_at && now - new Date(m.nudged_at) < 30 * DAY));
    const goal = Math.min(100, Math.round((consented.length / RECOGNITION_GOAL) * 100));
    const todo = actionItems(id);
    let rank = 0, prev = null;
    const ranked = members.map((m, i) => { if (m.attended !== prev) { rank = i + 1; prev = m.attended; } return { ...m, rank }; });
    const skills = [...new Set(members.flatMap((m) => m.help_with || []))].sort();
    const F = { all: () => true, consent: (m) => m.recognition_ok, organize: (m) => m.involvement === 'organize',
      recent: (m) => m.attended_30 > 0, new: (m) => m.first_seen && now - new Date(m.first_seen) < 30 * DAY, quiet: (m) => m.fading };
    const filt = dash.filter.startsWith('help:') ? (m) => (m.help_with || []).includes(dash.filter.slice(5)) : F[dash.filter] || F.all;
    const shown = ranked.filter(filt);
    const memberRow = (m) => `<div class="list-row member">${m.is_officer ? avatar(m.name, 36) : `<span class="rank">${m.rank}</span>`}
      <div class="spacer"><div style="font-weight:600">${esc(m.name)}${m.is_officer ? ` <span class="footnote">· ${esc(m.title || 'Officer')}</span>` : ''}</div>
        <div class="footnote">${m.eligible ? `${m.attended} of ${plural(m.eligible, 'event')} since joining` : plural(m.attended, 'event')}${m.last_seen ? ` · last seen ${fmt.short(new Date(m.last_seen))}` : ''}</div>
        <div class="badges">${supporterIds.has(m.user_id) ? badge('Top supporter', 'success') : ''}${!m.is_officer && m.recognition_ok ? badge('Counts for recognition') : ''}${m.involvement === 'organize' && !m.is_officer ? badge('Wants to help organize', 'accent') : ''}
          ${(m.help_with || []).map((h) => badge(h)).join('')}${m.fading ? badge('Missed the last 3', 'warning') : ''}${m.busy ? badge('Busy, still in') : ''}${m.nudged_at ? badge(`Checked in with ${fmt.rel(new Date(m.nudged_at))}`) : ''}</div></div>
      ${m.email ? `<a class="icon-btn" href="mailto:${esc(m.email)}" aria-label="Email ${esc(m.name)}">${icon.mail}</a>` : ''}</div>`;
    const evRow = (e) => { const st = new Date(e.starts_at); const up = st > now;
      return `<a class="list-row" href="#/event/${e.id}" style="color:inherit;text-decoration:none"><div class="date-chip"><span class="dow">${fmt.dow(st)}</span><span class="day">${st.getDate()}</span></div>
      <div class="spacer"><div style="font-weight:600">${esc(e.title)}${e.status === 'cancelled' ? ' <span class="footnote">(cancelled)</span>' : ''}</div>
      <div class="footnote">${up ? `${plural(e.rsvps, 'RSVP')} so far` : `${e.checked_in} checked in · ${plural(e.rsvps, 'RSVP')} · ${pct(e.showed, e.rsvps)} of RSVPs came`}</div>
      ${!up && e.status !== 'cancelled' ? `<div class="footnote">${e.rating_avg != null ? `★ ${e.rating_avg} from ${plural(e.ratings, 'rating')}` : e.ratings ? `${e.ratings}/3 ratings needed to show an average` : 'No ratings yet'}</div>` : ''}</div></a>`; };
    const seg = (v, l) => `<button data-action="dash-tab" data-v="${v}" aria-pressed="${dash.tab === v}">${l}</button>`;
    const chip = (v, l) => `<button class="chip" data-action="dash-filter" data-v="${esc(v)}" aria-pressed="${dash.filter === v}">${esc(l)}</button>`;
    const tab = {
      members: () => `<div class="chips" role="group" aria-label="Filter members">${chip('all', 'Everyone')}${chip('consent', 'Counts for recognition')}${chip('organize', 'Wants to help organize')}
          ${chip('recent', 'Came in last 30 days')}${chip('new', 'First time in last 30 days')}${chip('quiet', 'Missed the last 3')}${skills.map((k) => chip('help:' + k, 'Can help: ' + k)).join('')}</div>
        <div class="card">${shown.map(memberRow).join('') || `<p class="footnote" style="padding:12px 0">${members.length ? 'No one matches this filter.' : 'No members yet. Share the club link to get your first ones.'}</p>`}</div>
        <p class="footnote">${plural(shown.length, 'member')} · ranked by check-ins. A member who came once can still be a real supporter, so use the filters, not just the rank.</p>
        <div class="section-header">E-board · not ranked</div><div class="card">${eboard.map(memberRow).join('')}</div>`,
      events: () => `<div class="card">${d.events.map(evRow).join('') || '<p class="footnote" style="padding:12px 0">No events yet.</p>'}</div>
        <p class="footnote">Ratings are anonymous. Officers only see an event’s average once 3 people have rated it.</p>`,
      tasks: () => { const open = dash.tasks.filter((t) => !t.done_at), done = dash.tasks.filter((t) => t.done_at).slice(0, 10);
        const row = (t) => `<div class="list-row task${t.done_at ? ' done' : ''}"><button class="check" data-action="task-done" data-id="${t.id}" data-v="${t.done_at ? 0 : 1}" aria-label="${t.done_at ? 'Mark not done' : 'Mark done'}" aria-pressed="${!!t.done_at}">✓</button>
          <div class="spacer"><div style="font-weight:600">${esc(t.title)}</div><div class="footnote">${esc(ownerName(id, t.owner_id))}${t.due_on ? ` · due ${fmt.short(new Date(t.due_on + 'T12:00'))}` : ''}${t.event_id && event(t.event_id) ? ` · ${esc(event(t.event_id).title)}` : ''}</div></div>
          <button class="link-btn" data-action="edit-task" data-id="${t.id}">Edit</button></div>`;
        return `<button class="btn primary" data-action="add-task" data-club="${id}">Add a task</button>
          <div class="card">${open.map(row).join('') || '<p class="footnote" style="padding:12px 0">No open tasks. Add follow-ups after events so nothing slips.</p>'}</div>
          ${done.length ? `<details class="card"><summary><strong>Done</strong> <span class="footnote">· ${done.length}</span></summary>${done.map(row).join('')}</details>` : ''}`; },
      polls: () => `<button class="btn primary" data-action="new-poll" data-club="${id}">Find a time</button>
        ${dash.polls.map((p) => { const r = dash.results[p.id]; const best = r ? Math.max(...r.slots.map((x) => x.yes + x.maybe / 2)) : 0;
          return `<div class="card stack"><div class="row"><strong class="spacer">${esc(p.title)}</strong>${p.event_id ? badge('Scheduled', 'success') : p.closed_at ? badge('Closed') : new Date(p.deadline) < now ? badge('Replies in', 'warning') : badge(`Open until ${fmt.short(new Date(p.deadline))}`)}</div>
            ${r ? `<p class="footnote">${r.responders} of ${plural(r.members, 'member')} replied. Individual answers stay private.</p>
              ${r.slots.map((x) => `<div class="slot-row"><div class="spacer"><div style="font-weight:600">${esc(fmt.full(new Date(x.starts_at)))}</div>
                <div class="footnote">${x.yes} yes · ${x.maybe} maybe · ${x.no} no</div><div class="bar"><span style="width:${r.responders ? Math.round(((x.yes + x.maybe / 2) / r.responders) * 100) : 0}%"></span></div></div>
                ${!p.closed_at ? `<button class="btn ${x.yes + x.maybe / 2 === best && best > 0 ? 'primary' : 'secondary'} small" data-action="schedule-poll" data-poll="${p.id}" data-slot="${x.id}">Pick</button>` : ''}</div>`).join('')}` : ''}
            ${p.event_id ? `<a class="link-btn" href="#/event/${p.event_id}">View the event</a>` : !p.closed_at ? `<button class="link-btn danger" data-action="close-poll" data-id="${p.id}" style="justify-self:start">Close without scheduling</button>` : ''}</div>`; }).join('')
          || '<p class="footnote">Not sure when people are free? Offer a few times, members answer yes/maybe/no, and you turn the best one into an event.</p>'}`,
    };
    return `<div class="stack-l">
      <div class="stack"><div class="section-header">Needs attention${todo.length ? ' · ' + todo.length : ''}</div>
        <div class="card todos">${todo.join('') || '<p class="footnote" style="padding:8px 0">Nothing needs attention right now.</p>'}</div></div>
      <div class="stats">${stat(members.length, 'Members', 'not counting e-board')}${stat(past.length ? turnout : '–', 'Avg turnout', plural(past.length, 'past event'))}
        ${stat(rs ? pct(sh, rs) : '–', 'RSVPs who came', rs ? `${sh} of ${rs}` : 'no RSVPs yet')}${stat(rating, 'Avg rating', rated.length ? 'anonymous' : 'needs 3+ per event')}</div>
      <div class="card stack recog">
        <div class="row"><strong class="spacer">Official recognition</strong><span class="footnote">${consented.length}/${RECOGNITION_GOAL} supporters</span></div>
        <div class="bar" role="progressbar" aria-valuenow="${consented.length}" aria-valuemin="0" aria-valuemax="${RECOGNITION_GOAL}"><span style="width:${goal}%"></span></div>
        <p class="footnote">${members.length} member${members.length === 1 ? '' : 's'}, ${consented.length} said yes to being counted (e-board not included).
          ${consented.length >= RECOGNITION_GOAL ? 'That’s enough to apply.' : `${RECOGNITION_GOAL - consented.length} more to reach ${RECOGNITION_GOAL}.`}
          Members can switch this on from the club page. This tracks your count; the university decides recognition.</p>
        <div class="officer-actions">
          <button class="btn primary" data-action="recog-mail" data-club="${id}" ${supporters.length ? '' : 'disabled'}>Draft the request email</button>
          <button class="btn secondary" data-action="copy-emails" data-v="supporters">Copy supporters’ emails (${supporters.length})</button>
          <button class="btn secondary" data-action="copy-emails" data-v="all">Copy all member emails (${d.members.length})</button></div></div>
      ${fading.length ? `<div class="card stack nudge"><strong>${plural(fading.length, 'member')} missed the last 3 events</strong>
        <p class="footnote">That’s all we know. They might just be busy. Send a friendly check-in: they can say they’re still in, that they’re busy but want to stay, or leave. Each person gets this at most once a month.</p>
        <div class="badges">${fading.map((m) => badge(m.name)).join('')}</div>
        <button class="btn secondary" data-action="nudge" data-club="${id}" data-users="${fading.map((m) => m.user_id).join(',')}">Send “Still interested?”</button></div>` : ''}
      <div class="segmented tight" role="group" aria-label="Show">${seg('members', 'Members')}${seg('events', 'Events')}${seg('tasks', 'Tasks')}${seg('polls', 'Polls')}</div>
      ${tab[dash.tab]()}</div>`;
  }
  async function loadDash(id) {
    const c = club(id);
    const [d, tasks, polls, reqs] = await Promise.all([
      rpc('club_insights', { p_club: id }),
      q(sb.from('club_tasks').select('*').eq('club_id', id).order('done_at', { ascending: false, nullsFirst: true }).order('due_on', { ascending: true, nullsFirst: false })),
      q(sb.from('polls').select('*').eq('club_id', id).order('created_at', { ascending: false }).limit(10)),
      c?.requires_approval ? rpc('join_requests', { p_club: id }) : Promise.resolve([]),
    ]);
    const results = {};
    await Promise.all(polls.filter((p) => !p.closed_at || p.event_id).slice(0, 5).map(async (p) => { results[p.id] = await rpc('poll_results', { p_poll: p.id }); }));
    Object.assign(dash, { data: d, tasks, polls, results, requests: reqs.length, club: id });
  }
  after.dash = async (id) => {
    if (!isOfficer(id)) return;
    if (dash.club !== id) Object.assign(dash, { tab: 'members', filter: 'all' });
    const ok = await run(() => loadDash(id).then(() => true));
    if (!ok || !$('#dash-body') || route().id !== id) return;
    $('#dash-body').innerHTML = dashBody(id);
  };
  const redrawDash = async () => { if (route().name === 'dash' && dash.club) { await run(() => loadDash(dash.club)); if ($('#dash-body')) $('#dash-body').innerHTML = dashBody(dash.club); } };
  function membersCsv(d) {
    const c = (s) => `"${String(s ?? '').replace(/"/g, '""')}"`;
    const top = new Set(supportersOf(d.members).map((m) => m.user_id));
    return ['name,email,major,year,role,position,involvement,counts_for_recognition,can_help_with,events_attended,events_since_joining,attended_last_30_days,rsvps,first_attended,last_attended,joined,top_supporter',
      ...d.members.map((m) => [c(m.name), c(m.email), c(m.major), c(m.class_year), m.is_officer ? 'e-board' : m.role, c(m.title), m.involvement,
        m.recognition_ok ? 'yes' : 'no', c((m.help_with || []).join('; ')), m.attended, m.eligible, m.attended_30, m.rsvps,
        m.first_seen ? m.first_seen.slice(0, 10) : '', m.last_seen ? m.last_seen.slice(0, 10) : '', m.joined_at.slice(0, 10), top.has(m.user_id) ? 'yes' : ''].join(','))].join('\n');
  }

  // ───────────── Events ─────────────
  function eventsView() {
    const now = new Date();
    const list = visibleEvents().filter((e) => e.end > new Date(now - 864e5) && (S.evScope === 'all' ? true
      : S.evScope === 'mine' ? e.hosts.some((h) => isMember(h)) : S.rsvps.has(e.id)));
    const days = [];
    list.forEach((e) => { const last = days[days.length - 1]; if (last && sameDay(last[0], e.start)) last[1].push(e); else days.push([e.start, [e]]); });
    const seg = (v, l) => `<button data-action="ev-scope" data-v="${v}" aria-pressed="${S.evScope === v}">${l}</button>`;
    return `${titleBar('Events')}<div class="stack-l">
      <div class="segmented" role="group" aria-label="Show">${seg('all', 'All events')}${seg('mine', 'My clubs')}${seg('going', 'Going')}</div>
      ${days.map(([d, evs]) => `<div class="stack"><div class="section-header">${sameDay(d, now) ? 'Today' : esc(fmt.day(d))}</div>${evs.map(eventRow).join('')}</div>`).join('')
        || '<div class="empty"><h2>No events</h2><p>Join a club or RSVP to see events here.</p></div>'}</div>`;
  }
  function eventView(id) {
    const e = event(id);
    if (!e) return `${back('#/events', 'Events')}</div><div class="empty"><h2>Event not found</h2></div>`;
    const going = S.rsvps.has(e.id), live = e.status !== 'cancelled', over = e.end < new Date();
    return `${back('#/events', 'Events')}<button class="link-btn" data-action="share-event" data-id="${e.id}">Share</button><button class="icon-btn" data-action="report" data-type="event" data-id="${e.id}" data-name="${esc(e.title)}" aria-label="Report event">⚑</button></div>
      <div class="stack-l">
        <div class="stack" style="gap:8px">${statusBadge(e) ? `<div>${statusBadge(e)}</div>` : ''}
          <h1 style="font-size:28px;font-weight:800">${esc(e.title)}</h1>
          <div style="color:var(--accent);font-weight:600;font-size:15px">${e.hosts.map((h) => club(h) ? `<a href="#/club/${h}" style="text-decoration:none">${esc(club(h).name)}</a>` : '').join(' + ')}</div></div>
        ${e.status === 'rescheduled' && e.previous_start ? `<p class="notice warning">Moved from ${esc(fmt.full(new Date(e.previous_start)))}</p>` : ''}
        ${!live ? '<p class="notice warning"><strong>This event was cancelled.</strong></p>' : ''}
        <dl class="card facts"><div><dt>When</dt><dd>${esc(fmt.full(e.start))} – ${esc(fmt.time(e.end))}</dd></div>
          ${e.location ? `<div><dt>Where</dt><dd>${esc(e.location)}</dd></div>` : ''}<div><dt>Organizer</dt><dd>${esc(e.organizer)}</dd></div></dl>
        ${newcomerHTML(e.newcomer)}
        ${e.details ? `<p>${esc(e.details)}</p>` : ''}
        <div id="my-rating"></div>
        ${live && !over ? `<div class="stack">
          <button class="btn ${going ? 'secondary' : 'primary'}" data-action="rsvp" data-id="${e.id}" aria-pressed="${going}">${going ? '✓ Going' : 'RSVP'}</button>
          <a class="btn secondary" href="#/pass/${e.id}">Show my check-in pass</a>
          <button class="btn secondary" data-action="ics" data-id="${e.id}">Add to calendar</button></div>` : ''}
        ${live && over ? `<a class="btn secondary" href="#/pass/${e.id}">Show my check-in pass</a>` : ''}
        ${runsEvent(e) ? `<div class="stack"><div class="section-header">Officer tools</div>
          <div id="event-stats" class="stack"><div class="spinner" style="margin:12px auto"></div></div>
          <a class="btn primary" href="#/checkin/${e.id}">Run check-in</a>
          <div class="row">${live ? `<button class="btn secondary" data-action="edit-event" data-id="${e.id}">Edit event</button>` : ''}
            <button class="btn secondary" data-action="add-task" data-club="${e.hosts.find(isOfficer)}" data-event="${e.id}">${over ? 'Add follow-up' : 'Add a to-do'}</button></div>
          <p class="footnote">Reminders: ${e.reminders?.length ? esc(REMINDERS.filter(([m]) => e.reminders.includes(m)).map(([, l]) => l).join(', ')) + ' before' : 'none'}. A rating request goes to everyone who checked in, 15 minutes after it ends.</p>
          ${live && !over ? `<button class="btn danger" data-action="cancel-event" data-id="${e.id}">Cancel event</button>` : ''}</div>` : ''}
      </div>`;
  }
  after.event = async (id) => {
    const e = event(id); if (!e) return;
    if (e.end < new Date() && e.status !== 'cancelled') {
      const [att, mine] = await Promise.all([
        run(() => q(sb.from('attendance').select('id').eq('event_id', id).eq('user_id', S.user.id).is('removed_at', null))),
        run(() => rpc('my_feedback', { p_event: id })),
      ]);
      const box = $('#my-rating');
      if (box && att?.length && Date.now() - e.end < 7 * 864e5) box.innerHTML = `<div class="card stack rate-card" data-stars="${mine?.stars || 0}"><strong>${mine ? 'Your rating' : 'How was it?'}</strong>
        ${stars(id, mine?.stars || 0, 'big')}
        <label class="field"><span>What should they keep? <span class="muted" style="font-weight:400">(optional)</span></span><textarea class="input short" id="fb-keep" maxlength="500">${esc(mine?.keep || '')}</textarea></label>
        <label class="field"><span>What should change? <span class="muted" style="font-weight:400">(optional)</span></span><textarea class="input short" id="fb-change" maxlength="500">${esc(mine?.change || '')}</textarea></label>
        <button class="btn secondary" data-action="feedback" data-event="${id}">Send feedback</button>
        <p class="footnote">Officers never see who wrote what. Averages and comments only show once 3 people have responded.</p></div>`;
    }
    if (!runsEvent(e)) return;
    const s = await run(() => rpc('event_stats', { p_event: id }));
    const box = $('#event-stats'); if (!s || !box) return;
    box.innerHTML = `<div class="stats">${stat(s.rsvps, 'RSVPs')}${stat(s.checked_in, 'Checked in')}${stat(pct(s.showed, s.rsvps), 'RSVPs who came', `${s.showed} of ${s.rsvps}`)}
      ${stat(s.rating_avg != null ? '★ ' + s.rating_avg : '–', 'Rating', s.rating_avg != null ? plural(s.ratings, 'rating') : `${s.ratings}/3 needed`)}</div>
      ${s.rating_dist ? `<div class="card dist">${s.rating_dist.slice().reverse().map((n, i) => `<div class="row"><span class="footnote" style="width:28px">${5 - i}★</span><div class="bar spacer"><span style="width:${pct(n, s.ratings)}"></span></div><span class="footnote" style="width:24px;text-align:right">${n}</span></div>`).join('')}</div>` : ''}
      <p class="footnote">${plural(s.first_timers, 'first-timer')} · ${plural(s.guests, 'guest')} · ${plural(Math.max(0, s.checked_in - s.showed - s.guests), 'walk-in')} who didn’t RSVP</p>
      ${s.keep?.length || s.change?.length ? `<div class="card stack">${s.keep?.length ? `<div><div class="section-header">Keep</div><ul class="fb">${s.keep.map((t) => `<li>${esc(t)}</li>`).join('')}</ul></div>` : ''}
        ${s.change?.length ? `<div><div class="section-header">Change</div><ul class="fb">${s.change.map((t) => `<li>${esc(t)}</li>`).join('')}</ul></div>` : ''}</div>`
        : s.ratings && s.ratings < 3 ? '<p class="footnote">Written feedback shows once 3 people respond.</p>' : ''}
      ${s.rsvp_list.length ? `<details class="card"><summary><strong>RSVP list</strong> <span class="footnote">· ${s.rsvp_list.length}</span></summary>${s.rsvp_list.map((r) =>
        `<div class="list-row"><span class="spacer">${esc(r.name)}</span>${r.checked_in ? '<span class="badge success">Came</span>' : '<span class="footnote">Not checked in</span>'}</div>`).join('')}</details>` : ''}`;
  };

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
      const t = $('#pass-timer'); if (t) t.textContent = `Refreshes in ${left}s`;
      if (left <= 2) { pass = null; issue(); }
    }, 1000);
    issue();
    cleanup.push(() => { alive = false; clearInterval(tick); });
  };

  // ───────────── Officer check-in ─────────────
  const ci = { mode: 'scan', records: [] };
  function checkinView(id) {
    const e = event(id);
    if (!e || !runsEvent(e)) return `${back(`#/event/${id}`, 'Event')}</div><div class="empty"><h2>Officers only</h2><p>Only this club’s officers can run check-in.</p></div>`;
    const seg = (v, l) => `<button data-action="ci-mode" data-v="${v}" aria-pressed="${ci.mode === v}">${l}</button>`;
    return `${back(`#/event/${id}`, 'Event')}<button class="link-btn" data-action="csv" data-id="${id}">Export CSV</button></div>
      <h1 style="font-size:28px;font-weight:800;margin:8px 0 4px">Check-in</h1><p class="muted" style="font-size:15px;margin-bottom:16px">${esc(e.title)}</p>
      <div class="stack-l"><div class="segmented" role="group" aria-label="Mode">${seg('scan', 'Scan')}${seg('lookup', 'Look up')}${seg('guest', 'Guest')}</div>
        <div id="ci-mode">${ciModeHTML()}</div>
        <p class="result" id="ci-result" aria-live="assertive"></p>
        <div class="card"><div class="section-header" id="ci-count">Checked in</div><div id="ci-list"><p class="footnote" style="padding-top:12px">Loading…</p></div></div>
        <p class="footnote">Corrections need a reason, and the original record is kept.</p></div>`;
  }
  function ciModeHTML() {
    if (ci.mode === 'scan') return `<div class="scanner"><video id="cam" playsinline muted></video><div class="frame"></div></div>
      <p class="footnote" id="cam-note" style="margin-top:8px">Point the camera at a member’s pass. Safari will ask for camera access.</p>`;
    if (ci.mode === 'lookup') return `<label class="search"><span class="sr">Search members</span><input class="input" id="lookup" type="search" placeholder="Search members and RSVPs" autocomplete="off"></label><div id="lookup-results" class="card" style="margin-top:12px;padding-top:4px;padding-bottom:4px"><p class="footnote" style="padding:12px 0">Type a name.</p></div>`;
    return `<form id="guest-form" class="row"><label class="spacer"><span class="sr">Guest’s name</span><input class="input" name="guest" placeholder="Guest’s name" autocomplete="off"></label><button class="btn primary small" style="min-height:48px">Check in</button></form>`;
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
    return `${titleBar('My Clubs', '<a class="icon-btn" href="#/new-club" aria-label="Start a club">＋</a>')}
      <div class="stack-l">${lead.length + mem.length + pend.length ? group('Clubs you lead', lead) + group('Member', mem) + group('Waiting for approval', pend)
        + '<a class="btn secondary" href="#/new-club">Start a club</a>'
        : `<div class="empty"><h2>No clubs yet</h2><p style="margin-bottom:16px">Find a club in Discover and join, or start your own.</p><a class="btn primary" style="max-width:240px;margin:0 auto" href="#/new-club">Start a club</a></div>`}</div>`;
  }

  // ───────────── People ─────────────
  function peopleView() {
    if (!S.user.discoverable) return `${titleBar('People')}<div class="card stack"><strong>Meet people who like what you like</strong>
      <p class="muted" style="font-size:15px">Turn this on to see students who share your interests, and let them see you. Only the contact details you choose are shown.</p>
      <button class="btn primary" data-action="go-visible">Turn on</button></div>`;
    return `${titleBar('People')}<p class="muted" style="margin:-6px 0 16px;font-size:15px">Students who share ${S.user.interests?.length ? esc(S.user.interests.join(', ')) : 'your interests'}.</p>
      <div id="people" class="stack"><div class="spinner" style="margin:40px auto"></div></div>`;
  }
  after.people = async () => {
    if (!S.user.discoverable) return;
    const rows = await run(() => rpc('people_to_meet'));
    const box = $('#people'); if (!rows || !box) return;
    box.innerHTML = rows.map((p) => `<div class="card person-card"><div class="row" style="align-items:flex-start">${avatar(p.name, 52)}
        <div class="spacer"><div style="font-weight:700;font-size:17px">${esc(p.name)}${p.pronouns ? ` <span class="footnote">${esc(p.pronouns)}</span>` : ''}</div>
          <div class="footnote">${esc([p.major, p.class_year].filter(Boolean).join(' · '))}</div></div>
        <button class="icon-btn small-icon" data-action="report" data-type="profile" data-id="${p.user_id}" data-name="${esc(p.name)}" aria-label="Report ${esc(p.name)}">⚑</button></div>
      ${p.bio ? `<p style="margin-top:8px">${esc(p.bio)}</p>` : ''}
      ${p.help_with?.length ? `<p class="footnote" style="margin-top:6px">Can help with: ${esc(p.help_with.join(', '))}</p>` : ''}${p.looking_for?.length ? `<p class="footnote">Looking for: ${esc(p.looking_for.join(', '))}</p>` : ''}
      <div class="badges">${p.interests.map((i) => badge(i, p.shared.includes(i) ? 'accent' : '')).join('')}${p.common_clubs ? badge(`${plural(p.common_clubs, 'club')} in common`, 'success') : ''}</div>
      ${contactButtons(p) || '<p class="footnote" style="margin-top:8px">Hasn’t shared contact info yet. You might meet at a club event.</p>'}</div>`).join('')
      || `<div class="empty"><h2>No one yet</h2><p>As more students join with ${S.user.interests?.length ? 'your interests' : 'interests set'}, they’ll show up here.</p><button class="btn secondary" style="max-width:240px;margin:16px auto 0" data-action="edit-profile">Edit interests</button></div>`;
  };

  // ───────────── Inbox ─────────────
  const KIND = { reminder: 'Reminder', new_event: 'New event', cancelled: 'Cancelled', rating: 'Rate it', nudge: 'Check-in', invite: 'Officer invite',
    approved: 'Approved', team_complete: 'Officer team', announcement: 'Announcement', event_changed: 'Changed', poll: 'When works?', task: 'Task' };
  function inboxView() {
    const inv = myInvites();
    const items = S.notifs.filter((n) => !(n.kind === 'invite' && inv.some((i) => n.dedupe === 'inv:' + i.id)));
    const link = (n) => n.event_id && event(n.event_id) ? `#/event/${n.event_id}` : n.club_id && club(n.club_id) ? `#/club/${n.club_id}` : '';
    const item = (n) => {
      const href = link(n), done = !!n.acted_at;
      let actions = '';
      if (n.kind === 'rating' && n.event_id) actions = done ? '<p class="footnote">Thanks for rating.</p>' : stars(n.event_id, 0);
      if (n.kind === 'nudge') actions = done ? '<p class="footnote">Thanks for letting them know.</p>' : `<div class="stack" style="gap:8px">
        <button class="btn primary small" data-action="nudge-answer" data-id="${n.id}" data-v="stay">I’m still in</button>
        <button class="btn secondary small" data-action="nudge-answer" data-id="${n.id}" data-v="busy">Busy lately, but keep me in</button>
        <button class="btn secondary small" data-action="nudge-answer" data-id="${n.id}" data-v="leave">Leave the club</button></div>`;
      return `<div class="card note${n.read_at ? '' : ' unread'}"><div class="row"><span class="kicker spacer">${esc(KIND[n.kind] || 'Update')}</span><span class="footnote">${fmt.rel(new Date(n.created_at))}</span></div>
        ${href ? `<a href="${href}" class="note-title">${esc(n.title)}</a>` : `<div class="note-title">${esc(n.title)}</div>`}
        ${n.body ? `<p class="muted" style="font-size:15px">${esc(n.body)}</p>` : ''}${actions}</div>`;
    };
    return `${back('#/discover', 'Back')}</div><h1 class="large-title" style="margin-top:8px">Inbox</h1><div class="stack">
      ${inv.map((i) => `<div class="card stack invite-card"><span class="kicker">Officer invite</span><strong>${esc(club(i.club_id)?.name || 'A club')} wants you as ${esc(i.position)}</strong>
        <p class="muted" style="font-size:15px">If you accept, your name, position and school email show on the club page.</p>
        <div class="row"><a class="btn secondary small" href="#/club/${i.club_id}">View club</a><span class="spacer"></span>
        <button class="btn secondary small" data-action="invite-answer" data-id="${i.id}" data-v="0">Decline</button>
        <button class="btn primary small" data-action="invite-answer" data-id="${i.id}" data-v="1">Accept</button></div></div>`).join('')}
      ${items.map(item).join('') || (inv.length ? '' : '<div class="empty"><h2>All caught up</h2><p>Reminders, announcements and invites from your clubs show up here. Nothing else.</p></div>')}</div>`;
  }
  let inboxFresh = false;                       // reset on every navigation, so opening the inbox always fetches
  after.inbox = () => {
    if (!inboxFresh) {
      inboxFresh = true;
      run(loadInbox).then(() => { if (route().name === 'inbox') render(); });
      return;
    }
    const ids = S.notifs.filter((n) => !n.read_at).map((n) => n.id);
    if (!ids.length) return;
    // Mark as read on the server; keep the highlight until you leave the screen.
    run(() => rpc('mark_notifications_read', { p_ids: ids })).then(() => { const t = new Date().toISOString(); S.notifs.forEach((n) => { if (ids.includes(n.id)) n.read_at = t; }); });
  };

  // ───────────── Profile ─────────────
  function profileView() {
    const u = S.user, active = Object.values(S.memberships).filter((m) => m.status === 'active').length;
    const blocked = S.clubs.filter((c) => S.blocked.has(c.id));
    return `${titleBar('Profile')}<div class="stack-l">
      <div class="card stack"><div class="row" style="align-items:flex-start">${avatar(u.name, 64)}<div class="spacer">
        <h2 style="font-size:22px;font-weight:800">${esc(u.name)}${u.pronouns ? ` <span class="footnote" style="font-weight:400">${esc(u.pronouns)}</span>` : ''}</h2>
        <p class="muted" style="font-size:15px">${esc([u.major, u.class_year].filter(Boolean).join(' · ') || CFG.campus.name)}</p>
        <p class="footnote">${esc(u.email)}</p></div></div>
        ${u.bio ? `<p>${esc(u.bio)}</p>` : ''}
        ${u.interests?.length ? `<div class="badges">${u.interests.map((i) => badge(i, 'accent')).join('')}</div>` : ''}
        ${u.help_with?.length ? `<p class="footnote">Can help with: ${esc(u.help_with.join(', '))}</p>` : ''}${u.looking_for?.length ? `<p class="footnote">Looking for: ${esc(u.looking_for.join(', '))}</p>` : ''}
        ${contactButtons({ email: u.share_email ? u.email : '', phone: u.share_phone ? u.phone : '', linkedin: u.share_linkedin ? u.linkedin : '' })}
        <button class="btn secondary" data-action="edit-profile">Edit profile</button></div>
      <div class="stack"><div class="section-header">Involvement record</div><div class="card" id="involvement">
        <div class="list-row"><span class="spacer">Clubs</span><strong>${active}</strong></div>
        <div class="list-row"><span class="spacer">Events attended</span><strong id="inv-count">…</strong></div><div id="inv-list"></div></div>
        <p class="footnote">Your check-ins, kept so you can show what you’ve been part of.</p></div>
      <div class="stack"><div class="section-header">Privacy</div><div class="card toggles">
        ${toggle('discoverable', 'Show me in People', 'Students with the same interests can find you.', u.discoverable).replace('name="discoverable"', 'data-privacy="discoverable"')}
        ${toggle('leaderboard', 'Show me on club leaderboards', 'Members see who comes most. Officers always see attendance.', u.leaderboard).replace('name="leaderboard"', 'data-privacy="leaderboard"')}</div></div>
      ${blocked.length ? `<div class="stack"><div class="section-header">Blocked clubs</div><div class="card">${blocked.map((c) => `<div class="list-row"><span class="spacer">${esc(c.name)}</span><button class="link-btn" data-action="unblock" data-club="${c.id}">Unblock</button></div>`).join('')}</div></div>` : ''}
      <div class="stack"><div class="section-header">Help</div><div class="card">
        <div class="list-row"><span class="spacer muted" style="font-size:15px">On iPhone: Share → Add to Home Screen to use it like an app</span></div>
        <div class="list-row"><a href="prototype/">Original design prototype</a></div></div></div>
      <div class="card stack"><button class="btn secondary" data-action="signout">Sign out</button><button class="btn danger" data-action="delete-account">Delete account</button></div></div>`;
  }
  after.profile = async () => {
    const rows = await run(() => q(sb.from('attendance').select('*').eq('user_id', S.user.id).is('removed_at', null).order('recorded_at', { ascending: false })));
    if (!rows || !$('#inv-count')) return;
    $('#inv-count').textContent = rows.length;
    $('#inv-list').innerHTML = rows.map((r) => `<div class="list-row"><div><div style="font-weight:600;font-size:15px">${esc(event(r.event_id)?.title || 'Event')}</div><div class="footnote">${esc(fmt.day(new Date(r.recorded_at)))}</div></div></div>`).join('');
  };
  /** Save profile changes (merges into the current profile). */
  async function saveProfile(patch) {
    const u = { ...S.user, ...patch };
    await rpc('save_profile', { p_name: u.name, p_major: u.major, p_year: u.class_year, p_pronouns: u.pronouns, p_interests: u.interests,
      p_bio: u.bio, p_phone: u.phone, p_linkedin: u.linkedin, p_share_email: u.share_email, p_share_phone: u.share_phone,
      p_share_linkedin: u.share_linkedin, p_discoverable: u.discoverable, p_leaderboard: u.leaderboard });
    S.user = await loadProfile(S.user.id);
  }
  function editProfileSheet() {
    const u = S.user;
    const form = openSheet('Edit profile', `<div class="stack-l">
      <label class="field"><span>Name</span><input class="input" name="name" value="${esc(u.name)}" maxlength="80" required></label>
      <label class="field"><span>Pronouns</span><input class="input" name="pronouns" value="${esc(u.pronouns)}" maxlength="30"></label>
      <label class="field"><span>Major</span><input class="input" name="major" value="${esc(u.major)}" maxlength="80"></label>
      <label class="field"><span>Year</span><select class="input" name="class_year"><option value="">—</option>${YEARS.map((y) => `<option ${u.class_year === y ? 'selected' : ''}>${y}</option>`).join('')}</select></label>
      <div class="field"><span>Interests (up to 3)</span><div class="chip-wrap">${INTERESTS.map((i) => `<label class="chip-check"><input type="checkbox" name="interests" value="${esc(i)}" ${u.interests?.includes(i) ? 'checked' : ''}><span>${esc(i)}</span></label>`).join('')}</div></div>
      <label class="field"><span>A line about you</span><input class="input" name="bio" value="${esc(u.bio)}" maxlength="280"></label>
      <label class="field"><span>Phone</span><input class="input" name="phone" type="tel" value="${esc(u.phone)}" maxlength="30"></label>
      <label class="field"><span>LinkedIn</span><input class="input" name="linkedin" type="url" autocapitalize="off" value="${esc(u.linkedin)}" maxlength="200" placeholder="linkedin.com/in/your-name"></label>
      <div class="field"><span>I can help with <span class="muted" style="font-weight:400">(up to 6)</span></span><div class="chip-wrap">${HELP.map((i) => `<label class="chip-check"><input type="checkbox" name="help" value="${esc(i)}" ${u.help_with?.includes(i) ? 'checked' : ''}><span>${esc(i)}</span></label>`).join('')}</div></div>
      <div class="field"><span>I’m looking for <span class="muted" style="font-weight:400">(up to 4)</span></span><div class="chip-wrap">${LOOKING.map((i) => `<label class="chip-check"><input type="checkbox" name="looking" value="${esc(i)}" ${u.looking_for?.includes(i) ? 'checked' : ''}><span>${esc(i)}</span></label>`).join('')}</div></div>
      <div class="card toggles">${toggle('share_email', 'Show my school email', '', u.share_email)}${toggle('share_phone', 'Show my phone number', '', u.share_phone)}${toggle('share_linkedin', 'Show my LinkedIn', '', u.share_linkedin)}</div>
      <p class="footnote">Shown to students in People and, if you’re an officer, on your club’s page.</p></div>`,
    { action: 'Save', onSubmit: async (fd) => {
      const interests = fd.getAll('interests'), help = fd.getAll('help'), looking = fd.getAll('looking');
      if (interests.length > 3) { toast('Pick up to 3 interests.', true); return false; }
      if (help.length > 6 || looking.length > 4) { toast('Pick fewer options.', true); return false; }
      if (!(await run(() => rpc('save_profile_extras', { p_help_with: help, p_looking_for: looking }).then(() => true)))) return false;
      const ok = await run(() => saveProfile({ name: (fd.get('name') || '').trim(), pronouns: (fd.get('pronouns') || '').trim(), major: (fd.get('major') || '').trim(),
        class_year: fd.get('class_year') || '', interests, bio: (fd.get('bio') || '').trim(), phone: (fd.get('phone') || '').trim(),
        linkedin: (fd.get('linkedin') || '').trim(), share_email: fd.get('share_email') === 'on', share_phone: fd.get('share_phone') === 'on',
        share_linkedin: fd.get('share_linkedin') === 'on' }).then(() => true));
      if (ok) { await run(loadAll); toast('Profile saved'); render(); } return !!ok;
    } });
    form.addEventListener('change', (e) => {
      const cap = { interests: 3, help: 6, looking: 4 }[e.target.name];
      if (cap && form.querySelectorAll(`input[name=${e.target.name}]:checked`).length > cap) { e.target.checked = false; toast(`Up to ${cap}. Unpick one first.`, true); }
    });
  }

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
    setTimeout(() => form.querySelector('input:not([type=radio]):not([type=hidden]):not([type=checkbox]), textarea')?.focus(), 250);
    return form;
  }
  function closeSheet() { $('#sheet-root').innerHTML = ''; document.body.style.overflow = ''; }
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && $('#sheet-root').innerHTML) closeSheet(); });

  function confirmSheet(title, message, actionLabel, fn, tone = 'danger') {
    openSheet(title, `<div class="stack" style="padding:8px 0"><p>${esc(message)}</p>
      <button class="btn primary" type="submit" ${tone === 'danger' ? 'style="background:var(--danger)"' : ''}>${esc(actionLabel)}</button></div>`,
      { onSubmit: async () => (await run(fn)) !== undefined });
  }
  const radios = (name, options, selected) => `<div class="card" style="padding-top:0;padding-bottom:0">${options.map(([v, label, sub]) => `<label class="choice">
    <input type="radio" name="${name}" value="${esc(v)}" ${v === selected ? 'checked' : ''}><span><span style="font-weight:600">${esc(label)}</span>${sub ? `<br><span class="footnote">${esc(sub)}</span>` : ''}</span></label>`).join('')}</div>`;

  function joinSheet(c, involvement = 'attend') {
    openSheet(c.name, `<div class="stack-l"><div class="stack"><div class="section-header">How involved do you want to be?</div>${radios('involvement', INVOLVE, involvement)}</div>
      <div class="stack"><div class="section-header">Notifications</div>${radios('notify', NOTIFY, 'rsvp')}</div>
      <label class="choice card" style="border:0"><input type="checkbox" name="recognition"><span><span style="font-weight:600">Count me as a supporter when ${esc(c.name)} applies for official recognition</span>
        <br><span class="footnote">Officers may include your name and school email in that request. You can change this anytime.</span></span></label>
      <p class="footnote">The club’s officers will see your name, school email, and which events you check in to. You can change all of this later.</p></div>`,
    { action: c.requires_approval ? 'Request' : 'Join', onSubmit: async (fd) => {
      const inv = fd.get('involvement') || 'attend';
      const m = await run(() => rpc('join_club', { p_club: c.id, p_role: inv === 'organize' ? 'founding' : 'member', p_contact: 'events', p_notify: fd.get('notify'),
        p_involvement: inv, p_recognition_ok: fd.get('recognition') === 'on', p_request: uuid() }));
      if (!m) return false;
      S.memberships[c.id] = { ...m, user_id: S.user.id }; toast(m.status === 'pending' ? `Request sent to ${c.name}’s officers` : `You joined ${c.name}`); render(); return true;
    } });
  }
  const REASONS = [['impersonation', 'Pretending to be someone else'], ['duplicate', 'Duplicate'],
    ['unsafe', 'Inappropriate, unsafe or harassing'], ['wrong_status', 'Status claim looks wrong'], ['other', 'Something else']];
  function reportSheet(type, id, name) {
    openSheet('Report', `<div class="stack-l"><div class="stack"><div class="section-header">What’s wrong with ${esc(name)}?</div>${radios('reason', REASONS.map(([k, v]) => [k, v, '']), '')}</div>
      <label class="field"><span>Details (optional)</span><textarea class="input" name="detail" maxlength="1000" placeholder="Anything that helps a moderator"></textarea></label></div>`,
    { action: 'Send', onSubmit: async (fd) => {
      if (!fd.get('reason')) { toast('Pick a reason.', true); return false; }
      const ok = await run(() => rpc('report_content', { p_type: type, p_target: id, p_reason: fd.get('reason'), p_detail: fd.get('detail') || '' }).then(() => true));
      if (ok) toast('Report sent. A moderator will review it.'); return !!ok;
    } });
  }
  function clubMenu(c) {
    const officer = isOfficer(c.id);
    openSheet(c.name, `<div class="card stack">
      ${officer ? `<button type="button" class="btn secondary" data-action="edit-club" data-club="${c.id}">Edit club</button>
      <button type="button" class="btn secondary" data-action="officer-info" data-club="${c.id}">Edit my “contact me about”</button>
      <button type="button" class="btn secondary" data-action="step-down" data-club="${c.id}">Step down as officer</button>` : ''}
      <button type="button" class="btn secondary" data-action="share" data-club="${c.id}">Share club</button>
      <button type="button" class="btn secondary" data-action="report" data-type="club" data-id="${c.id}" data-name="${esc(c.name)}">Report club</button>
      ${officer ? '' : `<button type="button" class="btn danger" data-action="block" data-club="${c.id}">Block club</button>`}</div>`, { cancel: 'Close' });
  }
  function editClubSheet(c) {
    let blob = null;
    const form = openSheet('Edit club', `<div class="stack-l">
      <div class="row">${mono(c, 64).replace('class="', 'id="ec-logo" class="')}<label class="btn secondary small file-btn">Change logo<input type="file" accept="image/png,image/jpeg,image/webp,image/heic" class="sr" id="ec-file"></label></div>
      <label class="field"><span>Club name</span><input class="input" name="name" value="${esc(c.name)}" maxlength="80" required></label>
      <label class="field"><span>What’s the point?</span><input class="input" name="blurb" value="${esc(c.blurb)}" maxlength="160"></label>
      <label class="field"><span>Interest</span><select class="input" name="interest">${INTERESTS.concat(INTERESTS.includes(c.interest) ? [] : [c.interest]).map((i) => `<option ${c.interest === i ? 'selected' : ''}>${esc(i)}</option>`).join('')}</select></label>
      <label class="field"><span>About</span><textarea class="input" name="about" maxlength="2000">${esc(c.about)}</textarea></label>
      <div class="field"><span>Color (when there’s no logo)</span><div class="swatches">${ACCENTS.map(([h, n]) => `<label class="swatch" style="background:${h}"><input type="radio" class="sr" name="accent" value="${h}" ${c.accent_hex === h ? 'checked' : ''}><span class="sr">${n}</span></label>`).join('')}</div></div>
      <div class="card toggles">${toggle('approval', 'Officers approve new members', '', c.requires_approval)}</div></div>`,
    { action: 'Save', onSubmit: async (fd) => {
      const name = (fd.get('name') || '').trim();
      const ok = await run(async () => {
        await rpc('update_club', { p_club: c.id, p_name: name, p_interest: fd.get('interest'), p_blurb: (fd.get('blurb') || '').trim(), p_about: (fd.get('about') || '').trim(),
          p_monogram: monogramOf(name), p_accent: fd.get('accent') || c.accent_hex, p_requires_approval: fd.get('approval') === 'on' });
        if (blob) await uploadLogo(c.id, blob);
        return true;
      });
      if (ok) { await refresh(); toast('Club updated'); } return !!ok;
    } });
    form.querySelector('#ec-file').addEventListener('change', async (e) => {
      const f = e.target.files[0]; if (!f) return;
      blob = await run(() => squareImage(f)); if (!blob) return;
      $('#ec-logo').outerHTML = `<img id="ec-logo" class="logo" src="${URL.createObjectURL(blob)}" alt="New logo" width="64" height="64">`;
    });
  }
  function inviteSheet(c, position) {
    openSheet('Invite an officer', `<div class="stack-l">
      <label class="field"><span>Position</span><input class="input" name="position" value="${esc(position)}" maxlength="40" placeholder="e.g. Social media chair" ${position ? 'readonly' : ''}></label>
      <label class="field"><span>Their school email</span><input class="input" name="email" type="email" inputmode="email" autocapitalize="off" spellcheck="false" required></label>
      <p class="footnote">They’ll see the invite in their inbox the next time they open Vnua-connect (or when they first sign up with that email).</p></div>`,
    { action: 'Invite', onSubmit: async (fd) => {
      const email = (fd.get('email') || '').trim().toLowerCase(), pos = (fd.get('position') || '').trim();
      if (pos.length < 2) { toast('Name the position.', true); return false; }
      if (!campusAllows(email)) { toast(`Use their ${CFG.campus.name} email.`, true); return false; }
      const ok = await run(() => rpc('invite_officer', { p_club: c.id, p_email: email, p_position: pos }).then(() => true));
      if (ok) { await refresh(); toast(`Invite sent to ${email}`); } return !!ok;
    } });
  }
  function officerInfoSheet(c) {
    const me = c.officers.find((o) => o.user_id === S.user.id);
    openSheet('Contact me about', `<div class="stack-l"><label class="field"><span>What should students reach out to you about?</span>
      <input class="input" name="ask" value="${esc(me?.ask_about || '')}" maxlength="140" placeholder="e.g. joining, dues, the spring trip"></label>
      <p class="footnote">Shows under your name on the club page with the contact details you share in your profile.</p></div>`,
    { action: 'Save', onSubmit: async (fd) => {
      const ok = await run(() => rpc('update_officer_info', { p_club: c.id, p_ask_about: (fd.get('ask') || '').trim() }).then(() => true));
      if (ok) { await refresh(); toast('Saved'); } return !!ok;
    } });
  }
  function announceSheet(c) {
    openSheet('Announcement', `<div class="stack-l">
      <label class="field"><span>Title</span><input class="input" name="title" maxlength="100" placeholder="e.g. Room change this Thursday" required></label>
      <label class="field"><span>Message</span><textarea class="input" name="body" maxlength="500"></textarea></label>
      <p class="footnote">Goes to members’ inboxes, except anyone who turned this club’s notifications off. It’s one-way, not a group chat.</p></div>`,
    { action: 'Send', onSubmit: async (fd) => {
      const n = await run(() => rpc('send_announcement', { p_club: c.id, p_title: (fd.get('title') || '').trim(), p_body: (fd.get('body') || '').trim() }));
      if (n === undefined) return false;
      await run(loadInbox); toast(`Sent to ${plural(n, 'person', 'people')}`); return true;
    } });
  }
  function eventSheet(c, e = null) {
    const t = new Date(); t.setDate(t.getDate() + 7); t.setHours(18, 0, 0, 0);
    const local = (d) => new Date(d - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
    const others = e ? [] : S.clubs.filter((x) => x.id !== c.id && isOfficer(x.id));
    const rid = uuid(), v = e || { title: '', start: t, duration_minutes: 60, location: '', details: '', reminders: [1440, 120], newcomer: {} };
    const nc = v.newcomer || {};
    openSheet(e ? 'Edit event' : c.name, `<div class="stack-l">
      <label class="field"><span>Event title</span><input class="input" name="title" maxlength="140" value="${esc(v.title)}" required></label>
      <label class="field"><span>Starts</span><input class="input" name="start" type="datetime-local" value="${local(v.start)}" required></label>
      <label class="field"><span>Length</span><select class="input" name="duration">${[30, 45, 60, 90, 120, 180, 240].concat([30, 45, 60, 90, 120, 180, 240].includes(v.duration_minutes) ? [] : [v.duration_minutes]).map((m) => `<option value="${m}" ${m === v.duration_minutes ? 'selected' : ''}>${m < 60 ? m + ' min' : m % 60 ? `${Math.floor(m / 60)} hr ${m % 60} min` : m / 60 + ' hr'}</option>`).join('')}</select></label>
      <label class="field"><span>Where</span><input class="input" name="location" maxlength="140" value="${esc(v.location)}" placeholder="Building and room"></label>
      <label class="field"><span>Details</span><textarea class="input" name="details" maxlength="2000" placeholder="What it is, in a sentence or two">${esc(v.details)}</textarea></label>
      <details class="card newcomer-form" ${e && Object.keys(nc).length ? 'open' : ''}><summary><strong>“First time?” info</strong> <span class="footnote">· recommended</span></summary>
        <p class="footnote" style="margin:8px 0 4px">Shown on the event page and on shared links, so someone new knows what to expect without having to ask.</p>
        ${NEWCOMER.map(([k, l, ph]) => `<label class="field"><span>${esc(l)}</span><input class="input" name="nc_${k}" maxlength="300" value="${esc(nc[k] || '')}" placeholder="${esc(ph)}"></label>`).join('')}</details>
      <div class="field"><span>Remind people</span><div class="chip-wrap">${REMINDERS.map(([m, l]) => `<label class="chip-check"><input type="checkbox" name="rem" value="${m}" ${(v.reminders || []).includes(m) ? 'checked' : ''}><span>${l} before</span></label>`).join('')}</div>
        <span class="footnote">Goes to everyone who RSVPs, plus members who want everything. Afterwards, people who checked in get asked for a rating.</span></div>
      ${others.length ? `<div class="stack"><div class="section-header">Co-host with</div><div class="card" style="padding-top:0;padding-bottom:0">${others.map((o) => `<label class="choice"><input type="checkbox" name="cohost" value="${o.id}"><span>${esc(o.name)}</span></label>`).join('')}</div>
        <p class="footnote">Joint events show up for both clubs. Each person is counted once.</p></div>` : ''}
      ${e ? '<p class="footnote">If you change the time or place, everyone who RSVP’d is told.</p>' : ''}</div>`,
    { action: e ? 'Save' : 'Post', onSubmit: async (fd) => {
      const title = (fd.get('title') || '').trim(); if (title.length < 2) { toast('Give the event a title.', true); return false; }
      const start = new Date(fd.get('start')); if (isNaN(start)) { toast('Pick a start time.', true); return false; }
      const newcomer = Object.fromEntries(NEWCOMER.map(([k]) => [k, (fd.get('nc_' + k) || '').trim()]).filter(([, x]) => x));
      const common = { p_title: title, p_starts_at: start.toISOString(), p_duration: Number(fd.get('duration')), p_location: (fd.get('location') || '').trim(),
        p_details: (fd.get('details') || '').trim(), p_reminders: fd.getAll('rem').map(Number), p_newcomer: newcomer };
      const ok = await run(() => (e ? rpc('update_event', { p_event: e.id, ...common }) : rpc('create_event', { p_hosts: [c.id, ...fd.getAll('cohost')], p_request: rid, ...common })).then(() => true));
      if (!ok) return false;
      await refresh(); toast(e ? 'Event updated' : 'Event posted'); return true;
    } });
  }
  function taskSheet(clubId, t = null, eventId = null) {
    const c = club(clubId); if (!c) return;
    // Club events, from the app's list plus the dashboard's (which can include ones loaded since).
    const evs = [...S.events.filter((e) => e.hosts.includes(clubId)).map((e) => ({ id: e.id, title: e.title, start: e.start })),
      ...(dash.club === clubId && dash.data ? dash.data.events.map((e) => ({ id: e.id, title: e.title, start: new Date(e.starts_at) })) : [])]
      .filter((e, i, a) => a.findIndex((x) => x.id === e.id) === i).sort((a, b) => b.start - a.start).slice(0, 25);
    const ev = t?.event_id || eventId;
    openSheet(t ? 'Edit task' : eventId && event(eventId)?.end < new Date() ? 'Follow up' : 'New task', `<div class="stack-l">
      <label class="field"><span>${eventId && !t && event(eventId)?.end < new Date() ? 'What should happen next?' : 'Task'}</span><input class="input" name="title" maxlength="140" value="${esc(t?.title || '')}" placeholder="e.g. Email everyone the photos, book a bigger room" required></label>
      <label class="field"><span>Who owns it</span><select class="input" name="owner"><option value="">Unassigned</option>${c.officers.map((o) => `<option value="${o.user_id}" ${(t ? t.owner_id : S.user.id) === o.user_id ? 'selected' : ''}>${esc(o.name)} · ${esc(o.title)}</option>`).join('')}</select></label>
      <label class="field"><span>Due</span><input class="input" type="date" name="due" value="${esc(t?.due_on || '')}"></label>
      <label class="field"><span>Event</span><select class="input" name="event"><option value="">None</option>${evs.map((e) => `<option value="${e.id}" ${ev === e.id ? 'selected' : ''}>${esc(e.title)} · ${esc(fmt.short(e.start))}</option>`).join('')}</select></label>
      ${t ? `<button type="button" class="btn danger" data-action="delete-task" data-id="${t.id}">Delete task</button>` : ''}
      <p class="footnote">Only officers see tasks. The owner gets a note in their inbox.</p></div>`,
    { action: 'Save', onSubmit: async (fd) => {
      const title = (fd.get('title') || '').trim(); if (title.length < 2) { toast('Describe the task.', true); return false; }
      const ok = await run(() => rpc('save_task', { p_task: t?.id || null, p_club: clubId, p_title: title, p_owner: fd.get('owner') || null,
        p_due: fd.get('due') || null, p_event: fd.get('event') || null }).then(() => true));
      if (ok) { toast('Saved'); redrawDash(); } return !!ok;
    } });
  }
  function pollSheet(c) {
    const local = (d) => new Date(d - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
    const base = new Date(); base.setDate(base.getDate() + 5); base.setHours(18, 0, 0, 0);
    const slot = (i) => { const d = new Date(base); d.setDate(d.getDate() + i); return `<input class="input" type="datetime-local" name="slot" value="${local(d)}">`; };
    const dl = new Date(); dl.setDate(dl.getDate() + 3); dl.setHours(21, 0, 0, 0);
    const form = openSheet('Find a time', `<div class="stack-l">
      <label class="field"><span>What’s it for?</span><input class="input" name="title" maxlength="140" placeholder="e.g. First general meeting" required></label>
      <div class="field"><span>Times to offer (2–6)</span><div class="stack" id="slots" style="gap:8px">${slot(0)}${slot(1)}${slot(2)}</div>
        <button type="button" class="link-btn" id="add-slot" style="justify-self:start">＋ Add a time</button></div>
      <label class="field"><span>Length</span><select class="input" name="duration">${[[30, '30 min'], [60, '1 hr'], [90, '1 hr 30 min'], [120, '2 hr'], [180, '3 hr']].map(([m, l]) => `<option value="${m}" ${m === 60 ? 'selected' : ''}>${l}</option>`).join('')}</select></label>
      <label class="field"><span>Where (if you know)</span><input class="input" name="location" maxlength="140"></label>
      <label class="field"><span>Reply by</span><input class="input" type="datetime-local" name="deadline" value="${local(dl)}"></label>
      <p class="footnote">Members answer yes, maybe or no for each time. You only see the totals. Pick a time and it becomes an event.</p></div>`,
    { action: 'Send', onSubmit: async (fd) => {
      const slots = fd.getAll('slot').filter(Boolean).map((x) => new Date(x).toISOString());
      const title = (fd.get('title') || '').trim(); if (title.length < 2) { toast('Say what it’s for.', true); return false; }
      const id = await run(() => rpc('create_poll', { p_club: c.id, p_title: title, p_slots: slots, p_duration: Number(fd.get('duration')),
        p_location: (fd.get('location') || '').trim(), p_deadline: new Date(fd.get('deadline')).toISOString() }));
      if (!id) return false;
      toast('Poll sent to members'); dash.tab = 'polls'; redrawDash(); if (route().name === 'club') render(); return true;
    } });
    form.querySelector('#add-slot').addEventListener('click', () => {
      const box = form.querySelector('#slots'); if (box.children.length >= 6) return toast('Up to 6 times.', true);
      box.insertAdjacentHTML('beforeend', slot(box.children.length));
    });
  }
  function correctSheet(recordId, name, eventId) {
    openSheet('Correct attendance', `<div class="stack-l"><p>Remove <strong>${esc(name)}</strong> from attendance?</p>
      <label class="field"><span>Reason (required)</span><textarea class="input" name="reason" maxlength="300" placeholder="e.g. Scanned the wrong person" required></textarea></label>
      <p class="footnote">The original record is kept with your reason so the club’s history stays honest.</p></div>`,
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
  const fileSafe = (s) => String(s || 'export').slice(0, 30).replace(/[^\w]+/g, '-');
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
      case 'signin-reset': S.signin = blankSignin(); render(); break;
      case 'signin-resend': sendCode(); break;
      // onboarding
      case 'ob-next': obNext(); break;
      case 'ob-back': S.ob.step--; render(); break;
      case 'ob-year': S.ob.year = d.v; render(); break;
      case 'ob-interest': {
        const i = S.ob.interests.indexOf(d.v);
        if (i >= 0) S.ob.interests.splice(i, 1); else if (S.ob.interests.length < 3) S.ob.interests.push(d.v); else return toast('Up to 3. Unpick one first.', true);
        render(); break; }
      case 'ob-finish': {
        const interests = S.ob.interests; S.ob = null;
        await run(loadAll);
        if (d.v === 'intent' && applyIntent()) break;
        if (d.v === 'create') { newClub(); location.hash = '#/new-club'; }
        else { S.interest = null; location.hash = '#/discover'; if (d.v === 'join' && !S.clubs.some((x) => interests.includes(x.interest))) toast('No clubs match yet. Browse them all, or start one.'); }
        render(); break; }
      // start a club
      case 'nc-next': ncNext(); break;
      case 'nc-back': S.nc.step--; render(); break;
      case 'nc-accent': S.nc.accent = d.v; render(); break;
      case 'nc-clear-logo': URL.revokeObjectURL(S.nc.logoPreview); S.nc.logoBlob = null; S.nc.logoPreview = ''; render(); break;
      case 'nc-add-extra': S.nc.extra.push({ title: '', email: '' }); render(); break;
      case 'nc-del-extra': S.nc.extra.splice(Number(d.v), 1); render(); break;
      case 'interest': S.interest = d.v || null; render(); break;
      case 'ev-scope': S.evScope = d.v; render(); break;
      case 'join': joinSheet(c); break;
      case 'leave': confirmSheet(`Leave ${c.name}?`, 'You can join again later.', 'Leave club', async () => {
        await rpc('leave_club', { p_club: c.id }); delete S.memberships[c.id]; toast(`You left ${c.name}`); render(); return true; }); break;
      case 'review': {
        const ok = await run(() => rpc('review_join_request', { p_club: d.club, p_user: d.user, p_approve: d.approve === '1' }).then(() => true));
        if (ok) { toast(d.approve === '1' ? 'Approved' : 'Request declined'); after.club(d.club); } break; }
      case 'club-menu': clubMenu(c); break;
      case 'edit-club': closeSheet(); editClubSheet(c); break;
      case 'officer-info': closeSheet(); officerInfoSheet(c); break;
      case 'step-down': closeSheet(); confirmSheet(`Step down from ${c.name}?`, 'You’ll stay a member. Your position opens up for someone else.', 'Step down', async () => {
        await rpc('remove_officer', { p_club: c.id, p_user: S.user.id }); await refresh(); toast('You stepped down'); return true; }); break;
      case 'invite': inviteSheet(c, d.v); break;
      case 'delete-task': closeSheet(); if (await run(() => rpc('delete_task', { p_task: d.id }).then(() => true))) { toast('Deleted'); redrawDash(); } break;
      case 'revoke-invite': if (await run(() => rpc('revoke_invite', { p_invite: d.id }).then(() => true))) { await refresh(); toast('Invite cancelled'); } break;
      case 'invite-answer': {
        const inv = S.invites.find((i) => i.id === d.id), yes = d.v === '1';
        const ok = await run(() => rpc('respond_invite', { p_invite: d.id, p_accept: yes }).then(() => true));
        if (ok) { await refresh(); toast(yes ? `You’re now ${inv?.position || 'an officer'}` : 'Invite declined'); if (yes && inv) location.hash = `#/club/${inv.club_id}`; }
        break; }
      case 'announce': announceSheet(c); break;
      case 'share': {
        const url = `${HERE}#/club/${c.id}`;
        if (navigator.share) navigator.share({ title: c.name, text: `Check out ${c.name} on Vnua-connect`, url }).catch(() => {});
        else copy(url, 'Link');
        break; }
      case 'report': closeSheet(); reportSheet(d.type, d.id, d.name); break;
      case 'block': confirmSheet(`Block ${c.name}?`, 'You won’t see this club or its events. You can undo this in Profile.', 'Block', async () => {
        await rpc('block_club', { p_club: c.id, p_blocked: true }); S.blocked.add(c.id); toast(`You won’t see ${c.name} anymore`); location.hash = '#/discover'; return true; }); break;
      case 'unblock': if (await run(() => rpc('block_club', { p_club: d.club, p_blocked: false }).then(() => true))) { S.blocked.delete(d.club); render(); } break;
      case 'rsvp': {
        const going = !S.rsvps.has(d.id);
        going ? S.rsvps.add(d.id) : S.rsvps.delete(d.id); render();           // optimistic
        const ok = await run(() => rpc('set_rsvp', { p_event: d.id, p_going: going, p_request: uuid() }).then(() => true));
        if (!ok) { going ? S.rsvps.delete(d.id) : S.rsvps.add(d.id); render(); }
        break; }
      case 'rate': {
        const v = Number(d.v);
        el.parentElement.querySelectorAll('.star').forEach((s, i) => s.classList.toggle('on', i < v));
        const rc = el.closest('.rate-card'); if (rc) rc.dataset.stars = v;
        const ok = await run(() => rpc('rate_event', { p_event: d.event, p_stars: v }).then(() => true));
        if (ok) { toast('Thanks. Your rating is anonymous.'); await run(loadInbox); if (route().name === 'inbox') render(); }
        break; }
      case 'nudge': {
        const users = d.users.split(',');
        const n = await run(() => rpc('nudge_members', { p_club: d.club, p_users: users }));
        if (n !== undefined) { toast(n ? `Sent to ${plural(n, 'member')}` : 'They were already checked in with this month'); after.dash(d.club); }
        break; }
      case 'nudge-answer': {
        const n = S.notifs.find((x) => x.id === d.id), name = club(n?.club_id)?.name || 'the club';
        const go = async () => {
          await rpc('respond_nudge', { p_notification: d.id, p_choice: d.v });
          await refresh(); toast(d.v === 'leave' ? `You left ${name}` : d.v === 'busy' ? 'Got it. You’re still in, no pressure.' : 'Great, see you soon'); return true;
        };
        if (d.v === 'leave') confirmSheet(`Leave ${name}?`, 'You can always join again later.', 'Leave club', go); else run(go);
        break; }
      case 'dash-tab': dash.tab = d.v; if (dash.data) $('#dash-body').innerHTML = dashBody(dash.club); break;
      case 'dash-filter': dash.filter = d.v; if (dash.data) $('#dash-body').innerHTML = dashBody(dash.club); break;
      case 'add-task': taskSheet(d.club, null, d.event); break;
      case 'edit-task': { const t = dash.tasks.find((x) => x.id === d.id); if (t) taskSheet(t.club_id, t); break; }
      case 'task-done': if (await run(() => rpc('set_task_done', { p_task: d.id, p_done: d.v === '1' }).then(() => true))) { toast(d.v === '1' ? 'Done' : 'Reopened'); redrawDash(); } break;
      case 'new-poll': pollSheet(c); break;
      case 'close-poll': if (await run(() => rpc('close_poll', { p_poll: d.id }).then(() => true))) { toast('Poll closed'); redrawDash(); } break;
      case 'schedule-poll': {
        const p = dash.polls.find((x) => x.id === d.poll), slot = dash.results[d.poll]?.slots.find((x) => x.id === d.slot);
        confirmSheet(`Schedule ${p.title}?`, `${fmt.full(new Date(slot.starts_at))}. This posts the event and tells everyone who said yes or maybe.`, 'Post event', async () => {
          const evId = await rpc('schedule_poll', { p_poll: d.poll, p_slot: d.slot, p_request: uuid() });
          await refresh(); location.hash = `#/event/${evId}`; toast('Event posted'); return true; }, 'primary');
        break; }
      case 'vote': {
        const box = el.closest('.vote'); box.querySelectorAll('button').forEach((b) => b.setAttribute('aria-pressed', b === el));
        if (await run(() => rpc('vote_poll', { p_slot: d.slot, p_answer: d.v }).then(() => true))) toast('Saved');
        break; }
      case 'dash-csv': if (dash.data) download(`members-${fileSafe(club(d.club)?.name)}.csv`, 'text/csv', membersCsv(dash.data)); break;
      case 'copy-emails': {
        if (!dash.data) break;
        const list = d.v === 'supporters' ? supportersOf(dash.data.members) : dash.data.members;
        if (!list.length) { toast('No one to copy yet.', true); break; }
        copy(list.map((m) => m.email).join(', '), d.v === 'supporters' ? 'Top supporters’ emails' : 'All emails'); break; }
      case 'recog-mail': {
        if (!dash.data) break;
        const cl = club(d.club), sup = supportersOf(dash.data.members), members = dash.data.members.filter((m) => !m.is_officer);
        const eboard = dash.data.members.filter((m) => m.is_officer).map((m) => `${m.name} (${m.title || 'Officer'})`).join(', ');
        const body = `Hello,\n\nWe'd like to request official recognition for ${cl.name}.\n\n${cl.blurb}\n\nWe have ${members.length} members plus our e-board: ${eboard}. `
          + `Our most active members are CC'd on this email. A full member list is attached.\n\nThank you,\n${S.user.name}\n${membership(d.club)?.officer_title || 'Officer'}, ${cl.name}`;
        location.href = `mailto:?cc=${encodeURIComponent(sup.map((m) => m.email).join(','))}&subject=${encodeURIComponent(`Recognition request: ${cl.name}`)}&body=${encodeURIComponent(body)}`;
        toast('Add the student activities office in To, and attach the CSV.');
        break; }
      case 'ics': { const e = event(d.id); download(`${fileSafe(e.title)}.ics`, 'text/calendar', icsFor(e)); break; }
      case 'cancel-event': confirmSheet('Cancel this event?', 'Everyone who RSVP’d gets told. RSVPs and check-ins are kept.', 'Cancel event', async () => {
        await rpc('cancel_event', { p_event: d.id }); await refresh(); toast('Event cancelled'); return true; }); break;
      case 'new-event': eventSheet(c); break;
      case 'edit-event': { const e = event(d.id); eventSheet(club(e.hosts.find(isOfficer)), e); break; }
      case 'share-event': {
        const e = event(d.id), url = `${HERE}#/event/${e.id}`;
        if (navigator.share) navigator.share({ title: e.title, text: `${e.title} · ${fmt.full(e.start)}`, url }).catch(() => {}); else copy(url, 'Link');
        break; }
      case 'feedback': {
        const card = el.closest('.rate-card'), st = Number(card?.dataset.stars || 0);
        if (!st) { toast('Pick a star rating first.', true); break; }
        const ok = await run(() => rpc('rate_event', { p_event: d.event, p_stars: st, p_keep: $('#fb-keep').value, p_change: $('#fb-change').value }).then(() => true));
        if (ok) toast('Thanks. Officers never see who wrote it.');
        break; }
      case 'preview-go': {
        if (d.v !== 'signin') saveIntent({ type: d.v, id: d.id, name: d.name });
        S.signin.show = true; render(); break; }
      case 'preview-back': takeIntent(); S.signin.show = false; render(); break;
      case 'ci-mode': ci.mode = d.v; render(); break;
      case 'ci-member': await ciCheckIn(d.event, { p_member: d.user }); $('#lookup')?.dispatchEvent(new Event('input')); break;
      case 'correct': correctSheet(d.id, d.name, d.event); break;
      case 'csv': { const e = event(d.id); download(`attendance-${fileSafe(e?.title)}.csv`, 'text/csv', csvFor(ci.records)); break; }
      case 'edit-profile': editProfileSheet(); break;
      case 'go-visible': if (await run(() => saveProfile({ discoverable: true }).then(() => true))) render(); break;
      case 'signout': await sb.auth.signOut(); break;
      case 'delete-account': confirmSheet('Delete your account?', 'This removes your profile, memberships and RSVPs. It can’t be undone.', 'Delete account', async () => {
        await rpc('delete_account'); await sb.auth.signOut({ scope: 'local' }); return true; }); break;
    }
  });
  document.addEventListener('input', (ev) => {
    const el = ev.target, d = el.dataset;
    if (d.ob && S.ob) S.ob[d.ob] = el.type === 'checkbox' ? el.checked : el.value;
    if (d.nc && S.nc) {
      S.nc[d.nc] = el.type === 'checkbox' ? el.checked : el.value;
      if (d.nc === 'position') render();
    }
    if (d.ncEmail && S.nc) S.nc.emails[d.ncEmail] = el.value;
    if (d.ncExtra !== undefined && S.nc) S.nc.extra[Number(d.ncExtra)][d.k] = el.value;
  });
  document.addEventListener('change', async (ev) => {
    const el = ev.target;
    if (el.dataset.ob && el.type === 'checkbox' && S.ob) S.ob[el.dataset.ob] = el.checked;
    if (el.dataset.nc && S.nc && (el.type === 'checkbox' || el.tagName === 'SELECT')) { S.nc[el.dataset.nc] = el.type === 'checkbox' ? el.checked : el.value; if (el.dataset.nc === 'position') render(); }
    if (el.dataset.file === 'nc-logo' && el.files[0]) {
      const blob = await run(() => squareImage(el.files[0]));
      if (blob && S.nc) { if (S.nc.logoPreview) URL.revokeObjectURL(S.nc.logoPreview); S.nc.logoBlob = blob; S.nc.logoPreview = URL.createObjectURL(blob); render(); }
    }
    if (el.dataset.mem) {
      const card = el.closest('[data-mem-card]'), clubId = card.dataset.memCard, m = S.memberships[clubId];
      const next = { notify: card.querySelector('[data-mem=notify]').value, involvement: card.querySelector('[data-mem=involvement]').value,
        recognition_ok: card.querySelector('[data-mem=recognition]')?.checked ?? m.recognition_ok };
      const ok = await run(() => rpc('update_membership', { p_club: clubId, p_notify: next.notify, p_involvement: next.involvement, p_recognition_ok: next.recognition_ok }).then(() => true));
      if (ok) { Object.assign(m, next); if (next.involvement === 'organize' && m.role === 'member') m.role = 'founding'; toast('Saved'); }
    }
    if (el.dataset.privacy) {
      const key = el.dataset.privacy, val = el.checked;
      const ok = await run(() => saveProfile({ [key]: val }).then(() => true));
      if (ok) toast('Saved'); else el.checked = !val;
    }
  });

  // ───────────── Boot ─────────────
  async function signedIn(session) {
    const profile = await run(() => loadProfile(session.user.id));
    if (!profile) { S.booting = false; render(); return; }
    S.user = profile;
    await run(loadAll); lastLoad = Date.now();
    if (!profile.onboarded_at) startOnboarding();
    S.booting = false; S.signin.show = false;
    if (S.ob || !applyIntent()) render();
  }
  async function boot() {
    const params = new URLSearchParams(location.search);
    const err = params.get('error_description') || new URLSearchParams(location.hash.slice(1)).get('error_description');
    const { data: { session } } = await sb.auth.getSession();       // also finishes a sign-in link (?code=…)
    if (params.has('code') || params.has('error') || location.hash.includes('error=')) history.replaceState(null, '', HERE + (location.hash.startsWith('#/') ? location.hash : ''));
    if (err) toast(/code verifier|both auth code/i.test(err) ? 'Open the sign-in link in the same browser you requested it from, or use the code.' : err.replace(/\+/g, ' '), true);
    if (!session && params.has('code') && !err) toast('That link was opened in a different browser. Enter the code from the email instead.', true);
    if (session) await signedIn(session); else { S.booting = false; render(); }
    sb.auth.onAuthStateChange((evt, s) => {
      if (evt === 'SIGNED_IN' && s && !S.user) { S.booting = true; render(); signedIn(s); }
      if (evt === 'SIGNED_OUT') { Object.assign(S, { user: null, clubs: [], events: [], memberships: {}, rsvps: new Set(), blocked: new Set(), notifs: [], invites: [], ob: null, nc: null });
        S.signin = blankSignin(); location.hash = ''; render(); }
    });
  }
  window.addEventListener('pageshow', (e) => { if (e.persisted && S.user) refresh(); });
  boot().catch((e) => { console.error(e); S.booting = false; render(); toast(errMsg(e), true); });
})();
