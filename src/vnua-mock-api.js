// Vnua-connect MOCK adapter (pass 4). In-memory only: no network, no security, no persistence.
// It stands in for a server so the UI can be built against one contract. Not authorization.
//
// Every call resolves to { ok: true, data } or { ok: false, error: { code, message, retryable } }.
// Error codes: network | validation | forbidden_role | last_admin | not_found
// Idempotency: calls carrying the same requestId return the first SUCCESSFUL result (failed calls are not cached).
// Uniqueness (separate from idempotency): one attendance record per (eventId, attendeeKey).
//
// Proposed production endpoints (server enforces auth + per-club / per-event roles):
//   PUT  /v1/events/:eventId/rsvp                {going}                       -> {eventId, going}
//   POST /v1/clubs/:clubId/memberships           {role:'member'|'founding', contact}   (never 'officer')
//   PATCH /v1/clubs/:clubId/memberships/me       {contact}
//   DELETE /v1/clubs/:clubId/memberships/me      -> last_admin if caller is the final administrator
//   POST /v1/events/:eventId/passes              -> {token, expiresAt}          (opaque, short-lived, event-bound)
//   POST /v1/events/:eventId/checkins            {token|memberId, requestId}    -> {status:'recorded'|'duplicate', recordId}
//   POST /v1/attendance/:recordId/corrections    {reason}                       (reason required; original kept)
(function () {
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const ok = (data) => ({ ok: true, data });
  const err = (code, message, retryable) => ({ ok: false, error: { code, message, retryable: !!retryable } });
  let st;
  const api = {
    kind: 'mock',
    failNext: false,
    reset(seed) {
      st = { rsvp: {}, members: {}, att: {}, req: {} };
      (seed || []).forEach(([e, k]) => { st.att[e + '|' + k] = 'rec_seed_' + k.replace(/\W/g, ''); });
      api.failNext = false;
    },
    async _run(requestId, fn) {
      await wait(150);
      if (api.failNext) { api.failNext = false; return err('network', 'No response from the server.', true); }
      if (requestId && st.req[requestId]) return st.req[requestId];
      const r = fn();
      if (requestId && r.ok) st.req[requestId] = r;
      return r;
    },
    setRsvp({ eventId, userId, going, requestId }) {
      return api._run(requestId, () => {
        if (typeof going !== 'boolean') return err('validation', 'RSVP must be yes or no.');
        st.rsvp[eventId + '|' + userId] = going; // never touches attendance
        return ok({ eventId, going });
      });
    },
    join({ clubId, userId, role, contact, requestId }) {
      return api._run(requestId, () => {
        if (!['member', 'founding'].includes(role)) return err('forbidden_role', 'You can’t give yourself that role.');
        if (!['none', 'events', 'organizing'].includes(contact)) return err('validation', 'Choose whether the club can email you.');
        st.members[clubId + '|' + userId] = { role, contact };
        return ok({ clubId, role, contact });
      });
    },
    updateContact({ clubId, userId, contact }) {
      return api._run(null, () => {
        if (!['none', 'events', 'organizing'].includes(contact)) return err('validation', 'Choose whether the club can email you.');
        return ok({ clubId, contact });
      });
    },
    leave({ clubId, userId, role }) {
      return api._run(null, () => {
        if (role === 'officer') return err('last_admin', 'You’re this club’s administrator. Transfer leadership before leaving.');
        delete st.members[clubId + '|' + userId];
        return ok({ clubId });
      });
    },
    async issuePass(eventId) {
      await wait(100);
      return ok({ token: 'VNUA-DEMO-' + Math.random().toString(36).slice(2, 10).toUpperCase(), expiresAt: Date.now() + 45000, eventId });
    },
    checkIn({ eventId, attendeeKey, requestId }) {
      return api._run(requestId, () => {
        if (!eventId || !attendeeKey) return err('validation', 'Missing event or attendee.');
        const k = eventId + '|' + attendeeKey;
        if (st.att[k]) return ok({ status: 'duplicate', recordId: st.att[k] });
        const id = 'rec_' + Math.random().toString(36).slice(2, 8);
        st.att[k] = id;
        return ok({ status: 'recorded', recordId: id });
      });
    },
    correct({ eventId, attendeeKey, reason, requestId }) {
      return api._run(requestId, () => {
        if (!reason || !reason.trim()) return err('validation', 'A reason is required.');
        delete st.att[eventId + '|' + attendeeKey]; // record marked removed; audit kept client-side in prototype
        return ok({ correctionId: 'cor_' + Math.random().toString(36).slice(2, 8) });
      });
    },
  };
  api.reset();
  window.VnuaMockApi = api;
})();
