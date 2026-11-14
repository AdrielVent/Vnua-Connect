// Renders the officer-team card at iPhone width with a very long invited email and checks nothing overflows.
import { webkit, devices } from 'playwright';
const b = await webkit.launch(); const p = await (await b.newContext(devices['iPhone 15 Pro'])).newPage();
await p.goto(process.env.SITE + '?layout-check');
await p.evaluate(() => {
  document.querySelector('#app').innerHTML = `<main class="screen no-tabs"><div class="card stack team"><div class="row"><div class="section-header spacer" style="margin:0">Officer team</div><span class="badge warning">1/4 core</span></div>
    <div><div class="slot pending"><span class="slot-t">Vice President</span><span class="spacer footnote">Invited vnua-e2e-vp-mwgkp84u-very-long@pride.hofstra.edu</span><button class="link-btn danger">Cancel</button></div></div></div></main>`;
});
const r = await p.evaluate(() => { const card = document.querySelector('.team').getBoundingClientRect(); const btn = document.querySelector('.slot .link-btn').getBoundingClientRect(); const badge = document.querySelector('.team .badge').getBoundingClientRect();
  return { cardRight: Math.round(card.right), btnRight: Math.round(btn.right), badgeRight: Math.round(badge.right), docOverflow: document.documentElement.scrollWidth > innerWidth }; });
console.log(JSON.stringify(r), r.btnRight <= r.cardRight && r.badgeRight <= r.cardRight && !r.docOverflow ? '✓ fits' : '✗ overflows');
await b.close();
