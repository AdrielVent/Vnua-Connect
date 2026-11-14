# Design decisions and their sources

Every layout change below names the real app screens it follows (from Mobbin, a library of real app screenshots) or the
published source behind it. Colors stay Vnua-connect's own: SHPE navy and AIAA navy/blue with an accessible orange,
because SHPE and AIAA (and being turned down for official status) are why this app exists.

## Shared club page (what a student sees after tapping a club link), Nov 14, 2026
Picked direction **B: club page, Join pinned** over A (compact invite card).

| Change | Why | Following |
|---|---|---|
| **Join and Help build pinned to the bottom of the screen**, details scroll above | The student reads about the club and can tap Join at any moment without scrolling back up | [Lex](https://mobbin.com/screens/7b51df1e-40e1-43cc-8edd-b49e3aab8cb5), [Meetup](https://mobbin.com/screens/0341b80b-28fa-47a2-84b4-f021716a5d45), [Garmin Connect](https://mobbin.com/screens/627a1298-04d1-4317-8fcb-5bcad28d3d24), [Numo](https://mobbin.com/screens/efb59933-58d0-42ee-8983-944ef8c75e11) |
| **Members line with a few faces** ("4 members · Games") instead of separate tag pills | Who's in it and what it's about, in one glance under the name | Faces: [Meetup](https://mobbin.com/screens/0341b80b-28fa-47a2-84b4-f021716a5d45), [Numo](https://mobbin.com/screens/efb59933-58d0-42ee-8983-944ef8c75e11). "X members" under the name: [Lex](https://mobbin.com/screens/7b51df1e-40e1-43cc-8edd-b49e3aab8cb5), [LinkedIn](https://mobbin.com/screens/ac13a36e-3ce7-44d9-9b36-79de94237e0d), [Facebook](https://mobbin.com/screens/179eee97-51da-4a62-84cd-493f02e5183e) |
| **Share in the top corner** | The page is meant to be forwarded into other group chats | [Meetup](https://mobbin.com/screens/0341b80b-28fa-47a2-84b4-f021716a5d45) (share in the top bar), [Glassdoor](https://mobbin.com/screens/a796641b-e71a-4fd2-82fb-255e5fd01149) (share beside Join), [LinkedIn](https://mobbin.com/screens/ac13a36e-3ce7-44d9-9b36-79de94237e0d) (more button beside Join) |

Kept as they were: both buttons and their wording, the e-board with first names only, the sign-in line, the
not-affiliated line. Not taken: GroupMe's one-icon-per-fact rows ([GroupMe](https://mobbin.com/screens/3009b756-017f-46ce-8c53-98691f239ef7)),
which belong to direction A; mixing both layouts would undo B.

## Why no group chat, and why members choose their notifications
Student newspapers report that big club chats get muted and ignored:
- Duke: many students are "opting to simply mute the continuous stream of texts" — [Duke Chronicle, 2021](https://www.dukechronicle.com/article/2021/04/duke-university-first-year-student-group-chat-active-fraternity-social-life)
- Bucknell: members "mute the chat or ignore the messages sent" — [The Bucknellian](https://bucknellian.net/?p=126849)
- Northwestern: bot accounts in large student-org chats — [Daily Northwestern, 2024](https://dailynorthwestern.com/2024/11/06/lateststories/groupme-chatbots-raise-frustrations-for-student-organizations)

These are reported student experiences, not a survey. Reddit threads could not be read directly (Reddit blocks the
search tool used), so none are quoted.

## Earlier visual cleanup
See the sources in the commit history and `docs/COMPETITION.md`: Fountain Institute's "7 signs a UI has been vibe coded",
the Nutlope/hallmark anti-pattern list, and Lucide's icon design guide.
