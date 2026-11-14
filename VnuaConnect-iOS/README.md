# Vnua-connect for iPhone (SwiftUI)

Native SwiftUI app. Hofstra first; every record carries `campusId` so other campuses can be added later.

## Open and run
1. Double-click `VnuaConnect.xcodeproj` (Xcode 16+; built with Xcode 26).
2. Target **VnuaConnect** → Signing & Capabilities → pick your Team.
3. Run on a simulator or your iPhone. The camera scanner only works on a real device.
4. Skip sign-in during development: Product → Scheme → Edit Scheme → Run → Arguments → add `-demoSignIn`.
5. Tests: ⌘U (11 rule tests in `VnuaConnectTests/`).

The folders are *synchronized*: any file you add under `VnuaConnect/` is part of the app automatically.

## Layout
| Folder | What it holds |
|---|---|
| `App/` | App entry, tab bar, `AppState` (single source of truth) |
| `Design/` | Color tokens (light + dark), Figtree (titles) + SF Pro (text) type scale, buttons/cards/badges |
| `Models/` | Campus, Club, Event, Membership, Attendance, errors |
| `API/` | `VnuaAPI` protocol + `MockAPI` (port of `src/vnua-mock-api.js`). `SupabaseAPI` goes here next |
| `Features/` | Sign in, Discover, Club detail, Events, Pass (rotating QR), Officer check-in (VisionKit scanner), My Clubs, Profile |
| `Resources/Fonts/` | Figtree Bold/ExtraBold (SIL OFL, license file included) |

## Font
Titles use **Figtree** (SIL Open Font License 1.1 — free to embed and ship; `Resources/Fonts/Figtree-OFL.txt`). Body text uses SF Pro. Circular (Lineto) was removed on Nov 14, 2026 because it is commercial-only.

## Design rules (Apple HIG)
- 44pt minimum tap targets, Dynamic Type on every style, SF Symbols, VoiceOver labels.
- Light and dark mode for every color token.
- Standard patterns: tab bar (4 tabs), large titles, sheets for short tasks, confirmation dialogs for destructive actions.
- App Store requirements already in place: account deletion, report and block, support contact.

## Backend
The app talks to `VnuaAPI`, which has two implementations:
- `SupabaseAPI`: used when `VnuaConnect/Config/Supabase.plist` exists. Copy it from `Supabase.example.plist`; setup steps are in `../supabase/README.md`.
- `MockAPI`: the offline demo with fictional data, used when that file is missing.

## Next
1. Create the Supabase project and push the schema (`../supabase/README.md`), then add custom SMTP for email codes.
2. Officer tools: create/edit events, edit club page, announcements.
3. Push notifications (APNs) for event changes and approved join requests.
4. TestFlight with 2–3 clubs.
