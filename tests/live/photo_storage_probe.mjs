const U = process.env.SB_URL, A = process.env.SB_ANON, S = process.env.SB_SERVICE;
const j = async (r) => { const t = await r.text(); try { return JSON.parse(t); } catch { return t; } };
const email = `vnua-photo-${Date.now().toString(36)}@pride.hofstra.edu`, pw = 'Probe-' + Date.now();
const user = await j(await fetch(`${U}/auth/v1/admin/users`, { method: 'POST', headers: { apikey: S, Authorization: `Bearer ${S}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: pw, email_confirm: true }) }));
try {
  const sess = await j(await fetch(`${U}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: A, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: pw }) }));
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
  const path = `${user.id}/probe.png`;
  const up = await fetch(`${U}/storage/v1/object/avatars/${path}`, { method: 'POST', headers: { apikey: A, Authorization: `Bearer ${sess.access_token}`, 'Content-Type': 'image/png' }, body: png });
  console.log('upload as the user:', up.status, JSON.stringify(await j(up)).slice(0, 120));
  const other = await fetch(`${U}/storage/v1/object/avatars/00000000-0000-0000-0000-000000000000/x.png`, { method: 'POST', headers: { apikey: A, Authorization: `Bearer ${sess.access_token}`, 'Content-Type': 'image/png' }, body: png });
  console.log('upload into someone else\'s folder:', other.status);
  const pub = await fetch(`${U}/storage/v1/object/public/avatars/${path}`);
  console.log('public URL:', pub.status, pub.headers.get('content-type'));
} finally {
  await fetch(`${U}/storage/v1/object/avatars`, { method: 'DELETE', headers: { apikey: S, Authorization: `Bearer ${S}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ prefixes: [`${user.id}/probe.png`] }) });
  await fetch(`${U}/auth/v1/admin/users/${user.id}`, { method: 'DELETE', headers: { apikey: S, Authorization: `Bearer ${S}` } });
  console.log('cleaned up');
}
