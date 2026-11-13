import Foundation

/// The one contract the UI talks to. Two implementations:
///  - MockAPI: in-memory, used for previews, tests, and building UI offline (port of src/vnua-mock-api.js)
///  - SupabaseAPI (next step): the real backend. The server must enforce every role check the mock enforces.
///
/// Server side: supabase/migrations/*.sql. Every write is a Postgres function (RPC) that re-checks the caller,
/// so the app can never grant itself more than the rules allow. Tests: supabase/tests/run_local.sh.
///
/// `requestId` makes writes idempotent: retrying with the same id returns the first successful result.
protocol VnuaAPI: Sendable {
    // Auth (email one-time code, school domain only)
    func restoreSession() async -> UserProfile?
    func requestCode(email: String, name: String, campus: Campus) async throws
    func verify(email: String, name: String, code: String, campus: Campus) async throws -> UserProfile
    /// Handles the sign-in link from the email (vnuaconnect://login-callback). Returns nil if the URL isn't ours.
    func handleAuthURL(_ url: URL) async throws -> UserProfile?
    func signOut() async
    func deleteAccount() async throws

    // Directory
    func clubs(campusId: String) async throws -> [Club]
    func events(campusId: String) async throws -> [ClubEvent]

    // Me
    func memberships() async throws -> [Membership]
    func rsvps() async throws -> Set<String>
    func involvement() async throws -> [AttendanceRecord]
    func blockedClubs() async throws -> Set<String>
    func setBlocked(clubId: String, blocked: Bool) async throws

    // Membership
    func join(clubId: String, role: MemberRole, contact: ContactPreference, requestId: String) async throws -> Membership
    func updateContact(clubId: String, contact: ContactPreference) async throws
    func leave(clubId: String) async throws
    func joinRequests(clubId: String) async throws -> [JoinRequest]
    func reviewJoinRequest(clubId: String, userId: String, approve: Bool) async throws
    /// Found a new club. The caller becomes its officer; it's hidden from others until a moderator publishes it.
    func createClub(_ draft: ClubDraft) async throws -> String

    // Events
    func setRSVP(eventId: String, going: Bool, requestId: String) async throws -> Bool
    func issuePass(eventId: String) async throws -> EventPass
    func createEvent(_ draft: EventDraft, requestId: String) async throws -> String
    func cancelEvent(eventId: String) async throws

    // Officer tools
    func searchAttendees(eventId: String, query: String) async throws -> [MemberSummary]
    func checkIn(eventId: String, subject: CheckInSubject, requestId: String) async throws -> CheckInResult
    func correct(recordId: String, reason: String, requestId: String) async throws
    func attendance(eventId: String) async throws -> [AttendanceRecord]

    // Safety (App Store guideline 1.2: user-generated content needs reporting)
    func report(targetType: String, targetId: String, reason: ReportReason, detail: String) async throws
}
