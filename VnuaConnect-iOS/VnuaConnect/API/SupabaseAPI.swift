import Foundation
import Supabase

/// Reads VnuaConnect/Config/Supabase.plist (git-ignored). Missing or placeholder → the app uses MockAPI.
struct SupabaseConfig {
    let url: URL
    let anonKey: String

    static func load(bundle: Bundle = .main) -> SupabaseConfig? {
        guard let file = bundle.url(forResource: "Supabase", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: file) as? [String: Any],
              let urlString = dict["SUPABASE_URL"] as? String, !urlString.contains("YOUR-PROJECT"),
              let url = URL(string: urlString),
              let key = dict["SUPABASE_ANON_KEY"] as? String, !key.isEmpty, !key.hasPrefix("YOUR")
        else { return nil }
        return SupabaseConfig(url: url, anonKey: key)
    }
}

/// Real backend. All rules live in Postgres (supabase/migrations); this file only translates.
final class SupabaseAPI: VnuaAPI {
    private let client: SupabaseClient

    init(config: SupabaseConfig) {
        client = SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey,
                                options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true)))
    }

    // MARK: - Auth

    func restoreSession() async -> UserProfile? {
        guard let session = try? await client.auth.session else { return nil }
        return try? await profile(session.user.id)
    }

    func requestCode(email: String, name: String, campus: Campus) async throws {
        // Check the domain here for a friendly message; the database trigger enforces it for real.
        guard campus.allows(email: email) else { throw APIError.validation("Use your \(campus.name) email address.") }
        try await call {
            try await client.auth.signInWithOTP(email: email.lowercased(), shouldCreateUser: true,
                                                data: ["name": .string(name.trimmingCharacters(in: .whitespaces))])
        }
    }

    func verify(email: String, name: String, code: String, campus: Campus) async throws -> UserProfile {
        try await call {
            let res = try await client.auth.verifyOTP(email: email.lowercased(), token: code, type: .email)
            return try await profile(res.user.id)
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    func deleteAccount() async throws {
        try await call { try await client.rpc("delete_account").execute() }
        try? await client.auth.signOut(scope: .local)
    }

    private func profile(_ id: UUID) async throws -> UserProfile {
        let p: ProfileRow = try await client.from("profiles").select().eq("id", value: id).single().execute().value
        return UserProfile(id: p.id.lower, name: p.name, email: p.email, campusId: p.campus_id)
    }

    private func myId() async throws -> UUID {
        guard let id = try? await client.auth.session.user.id else { throw APIError.validation("Please sign in again.") }
        return id
    }

    // MARK: - Directory

    func clubs(campusId: String) async throws -> [Club] {
        try await call {
            async let clubRows: [DBClub] = client.from("clubs").select().eq("campus_id", value: campusId)
                .order("name").execute().value
            async let officerRows: [OfficerRow] = client.from("club_officers").select().execute().value
            let (cs, os) = try await (clubRows, officerRows)
            let officers = Dictionary(grouping: os, by: { $0.club_id.lower })
            return cs.map { $0.model(officers: officers[$0.id.lower] ?? []) }
        }
    }

    func events(campusId: String) async throws -> [ClubEvent] {
        try await call {
            let rows: [DBEvent] = try await client.from("events").select("*, event_hosts(club_id)")
                .eq("campus_id", value: campusId).order("starts_at").execute().value
            return rows.map(\.model)
        }
    }

    // MARK: - Me

    func memberships() async throws -> [Membership] {
        try await call {
            let me = try await myId()
            let rows: [MembershipRow] = try await client.from("memberships").select()
                .eq("user_id", value: me).execute().value
            return rows.map(\.model)
        }
    }

    func rsvps() async throws -> Set<String> {
        try await call {
            let me = try await myId()
            let rows: [EventIdRow] = try await client.from("rsvps").select("event_id").eq("user_id", value: me).execute().value
            return Set(rows.map { $0.event_id.lower })
        }
    }

    func involvement() async throws -> [AttendanceRecord] {
        try await call {
            let me = try await myId()
            let rows: [AttendanceRow] = try await client.from("attendance").select()
                .eq("user_id", value: me).is("removed_at", value: nil)
                .order("recorded_at", ascending: false).execute().value
            return rows.map(\.model)
        }
    }

    func blockedClubs() async throws -> Set<String> {
        try await call {
            let rows: [ClubIdRow] = try await client.from("club_blocks").select("club_id").execute().value
            return Set(rows.map { $0.club_id.lower })
        }
    }

    func setBlocked(clubId: String, blocked: Bool) async throws {
        try await call { try await client.rpc("block_club", params: ["p_club": AnyJSON.string(clubId), "p_blocked": .bool(blocked)]).execute() }
    }

    // MARK: - Membership

    func join(clubId: String, role: MemberRole, contact: ContactPreference, requestId: String) async throws -> Membership {
        try await call {
            let row: MembershipRow = try await client.rpc("join_club", params: [
                "p_club": clubId, "p_role": role.rawValue, "p_contact": contact.rawValue, "p_request": requestId,
            ]).execute().value
            return row.model
        }
    }

    func updateContact(clubId: String, contact: ContactPreference) async throws {
        try await call { try await client.rpc("update_contact", params: ["p_club": clubId, "p_contact": contact.rawValue]).execute() }
    }

    func leave(clubId: String) async throws {
        try await call { try await client.rpc("leave_club", params: ["p_club": clubId]).execute() }
    }

    func joinRequests(clubId: String) async throws -> [JoinRequest] {
        try await call {
            let rows: [JoinRequestRow] = try await client.rpc("join_requests", params: ["p_club": clubId]).execute().value
            return rows.map { JoinRequest(userId: $0.user_id.lower, name: $0.name, role: $0.role, requestedAt: $0.requested_at) }
        }
    }

    func reviewJoinRequest(clubId: String, userId: String, approve: Bool) async throws {
        try await call {
            try await client.rpc("review_join_request", params: [
                "p_club": AnyJSON.string(clubId), "p_user": .string(userId), "p_approve": .bool(approve),
            ]).execute()
        }
    }

    // MARK: - Events

    func setRSVP(eventId: String, going: Bool, requestId: String) async throws -> Bool {
        try await call {
            try await client.rpc("set_rsvp", params: [
                "p_event": AnyJSON.string(eventId), "p_going": .bool(going), "p_request": .string(requestId),
            ]).execute().value
        }
    }

    func issuePass(eventId: String) async throws -> EventPass {
        try await call {
            let row: PassRow = try await client.rpc("issue_pass", params: ["p_event": eventId]).execute().value
            return EventPass(token: row.token, eventId: row.event_id.lower, expiresAt: row.expires_at)
        }
    }

    // MARK: - Officer tools

    func searchAttendees(eventId: String, query: String) async throws -> [MemberSummary] {
        try await call {
            let rows: [PersonRow] = try await client.rpc("search_attendees", params: ["p_event": eventId, "p_query": query])
                .execute().value
            return rows.map { MemberSummary(id: $0.user_id.lower, name: $0.name) }
        }
    }

    func checkIn(eventId: String, subject: CheckInSubject, requestId: String) async throws -> CheckInResult {
        var params: [String: String] = ["p_event": eventId, "p_request": requestId]
        switch subject {
        case .pass(let token): params["p_token"] = token
        case .member(let id, _): params["p_member"] = id
        case .guest(let name): params["p_guest_name"] = name
        }
        return try await call {
            let row: CheckInRow = try await client.rpc("check_in", params: params).execute().value
            return CheckInResult(status: row.status == "duplicate" ? .duplicate : .recorded, record: row.record.model)
        }
    }

    func correct(recordId: String, reason: String, requestId: String) async throws {
        try await call {
            try await client.rpc("correct_attendance", params: ["p_record": recordId, "p_reason": reason, "p_request": requestId])
                .execute()
        }
    }

    func attendance(eventId: String) async throws -> [AttendanceRecord] {
        try await call {
            let rows: [AttendanceRow] = try await client.from("attendance").select().eq("event_id", value: eventId)
                .order("recorded_at", ascending: false).execute().value
            return rows.map(\.model)
        }
    }

    // MARK: - Safety

    func report(targetType: String, targetId: String, reason: ReportReason, detail: String) async throws {
        try await call {
            try await client.rpc("report_content", params: [
                "p_type": targetType, "p_target": targetId, "p_reason": reason.dbValue, "p_detail": detail,
            ]).execute()
        }
    }

    // MARK: - Error mapping

    /// Database functions raise 'code|message'. Translate everything into APIError.
    @discardableResult
    private func call<T>(_ op: () async throws -> T) async throws -> T {
        do {
            return try await op()
        } catch let e as APIError {
            throw e
        } catch let e as PostgrestError {
            throw Self.map(e.message)
        } catch is URLError {
            throw APIError.network
        } catch let e as AuthError {
            let msg = e.localizedDescription
            if msg.localizedCaseInsensitiveContains("saving new user") { throw APIError.validation("Use your school email address.") }
            if msg.localizedCaseInsensitiveContains("expired") || msg.localizedCaseInsensitiveContains("invalid") {
                throw APIError.validation("That code is wrong or expired. Request a new one.")
            }
            if msg.localizedCaseInsensitiveContains("rate limit") {
                throw APIError.validation("Too many codes requested. Wait a minute and try again.")
            }
            throw APIError.validation(msg)
        } catch {
            if (error as NSError).domain == NSURLErrorDomain { throw APIError.network }
            throw APIError.validation(error.localizedDescription)
        }
    }

    static func map(_ message: String) -> APIError {
        let parts = message.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return .validation(message) }
        switch parts[0] {
        case "forbidden_role": return .forbiddenRole
        case "forbidden": return .forbidden
        case "last_admin": return .lastAdmin
        case "not_found": return .notFound
        default: return .validation(parts[1])
        }
    }
}

// MARK: - Database rows (snake_case mirrors the SQL columns)

private extension UUID { var lower: String { uuidString.lowercased() } }

private struct ProfileRow: Decodable { let id: UUID; let campus_id: String; let name: String; let email: String }
private struct EventIdRow: Decodable { let event_id: UUID }
private struct ClubIdRow: Decodable { let club_id: UUID }
private struct PersonRow: Decodable { let user_id: UUID; let name: String }
private struct PassRow: Decodable { let token: String; let event_id: UUID; let expires_at: Date }
private struct OfficerRow: Decodable { let club_id: UUID; let name: String; let title: String; let ask_about: String }
private struct JoinRequestRow: Decodable { let user_id: UUID; let name: String; let role: MemberRole; let requested_at: Date }
private struct CheckInRow: Decodable { let status: String; let record: AttendanceRow }

private struct DBClub: Decodable {
    let id: UUID, campus_id: String, monogram: String, accent_hex: String, name: String, interest: String
    let blurb: String, about: String, recognition: String, funded: Bool?, affiliation: String?, requires_approval: Bool

    func model(officers: [OfficerRow]) -> Club {
        Club(id: id.lower, campusId: campus_id, monogram: monogram, accentHex: accent_hex, name: name, interest: interest,
             blurb: blurb, about: about,
             recognition: recognition == "recognized" ? .recognized : recognition == "not_recognized" ? .notRecognized : .notStated,
             funded: funded, affiliation: affiliation, requiresApproval: requires_approval,
             officers: officers.map { Officer(name: $0.name, title: $0.title, askAbout: $0.ask_about) })
    }
}

private struct DBEvent: Decodable {
    struct Host: Decodable { let club_id: UUID }
    let id: UUID, campus_id: String, title: String, starts_at: Date, duration_minutes: Int, location: String
    let details: String, organizer: String, status: EventStatus, previous_start: Date?, event_hosts: [Host]

    var model: ClubEvent {
        ClubEvent(id: id.lower, campusId: campus_id, hostClubIds: event_hosts.map { $0.club_id.lower }, title: title,
                  start: starts_at, durationMinutes: duration_minutes, location: location, details: details,
                  organizer: organizer, status: status, previousStart: previous_start)
    }
}

private struct MembershipRow: Decodable {
    let club_id: UUID, role: MemberRole, status: MembershipStatus, contact: ContactPreference
    var model: Membership { Membership(clubId: club_id.lower, role: role, status: status, contact: contact) }
}

private struct AttendanceRow: Decodable {
    let id: UUID, event_id: UUID, attendee_name: String, mode: String, recorded_at: Date
    let recorded_by_name: String, removed_reason: String?

    var model: AttendanceRecord {
        AttendanceRecord(id: id.lower, eventId: event_id.lower, attendeeName: attendee_name,
                         mode: mode == "pass" ? .pass : mode == "guest" ? .guest : .lookup,
                         recordedAt: recorded_at, recordedBy: recorded_by_name, removedReason: removed_reason)
    }
}
