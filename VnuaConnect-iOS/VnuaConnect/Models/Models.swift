import Foundation

// Every campus-scoped record carries campusId so new schools can be added later without a migration.

struct Campus: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    /// School email domains allowed to sign in (e.g. "hofstra.edu" also matches "pride.hofstra.edu").
    var emailDomains: [String]

    static let hofstra = Campus(id: "hofstra", name: "Hofstra University", emailDomains: ["hofstra.edu"])

    func allows(email: String) -> Bool {
        guard let domain = email.lowercased().split(separator: "@").last.map(String.init) else { return false }
        return emailDomains.contains { domain == $0 || domain.hasSuffix("." + $0) }
    }
}

struct UserProfile: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var email: String
    var campusId: String
}

enum Recognition: String, Codable, Sendable {
    case recognized, notRecognized, notStated

    var label: String {
        switch self {
        case .recognized: return "Recognized"
        case .notRecognized: return "Not yet recognized"
        case .notStated: return "Status not stated"
        }
    }
}

struct Club: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var campusId: String
    var monogram: String
    var accentHex: String
    var name: String
    var interest: String
    var blurb: String
    var about: String
    var recognition: Recognition
    var funded: Bool?
    var affiliation: String?
    /// GIHU-style: officers approve join requests. When false, joining is instant.
    var requiresApproval: Bool
    var officers: [Officer]
}

struct Officer: Hashable, Codable, Sendable {
    var name: String
    var title: String
    var askAbout: String
}

enum MemberRole: String, Codable, Sendable, CaseIterable {
    case member, founding, officer
    var label: String {
        switch self {
        case .member: return "Member"
        case .founding: return "Founding member"
        case .officer: return "Officer"
        }
    }
}

enum MembershipStatus: String, Codable, Sendable { case pending, active }

enum ContactPreference: String, Codable, Sendable, CaseIterable, Identifiable {
    case none, events, organizing
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Don't email me"
        case .events: return "Event updates only"
        case .organizing: return "Events and organizing"
        }
    }
}

struct Membership: Hashable, Codable, Sendable {
    var clubId: String
    var role: MemberRole
    var status: MembershipStatus
    var contact: ContactPreference
}

enum EventStatus: String, Codable, Sendable { case scheduled, rescheduled, cancelled }

struct ClubEvent: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var campusId: String
    var hostClubIds: [String]
    var title: String
    var start: Date
    var durationMinutes: Int
    var location: String
    var details: String
    var organizer: String
    var status: EventStatus
    var previousStart: Date?

    var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
}

struct EventPass: Hashable, Sendable {
    var token: String
    var eventId: String
    var expiresAt: Date
}

enum CheckInSubject: Sendable {
    case pass(token: String)
    case member(id: String, name: String)
    case guest(name: String)
}

/// A person an officer can find with "Look up" (members of the host clubs and people who RSVP'd).
struct MemberSummary: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
}

struct JoinRequest: Identifiable, Hashable, Sendable {
    var id: String { userId }
    let userId: String
    var name: String
    var role: MemberRole
    var requestedAt: Date
}

enum CheckInStatus: String, Sendable { case recorded, duplicate }

struct CheckInResult: Sendable {
    var status: CheckInStatus
    var record: AttendanceRecord
}

struct AttendanceRecord: Identifiable, Hashable, Sendable {
    enum Mode: String, Sendable { case pass = "Pass", lookup = "Lookup", guest = "Guest" }
    let id: String
    var eventId: String
    var attendeeName: String
    var mode: Mode
    var recordedAt: Date
    var recordedBy: String
    /// Corrections never delete. The original row stays with a reason (audit trail).
    var removedReason: String?
}

enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case impersonation = "Pretending to be another group"
    case duplicate = "Duplicate of an existing club or event"
    case unsafe = "Inappropriate or unsafe content"
    case wrongStatus = "Status claim looks wrong"
    case other = "Something else"
    var id: String { rawValue }

    /// Value stored in the database enum `report_reason`.
    var dbValue: String {
        switch self {
        case .impersonation: return "impersonation"
        case .duplicate: return "duplicate"
        case .unsafe: return "unsafe"
        case .wrongStatus: return "wrong_status"
        case .other: return "other"
        }
    }
}

/// Mirrors the web contract: {ok:false, error:{code, message, retryable}}.
enum APIError: LocalizedError, Equatable, Sendable {
    case network
    case validation(String)
    case forbiddenRole
    case forbidden
    case lastAdmin
    case notFound

    var errorDescription: String? {
        switch self {
        case .network: return "No response from the server. Try again."
        case .validation(let m): return m
        case .forbiddenRole: return "You can't give yourself that role."
        case .forbidden: return "Only this club's officers can do that."
        case .lastAdmin: return "You're this club's administrator. Transfer leadership before leaving."
        case .notFound: return "That item no longer exists."
        }
    }

    var isRetryable: Bool { self == .network }
}
