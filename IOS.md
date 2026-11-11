# iOS / App Store plan (native target)

Vnua-connect ships as an **iPhone app built in Xcode**. The research plan suggested a web pilot first. You chose the App Store as the target, so the plan below keeps the research plan's safety gates and packages the existing UI with **Capacitor**, which avoids a rewrite. These steps haven't been run yet and are untested.

## One-time setup (on a Mac)
1. Install Xcode from the Mac App Store and Node 20+.
2. Enroll in the Apple Developer Program ($99/year). Decide who owns the account after you graduate.
3. In this folder, run:
```
npm install
npm run ios:add      # creates ios/ Xcode project
npm run ios:sync
npm run ios:open     # opens Xcode → pick your Team under Signing → Run on your iPhone
```
4. In `ios/App/App/Info.plist`, add `NSCameraUsageDescription` with the text "Scan members' check-in passes at your club's events."
5. In Xcode, go to Signing & Capabilities and add **Push Notifications**. Then create an APNs key in the Apple Developer portal.

## Native features to wire (replacing simulated ones)
| Prototype (simulated) | Native implementation |
|---|---|
| "Scan a member's pass" button | `@capacitor-mlkit/barcode-scanning` live scanner. Keep the manual lookup as the fallback |
| Event and invite notifications | `@capacitor/push-notifications` + APNs, sent from Supabase Edge Functions. Ask permission only after the user joins a club |
| `vnua-mock-api.js` | Supabase adapter (email OTP, Postgres + row-level security), using the same `{ok, data/error}` contract |
| Recognition roster invites | A push notification plus an in-app card; the member must accept |

## App Store review requirements (Apple guidelines)
- In-app **account deletion**.
- **Report** and **block** controls for user-generated content (club pages and events), plus a published support contact.
- A privacy policy URL and App Privacy "nutrition labels": email, name, attendance (linked to the user, not used for tracking).
- Enough native value to not count as a repackaged website: the camera scanner, push notifications and check-in pass already provide it.
- Test with TestFlight on physical iPhones, including VoiceOver, before you submit.

## Order of work
1. Supabase schema, row-level security and cross-club denial tests (research plan B1–B12).
2. Swap the mock adapter for Supabase.
3. Capacitor iOS shell, native scanner and push.
4. TestFlight pilot with 2–3 clubs.
5. App Store submission.
