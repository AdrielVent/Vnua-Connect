import SwiftUI
import Observation

struct Banner: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var isError: Bool
}

/// Single source of truth for the UI. Views read from here and call its async actions.
@Observable
@MainActor
final class AppState {
    let api: any VnuaAPI
    let campus: Campus

    var user: UserProfile?
    var clubs: [Club] = []
    var events: [ClubEvent] = []
    var memberships: [String: Membership] = [:]
    var rsvps: Set<String> = []
    var blockedClubIds: Set<String> = []
    var isLoading = false
    var isRestoring = true
    var banner: Banner?
    /// True when running on MockAPI (no Supabase.plist). Shown as a hint on the sign-in screen.
    var isDemo: Bool { api is MockAPI }

    init(api: any VnuaAPI, campus: Campus = .hofstra) {
        self.api = api
        self.campus = campus
    }

    // MARK: derived

    var visibleClubs: [Club] { clubs.filter { !blockedClubIds.contains($0.id) } }
    var visibleEvents: [ClubEvent] { events.filter { !$0.hostClubIds.allSatisfy(blockedClubIds.contains) } }
    var interests: [String] { Array(Set(clubs.map(\.interest))).sorted() }

    func club(_ id: String) -> Club? { clubs.first { $0.id == id } }
    func membership(_ clubId: String) -> Membership? { memberships[clubId] }
    func isOfficer(of clubId: String) -> Bool {
        memberships[clubId].map { $0.role == .officer && $0.status == .active } ?? false
    }
    func canRunCheckIn(for event: ClubEvent) -> Bool { event.hostClubIds.contains(where: isOfficer(of:)) }
    func events(for clubId: String) -> [ClubEvent] { events.filter { $0.hostClubIds.contains(clubId) } }
    func hostNames(_ event: ClubEvent) -> String {
        event.hostClubIds.compactMap { club($0)?.name }.joined(separator: " + ")
    }

    // MARK: actions

    func show(_ message: String, error: Bool = false) {
        banner = Banner(message: message, isError: error)
        let id = banner?.id
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if banner?.id == id { banner = nil }
        }
    }

    /// Runs an API call and turns any failure into a friendly banner. Returns nil on failure.
    @discardableResult
    func run<T>(_ op: () async throws -> T) async -> T? {
        do { return try await op() }
        catch {
            show((error as? LocalizedError)?.errorDescription ?? "Something went wrong.", error: true)
            return nil
        }
    }

    /// Called once at launch: picks up a saved session so students don't sign in every time.
    func restore() async {
        defer { isRestoring = false }
        if let profile = await api.restoreSession() { await signedIn(profile) }
    }

    func signedIn(_ profile: UserProfile) async {
        user = profile
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        await run {
            async let c = api.clubs(campusId: campus.id)
            async let e = api.events(campusId: campus.id)
            async let m = api.memberships()
            async let r = api.rsvps()
            async let b = api.blockedClubs()
            let (cs, es, ms, rs, bs) = try await (c, e, m, r, b)
            blockedClubIds = bs
            clubs = cs
            events = es
            memberships = Dictionary(uniqueKeysWithValues: ms.map { ($0.clubId, $0) })
            rsvps = rs
        }
    }

    func join(_ club: Club, role: MemberRole, contact: ContactPreference) async {
        let rid = UUID().uuidString
        if let m = await run({ try await api.join(clubId: club.id, role: role, contact: contact, requestId: rid) }) {
            memberships[club.id] = m
            show(m.status == .pending ? "Request sent to \(club.name)'s officers" : "You joined \(club.name)")
        }
    }

    func leave(_ club: Club) async {
        if await run({ try await api.leave(clubId: club.id) }) != nil {
            memberships[club.id] = nil
            show("You left \(club.name)")
        }
    }

    func updateContact(_ club: Club, _ contact: ContactPreference) async {
        if await run({ try await api.updateContact(clubId: club.id, contact: contact) }) != nil {
            memberships[club.id]?.contact = contact
        }
    }

    func toggleRSVP(_ event: ClubEvent) async {
        let going = !rsvps.contains(event.id)
        let rid = UUID().uuidString
        // Optimistic update, rolled back on failure.
        if going { rsvps.insert(event.id) } else { rsvps.remove(event.id) }
        let result = await run { try await api.setRSVP(eventId: event.id, going: going, requestId: rid) }
        if result == nil {
            if going { rsvps.remove(event.id) } else { rsvps.insert(event.id) }
        }
    }

    func setBlocked(_ club: Club, _ blocked: Bool) async {
        if await run({ try await api.setBlocked(clubId: club.id, blocked: blocked) }) != nil {
            if blocked { blockedClubIds.insert(club.id); show("You won't see \(club.name) anymore") }
            else { blockedClubIds.remove(club.id) }
        }
    }

    func signOut() async {
        await api.signOut()
        clearLocal()
    }

    func deleteAccount() async {
        if await run({ try await api.deleteAccount() }) != nil { clearLocal() }
    }

    private func clearLocal() {
        user = nil
        clubs = []; events = []; memberships = [:]; rsvps = []; blockedClubIds = []
    }
}
