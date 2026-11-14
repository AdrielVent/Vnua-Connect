# Lion's Den demo — Fri Nov 20, iPhone 17, Safari + Home Screen app

Live path (do not add steps):
**shared club link (no account) → sign in → onboarding → Discover "Picked for you" → join the demo club → officer dashboard shows the new member.**

## Two iPhone facts that shape the demo
1. **Links always open in Safari, not in the Home Screen app.** Tapping a shared link from Messages/Mail opens Safari.
   So the "cold shared link" part is shown in **Safari** (that's what a real student sees from a group chat).
2. **The Home Screen app has its own storage, separate from Safari.** An email *sign-in link* signs you in to Safari, never to
   the installed app. Inside the installed app, sign in with a **password** (or a code, once SMTP is working).

## Sign-in: which branch are we on?
`web/config.js` → `signInEmail`.
- `'link'` (today): emails contain a link. The app says "Email me a sign-in link". **Branch 1B.**
- `'code'`: only switch after custom SMTP + the code template are set up **and** a real code has arrived and worked twice
  from a cold browser on the iPhone. Then bump `?v=` in `index.html` and push. **Branch 1A.**

## One-time setup (before Nov 18)
1. **Demo club (decision: path a, with b as backup).**
   - (a) **SHPE, for real:** Adriel is SHPE's President. Invite the real VP, Treasurer and Secretary from the SHPE club page
     (Officer team → Invite). Each accepts in their own app (Inbox → Accept). Then publish (SQL editor):
     `update clubs set is_published = true where name = 'SHPE';` — this only works once all four have accepted.
   - (b) **Backup, if the e-board can't accept in time:** a separate club named so it can't be mistaken for an official one,
     e.g. "Demo club (Lion's Den walkthrough)", with 3 more Hofstra accounts **you control or friends who agreed**. Same steps.
2. **Two accounts in the Home Screen app** (this is the fallback for a failed sign-in):
   - In **Safari**: sign in as yourself (email link) → Profile → **Set a password**.
   - Do the same for a second Hofstra account you control (the "new student" account).
   - Add to Home Screen (Share → Add to Home Screen) → open it → **Sign in with a password** as yourself →
     Profile → **Add another account** → password → the second account.
   - Profile → *Accounts on this device* now lists both. One tap switches.

## On-device test — run twice before Nov 19, screen-record both (Control Center → Screen Recording)
Use the iPhone 17 you'll present with. Ideally on Hofstra Wi-Fi.
| # | Do | Expect |
|---|---|---|
| 1 | Settings → Safari → Clear History and Website Data. Then text yourself the club link (Club → ⋯ → Share). Tap it. | Safari opens a public page: club name, e-board first names, **Join** / **Help build this group**, "not affiliated" line. No emails. |
| 2 | Tap **Join**. | Sign-in screen with "Join ⟨club⟩ — sign in first". Button says **Email me a sign-in link**. |
| 3 | Enter the new-student email → send. Open Mail **on this iPhone**, tap the link. | Safari signs in, shows Welcome. (Time it: ____ s until the email arrives.) |
| 4 | Onboarding: name, major, year, 2–3 interests, Continue, Save. | "Continue to ⟨club⟩" → Join sheet opens. |
| 5 | Pick how involved, tick "Count me as a supporter…", **Join**. | "You're a member". |
| 6 | Back → Discover. | The note "Every club gets the same spot here…" is visible. |
| 7 | Open the **Home Screen app** → Profile → switch to **your officer account** → club → Officer dashboard → Members. | The new student is listed; recognition shows the supporter count. |
| 8 | Profile → About. | "not affiliated with or endorsed by Hofstra University". |
Write down anything that looks or behaves differently from this table.

## If something fails live
- Email slow/missing at step 3 → open the Home Screen app, already signed in to both accounts, and continue from step 4's result
  (the student account) — say "sign-in emails can take a minute; here's the same account already signed in".
- No Wi-Fi → nothing works offline; use the screen recording from the rehearsal.

## What was tested where (keep this honest in the pitch)
- iPhone 17 Pro **Simulator**, real iOS 26.5 Mobile Safari, driven by Apple's safaridriver (`scratchpad/e2e/sim_demo_path.mjs`):
  the whole path above, using password sign-in. Some taps/typing needed a scripted fallback (simulator automation limits).
- WebKit on a Mac (Playwright): 59 checks across every feature.
- **Not yet tested by Claude on a physical iPhone, a real inbox, or the Home Screen app.** That's the on-device test above.
