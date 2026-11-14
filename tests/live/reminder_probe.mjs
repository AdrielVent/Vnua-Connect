// Proves pg_cron delivers reminders on the live project: event starts in ~2h, 2-hour reminder due now; wait for the scheduler.
const URL_ = process.env.SB_URL, S = process.env.SB_SERVICE;
const api = async (path, { method = 'GET', body, headers = {} } = {}) => {
  const r = await fetch(URL_ + path, { method, headers: { apikey: S, Authorization: `Bearer ${S}`, 'Content-Type': 'application/json', ...headers }, body: body && JSON.stringify(body) });
  const t = await r.text(); if (!r.ok) throw new Error(`${method} ${path} ${r.status} ${t}`); return t ? JSON.parse(t) : null;
};
const email = `vnua-cron-${Date.now().toString(36)}@pride.hofstra.edu`;
const user = await api('/auth/v1/admin/users', { method: 'POST', body: { email, email_confirm: true } });
let club, ev;
try {
  club = (await api('/rest/v1/clubs', { method: 'POST', headers: { Prefer: 'return=representation' }, body: { campus_id: 'hofstra', monogram: 'CP', name: `Cron probe ${Date.now()}`, interest: 'Tech' } }))[0];
  ev = (await api('/rest/v1/events', { method: 'POST', headers: { Prefer: 'return=representation' }, body: { campus_id: 'hofstra', title: 'Cron probe', starts_at: new Date(Date.now() + 118 * 60e3).toISOString(), reminders: [120], created_at: new Date(Date.now() - 864e5).toISOString() } }))[0];
  await api('/rest/v1/event_hosts', { method: 'POST', body: { event_id: ev.id, club_id: club.id } });
  await api('/rest/v1/rsvps', { method: 'POST', body: { event_id: ev.id, user_id: user.id } });
  const t0 = Date.now(); let got = null;
  while (Date.now() - t0 < 7 * 60e3 && !got) {
    await new Promise((r) => setTimeout(r, 20000));
    got = (await api(`/rest/v1/notifications?user_id=eq.${user.id}&kind=eq.reminder&select=title,created_at`))[0];
  }
  console.log(got ? `CRON OK after ${Math.round((Date.now() - t0) / 1000)}s: "${got.title}"` : 'CRON DID NOT FIRE within 7 minutes');
} finally {
  if (ev) await api(`/rest/v1/events?id=eq.${ev.id}`, { method: 'DELETE' });
  if (club) await api(`/rest/v1/clubs?id=eq.${club.id}`, { method: 'DELETE' });
  await api(`/auth/v1/admin/users/${user.id}`, { method: 'DELETE' });
  console.log('probe cleaned up');
}
