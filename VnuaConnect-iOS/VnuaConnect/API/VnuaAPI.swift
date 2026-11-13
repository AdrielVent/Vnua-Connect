import Foundation

/// The one contract the UI talks to. Two implementations:
///  - MockAPI: in-memory, used for previews, tests, and building UI offline (port of src/vnua-mock-api.js)
///  - SupabaseAPI (next step): the real backend. The server must enforce every role check the mock enforces.
///
/// Proposed production endpoints (same as the web prototype):
///   PUT    /v1/events/:eventId/rsvp                {going}
///   POST   /v1/clubs/:clubId/memberships           {role:'member'|'founding', contact}   (never 'officer')
///   PATCH  /v1/clubs/:clubId/memberships/me       {contact}
///   DELETE /v1/clubs/:clubId/memberships/me       -> last_admin if caller is the final administrator
///   POST   /v1/events/:eventId/passes              -> {token, expiresAt}   (opaque, short-lived, event-bound)
///   POST   /v1/events/:eventId/checkins            {token|memberId, requestId} -> {status, recordId}
///   POST   /v1/attendance/:recordId/corrections    {reason}               (reason required; original kept)
///
/// `requestId` makes writes idempotent: retrying with the same id returns the first successful result.
protocol VnuaAPI: Sendable {
    // Auth (email one-time code, school domain only)
    func requestCode(email: String, campus: Campus) async throws
    func verify(email: String, name: String, code: String, campus: Campus) async throws -> UserProfile
    func deleteAccount() async throws

    // Directory
    func clubs(campusId: String) async throws -> [Club]
    func events(campusId: String) async throws -> [ClubEvent]

    // Me
    func memberships() async throws -> [Membership]
    func rsvps() async throws -> Set<String>
    func involvement() async throws -> [AttendanceRecord]

    // Membership
    func join(clubId: String, role: MemberRole, contact: ContactPreference, requestId: String) async throws -> Membership
    func updateContact(clubId: String, contact: ContactPreference) async throws
    func leave(clubId: String) async throws

    // Events
    func setRSVP(eventId: String, going: Bool, requestId: String) async throws -> Bool
    func issuePass(eventId: String) async throws -> EventPass

    // Officer tools
    func checkIn(eventId: String, subject: CheckInSubject, requestId: String) async throws -> CheckInResult
    func correct(recordId: String, reason: String, requestId: String) async throws
    func attendance(eventId: String) async throws -> [AttendanceRecord]

    // Safety (App Store guideline 1.2: user-generated content needs reporting)
    func report(targetId: String, reason: ReportReason, detail: String) async throws
}
