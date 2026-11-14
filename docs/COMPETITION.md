# Vnua-connect vs. the competition — Lion's Den, Fri Nov 20, 2026

Every claim below has a source or a test. "Verified" = a test I ran against the live app (see *Proof* at the end).
Where a source is old or second-hand, it says so.

## The event
- Shark Tank–style, **4-minute pitch** to "experienced entrepreneurs"; top 10 finalists; Fri **Nov 20, 2026**, 12–3pm,
  ideaHUb, Guthart Hall 103; prizes $350 / $250 / $150. **No judging rubric is published.**
  — [hofstra.edu/lionsden](https://www.hofstra.edu/lionsden)
- 2025's page names Barbara Roberts (Entrepreneur-in-Residence) and Natalia Sandor as past judges. The 2026 panel isn't listed.

## The problem (keep these three kinds of claim separate)
1. **Documented rule:** Hofstra's classification system says registered organizations "must maintain (at all times) an
   up-to-date membership roster of no less than 15 members on GetInvolvedHU", with case-by-case exceptions.
   — [Student Organization Classification System, Spring 2017 (PDF)](https://www.hofstra.edu/pdf/studentaffairs/studentactivities/stdact-student-organization-classification-system.pdf).
   *Caveat: dated 2017; confirm it's current with osle@hofstra.edu before quoting it as today's rule.*
   A Hofstra guide says new groups must attend a New Student Organization Information Session to get the GetInvolvedHU
   application, then present to a committee that approves or denies. — [Guide to Pride 2023–24](https://issuu.com/hofstra/docs/guide-to-pride-2324/s/37009159)
2. **Founder's experience:** Adriel's SHPE and AIAA applications were denied on Nov 4, 2026 (his email thread — his account, not a public record).
3. **Not yet proven:** demand beyond SHPE/AIAA. Don't claim it. Show what you can measure by Friday (see *How to win*).

## Why clubs matter (evidence, not hype)
- Ohio State's 2024 Student Life Survey: involvement had strong associations with sense of belonging, even controlling
  for demographic and academic factors. — [OSU report (PDF)](https://cssl.osu.edu/documents/sls24-belonging-and-involvement-report-regional-tagged.pdf)
- UTS (Sydney), 500+ club members surveyed: positive association between club membership and belonging.
  — [ActivateUTS report (PDF)](https://opus.lib.uts.edu.au/bitstream/10453/151238/2/ActivateUTS%20Report%202020.pdf)
- *Honest caveat for Q&A:* this research is correlational, it doesn't prove clubs cause retention.

## The competition
| | What it is | Who it serves | Where Vnua-connect is different |
|---|---|---|---|
| **GetInvolvedHU** (Anthology Engage) | Hofstra's official platform. Org registration/renewal, co-curricular records, room reservations, event check-in. — [Anthology Engage overview (PDF)](https://www.anthology.com/sites/default/files/2022-06/Engage-Overview.pdf) | **Recognized** organizations | A group can't use it until it's recognized (info session → committee → 15-member roster). Vnua-connect is for the stage *before* that. **Position it as an on-ramp to GIHU, not a replacement.** |
| Engage's ownership | Anthology went through Chapter 11; Engage was sold to Encoura LE (court approval announced Nov 24, 2025). — [Anthology press release](https://www.anthology.com/news/anthology-receives-approval-for-sale-transactions), [Davis Polk](https://www.davispolk.com/experience/anthology-chapter-11-restructuring) | — | Fact only. **Don't** use it to attack Hofstra's vendor in front of Hofstra judges. |
| **CampusGroups**, **Modern Campus Involve** (formerly Presence) | Institution-wide engagement suites; pricing is quote-based, no free plan listed. — [SaaSworthy](https://www.saasworthy.com/product/campusgroups/pricing), [Software Advice](https://www.softwareadvice.com/gamification/presence-profile/) | Universities buy them for recognized orgs | Same institutional model as GIHU. Vnua-connect is free for students and built for groups the institution hasn't recognized yet. |
| **GroupMe / Discord / Instagram** | Free chat | Any group | Students mute big GroupMe chats ([Duke Chronicle](https://www.dukechronicle.com/article/2022/09/092322-gao-groupme)); student orgs report unwanted members/messages ([Daily Northwestern](https://dailynorthwestern.com/2024/11/06/lateststories/groupme-chatbots-raise-frustrations-for-student-organizations)). Chat keeps no attendance, no roster, no consent record — nothing to show a recognition committee. |
| **SHPE NJIT app** | One chapter's app: events, QR check-in, points leaderboard. Developer reports 1,200+ members (self-reported). — [App listing mirror](https://chrome-stats.com/d/id6757627370), [developer page](https://sjossue.github.io/work/shpe-app) | One organization | Vnua-connect is multi-club and campus-gated, and turns participation into the evidence a new club needs. |

## Where Vnua-connect wins — each line is a verified feature
1. **From "we want to start something" to a recognition-ready roster.** Officer team of four required before a club goes
   live; members explicitly opt in to be counted for recognition; dashboard shows "X/15 supporters" and drafts the request
   email with top supporters CC'd. *(verified: e2e checks "recognition counts members who said yes", "a moderator cannot
   publish it before all four positions are filled")*
2. **Real attendance, not chat noise.** QR pass + officer check-in, RSVP→showed-up rate, corrections that keep the original.
   *(verified: "the VP checks the member in by pass", "officer sees RSVP → check-in rate")*
3. **Only the notifications members choose** (Everything / Just what I RSVP to / Nothing), reminders the officer picks.
   *(verified: "muted members get no reminders"; live scheduler delivered a reminder)*
4. **Fair discovery:** clubs listed A–Z, never by size, stated on screen. *(verified: "Discover says clubs are listed A–Z")*
5. **Privacy by design:** campus-only sign-up, ratings officers can't trace to a person, contact info only if shared,
   explicit consent for recognition contact, disclaimer of Hofstra non-affiliation inside the app. *(verified: ratings
   unreadable, non-Hofstra email refused, server-only helpers blocked)*
6. **Shared links that convert:** a club link opens a public page and turns into "Join" or "Help build this group".
   *(verified on iOS 26.5 Safari in the iPhone 17 Pro Simulator)*

## Business model (say it as a plan, not a fact)
- Free for students. The database already supports more campuses (`insert into campuses …`, one line).
- Path to money to *test*, not claim: campus licenses once clubs show traction, and partnerships with national
  professional societies (e.g. SHPE/AIAA chapters) that want new chapters to get recognized. Costs today: Supabase free
  tier + GitHub Pages = $0; Apple Developer $99/yr when the iPhone app ships.

## How to win Friday (what judges reward is traction you can prove)
1. **Before Friday, get real numbers into the founder dashboard:** SHPE's VP/Treasurer/Secretary accept → publish SHPE →
   share the link in SHPE/AIAA chats → aim for 15 real "count me" supporters. Then the pitch says
   "X students joined in Y days" and you can show it live. *This is the single biggest lever.*
2. **Frame:** "GIHU is where clubs live once they're recognized. Vnua-connect is how a new club gets there." (complementary)
3. **Demo only the one path** in docs/DEMO.md, with the pre-signed-in fallback ready.
4. **Say the honest limits out loud** — judges trust founders who know them (see below).

## Honest limits to own in Q&A
- Traction today: 1 real account, 2 unpublished clubs (as of Nov 14).
- Sign-in sends a link until Gmail SMTP is set up (`supabase/setup_gmail_smtp.sh`); codes are built and tested but not live.
- Not yet tested on a physical iPhone by anyone but you; the iPhone app is behind the web app.
- Not affiliated with or endorsed by Hofstra; publishing on Vnua-connect is not recognition.
- The 15-member rule source is from 2017 — confirm it's current.

## Proof (re-run Nov 14, 2026 6:58 AM EST, commit 0d6f30a, live site v15)
- Database: 9 test suites (security, v2–v9) passed on a fresh database with every migration; production is up to date with the repo.
- Website end-to-end against the **live** site (WebKit, iPhone emulation): **87/87** checks passed; all test data deleted.
- Demo path against the live site in real **iOS 26.5 Safari, iPhone 17 Pro Simulator** (not a physical phone): passed
  (6 taps and 6 text fields needed a scripted fallback, a simulator-automation limit).
- Xcode app: builds; 17 unit tests pass (demo data, not production).
- Reminder scheduler on the live database delivered a test reminder.
- Not yet verified: a physical iPhone, a real inbox (sign-in email), the Home Screen install.
- Real usage at that time: 1 student, SHPE unpublished (Vice President invite pending), 0 "count me" taps.
