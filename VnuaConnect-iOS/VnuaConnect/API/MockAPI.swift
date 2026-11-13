import Foundation

/// In-memory stand-in for the server. NOT security: it only models the rules the real server must enforce.
/// All data is fictional (same seed as the web prototype).
actor MockAPI: VnuaAPI {
    /// Set to true to make the next call fail with `.network` (tests the retry UI).
    var failNext = false
    var latency: Duration = .milliseconds(150)

    private var user: UserProfile?
    private var clubList: [Club]
    private var eventList: [ClubEvent]
    private var memberships: [String: Membership] = [:]        // clubId -> membership (current user)
    private var rsvpSet: Set<String> = []
    private var records: [AttendanceRecord] = []
    private var passes: [String: (eventId: String, name: String, expiresAt: Date)] = [:]
    private var idempotency: [String: any Sendable] = [:]
    private(set) var reports: [(String, ReportReason, String)] = []

    init(now: Date = .now) {
        clubList = MockSeed.clubs
        eventList = MockSeed.events(relativeTo: now)
        records = [AttendanceRecord(id: "rec_seed_priya", eventId: "e1", attendeeName: "Priya N.", mode: .lookup,
                                    recordedAt: now.addingTimeInterval(-3600), recordedBy: "Ava R.")]
    }

    func setFailNext(_ v: Bool) { failNext = v }
    func setLatency(_ d: Duration) { latency = d }

    // MARK: plumbing

    private func gate() async throws {
        try? await Task.sleep(for: latency)
        if failNext { failNext = false; throw APIError.network }
    }

    private func idempotent<T: Sendable>(_ requestId: String, _ body: () throws -> T) async throws -> T {
        try await gate()
        if let cached = idempotency[requestId] as? T { return cached }
        let result = try body()               // failures are not cached
        idempotency[requestId] = result
        return result
    }

    private func requireUser() throws -> UserProfile {
        guard let user else { throw APIError.validation("Please sign in again.") }
        return user
    }

    private func isOfficer(ofHostsOf eventId: String) -> Bool {
        guard let e = eventList.first(where: { $0.id == eventId }) else { return false }
        return e.hostClubIds.contains { memberships[$0]?.role == .officer && memberships[$0]?.status == .active }
    }

    // MARK: auth

    func requestCode(email: String, campus: Campus) async throws {
        try await gate()
        guard email.contains("@"), campus.allows(email: email) else {
            throw APIError.validation("Use your \(campus.name) email address.")
        }
    }

    func verify(email: String, name: String, code: String, campus: Campus) async throws -> UserProfile {
        try await gate()
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw APIError.validation("Enter the 6-digit code from your email.")
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw APIError.validation("Enter your name.") }
        let profile = UserProfile(id: "u_demo", name: trimmed, email: email.lowercased(), campusId: campus.id)
        user = profile
        // Demo roles from the web prototype: officer of the drama club, member of the rocket club.
        memberships = [
            "drama": Membership(clubId: "drama", role: .officer, status: .active, contact: .organizing),
            "rocket": Membership(clubId: "rocket", role: .member, status: .active, contact: .events),
        ]
        return profile
    }

    func deleteAccount() async throws {
        try await gate()
        user = nil
        memberships = [:]
        rsvpSet = []
    }

    // MARK: directory

    func clubs(campusId: String) async throws -> [Club] {
        try await gate()
        return clubList.filter { $0.campusId == campusId }
    }

    func events(campusId: String) async throws -> [ClubEvent] {
        try await gate()
        return eventList.filter { $0.campusId == campusId }.sorted { $0.start < $1.start }
    }

    // MARK: me

    func memberships() async throws -> [Membership] {
        try await gate()
        return Array(memberships.values)
    }

    func rsvps() async throws -> Set<String> {
        try await gate()
        return rsvpSet
    }

    func involvement() async throws -> [AttendanceRecord] {
        try await gate()
        let me = try requireUser()
        return records.filter { $0.attendeeName == me.name && $0.removedReason == nil }
    }

    // MARK: membership

    func join(clubId: String, role: MemberRole, contact: ContactPreference, requestId: String) async throws -> Membership {
        try await idempotent(requestId) {
            _ = try requireUser()
            guard role == .member || role == .founding else { throw APIError.forbiddenRole }
            guard let club = clubList.first(where: { $0.id == clubId }) else { throw APIError.notFound }
            let m = Membership(clubId: clubId, role: role, status: club.requiresApproval ? .pending : .active, contact: contact)
            memberships[clubId] = m
            return m
        }
    }

    func updateContact(clubId: String, contact: ContactPreference) async throws {
        try await gate()
        guard memberships[clubId] != nil else { throw APIError.notFound }
        memberships[clubId]?.contact = contact
    }

    func leave(clubId: String) async throws {
        try await gate()
        if memberships[clubId]?.role == .officer { throw APIError.lastAdmin }
        memberships[clubId] = nil
    }

    // MARK: events

    func setRSVP(eventId: String, going: Bool, requestId: String) async throws -> Bool {
        try await idempotent(requestId) {
            _ = try requireUser()
            guard let e = eventList.first(where: { $0.id == eventId }) else { throw APIError.notFound }
            if going && e.status == .cancelled { throw APIError.validation("This event was cancelled.") }
            if going { rsvpSet.insert(eventId) } else { rsvpSet.remove(eventId) }   // never touches attendance
            return going
        }
    }

    func issuePass(eventId: String) async throws -> EventPass {
        try await gate()
        let me = try requireUser()
        let token = "VNUA-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10))
        let expires = Date.now.addingTimeInterval(45)
        passes[token] = (eventId, me.name, expires)
        return EventPass(token: token, eventId: eventId, expiresAt: expires)
    }

    // MARK: officer tools

    func checkIn(eventId: String, subject: CheckInSubject, requestId: String) async throws -> CheckInResult {
        try await idempotent(requestId) {
            let me = try requireUser()
            guard isOfficer(ofHostsOf: eventId) else { throw APIError.forbidden }

            let name: String
            let mode: AttendanceRecord.Mode
            switch subject {
            case .pass(let token):
                guard let p = passes[token] else { throw APIError.validation("That code isn't a Vnua-connect pass.") }
                guard p.eventId == eventId else { throw APIError.validation("This pass is for a different event.") }
                guard p.expiresAt > .now else { throw APIError.validation("This pass expired. Ask them to refresh it.") }
                name = p.name; mode = .pass
            case .member(let n):
                name = n.trimmingCharacters(in: .whitespaces); mode = .lookup
            case .guest(let n):
                name = n.trimmingCharacters(in: .whitespaces) + " (guest)"; mode = .guest
            }
            guard !name.isEmpty else { throw APIError.validation("Enter a name.") }

            // Uniqueness: one live record per (event, attendee). Joint events count each person once.
            if let existing = records.first(where: { $0.eventId == eventId && $0.attendeeName == name && $0.removedReason == nil }) {
                return CheckInResult(status: .duplicate, record: existing)
            }
            let rec = AttendanceRecord(id: "rec_" + UUID().uuidString.prefix(6).lowercased(), eventId: eventId,
                                       attendeeName: name, mode: mode, recordedAt: .now, recordedBy: me.name)
            records.append(rec)
            return CheckInResult(status: .recorded, record: rec)
        }
    }

    func correct(recordId: String, reason: String, requestId: String) async throws {
        _ = try await idempotent(requestId) { () -> Bool in
            let r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !r.isEmpty else { throw APIError.validation("A reason is required.") }
            guard let i = records.firstIndex(where: { $0.id == recordId }) else { throw APIError.notFound }
            guard isOfficer(ofHostsOf: records[i].eventId) else { throw APIError.forbidden }
            records[i].removedReason = r
            return true
        }
    }

    func attendance(eventId: String) async throws -> [AttendanceRecord] {
        try await gate()
        guard isOfficer(ofHostsOf: eventId) else { throw APIError.forbidden }
        return records.filter { $0.eventId == eventId }.sorted { $0.recordedAt > $1.recordedAt }
    }

    // MARK: safety

    func report(targetId: String, reason: ReportReason, detail: String) async throws {
        try await gate()
        reports.append((targetId, reason, detail))
    }
}

enum MockSeed {
    static let clubs: [Club] = [
        Club(id: "drama", campusId: "hofstra", monogram: "LD", accentHex: "#1f5a6b", name: "Lowlight Drama Collective",
             interest: "Performing arts", blurb: "Readings, rehearsals and small shows. All experience levels.",
             about: "A student-led group that stages readings and short productions. No auditions to join; roles are opt-in per show.",
             recognition: .notRecognized, funded: false, affiliation: nil, requiresApproval: false,
             officers: [Officer(name: "Ava R.", title: "President", askAbout: "General questions and partnerships"),
                        Officer(name: "Mina K.", title: "Vice president", askAbout: "Event ideas and rehearsals"),
                        Officer(name: "Jules A.", title: "Secretary", askAbout: "Access needs and sign-up problems")]),
        Club(id: "rocket", campusId: "hofstra", monogram: "OA", accentHex: "#2c455d", name: "Orbit & Airframe Society",
             interest: "Engineering", blurb: "Build nights for rockets, gliders and anyone flight-curious.",
             about: "Hands-on aerospace builds and talks. Open to any major.",
             recognition: .recognized, funded: false, affiliation: "Self-reported national chapter · not verified",
             requiresApproval: false, officers: [Officer(name: "Dev S.", title: "President", askAbout: "Build nights")]),
        Club(id: "pottery", campusId: "hofstra", monogram: "HP", accentHex: "#7a4f12", name: "Harbor Street Pottery Circle",
             interest: "Creative", blurb: "Wheel and hand-building sessions. Beginners welcome.",
             about: "Casual weekly sessions at a shared studio. Studio space is limited, so officers approve new members.",
             recognition: .notStated, funded: nil, affiliation: nil, requiresApproval: true,
             officers: [Officer(name: "Noor B.", title: "Founder", askAbout: "Studio times")]),
        Club(id: "service", campusId: "hofstra", monogram: "NT", accentHex: "#2f5d3a", name: "Neighbor Table Service Crew",
             interest: "Service", blurb: "Pantry shifts and neighborhood meal prep.",
             about: "Volunteer shifts with local partners.",
             recognition: .notStated, funded: nil, affiliation: nil, requiresApproval: false,
             officers: [Officer(name: "Tess W.", title: "Coordinator", askAbout: "Shift sign-ups")]),
        Club(id: "law", campusId: "hofstra", monogram: "PL", accentHex: "#4a3a6b", name: "Pre-Law Reading Group",
             interest: "Academic", blurb: "Short readings, long conversations. Any major.",
             about: "Biweekly discussion of articles and cases.",
             recognition: .recognized, funded: true, affiliation: nil, requiresApproval: false,
             officers: [Officer(name: "Rowan E.", title: "Chair", askAbout: "Reading list")]),
    ]

    static func events(relativeTo now: Date) -> [ClubEvent] {
        let cal = Calendar.current
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now))!
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        return [
            ClubEvent(id: "e1", campusId: "hofstra", hostClubIds: ["drama"], title: "Open read-through: Act One",
                      start: at(0, 18, 30), durationMinutes: 90, location: "Studio 2 (demo room)",
                      details: "Read aloud together. No preparation needed.", organizer: "Ava R.", status: .scheduled),
            ClubEvent(id: "e3", campusId: "hofstra", hostClubIds: ["pottery"], title: "Wheel basics, no experience needed",
                      start: at(2, 17), durationMinutes: 90, location: "Art room (demo)",
                      details: "First time on the wheel? Perfect.", organizer: "Noor B.", status: .scheduled),
            ClubEvent(id: "e2", campusId: "hofstra", hostClubIds: ["rocket"],
                      title: "Paper-rocket build night and short safety briefing for first-timers",
                      start: at(3, 19), durationMinutes: 120, location: "Maker room (demo)",
                      details: "Build and launch small paper rockets.", organizer: "Dev S.", status: .rescheduled,
                      previousStart: at(1, 19)),
            ClubEvent(id: "e5", campusId: "hofstra", hostClubIds: ["drama", "pottery"], title: "Joint set-design workshop",
                      start: at(3, 17, 30), durationMinutes: 90, location: "Studio 2 (demo room)",
                      details: "One event, two host clubs. Each person counts once.", organizer: "Ava R. and Noor B.",
                      status: .scheduled),
            ClubEvent(id: "e4", campusId: "hofstra", hostClubIds: ["service"], title: "Pantry sorting shift",
                      start: at(4, 16), durationMinutes: 120, location: "Community pantry (demo)",
                      details: "Sort donations with a small team.", organizer: "Tess W.", status: .cancelled),
        ]
    }
}
