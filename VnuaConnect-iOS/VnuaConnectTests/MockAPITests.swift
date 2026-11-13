import XCTest
@testable import VnuaConnect

/// The rules the real server must also enforce. When SupabaseAPI exists, run these against it too.
final class MockAPITests: XCTestCase {
    private func signedIn() async throws -> MockAPI {
        let api = MockAPI()
        await api.setLatency(.zero)
        _ = try await api.verify(email: "alex@pride.hofstra.edu", name: "Alex Rivera", code: "123456", campus: .hofstra)
        return api
    }

    func testRejectsNonSchoolEmail() async {
        let api = MockAPI()
        await api.setLatency(.zero)
        do { try await api.requestCode(email: "alex@gmail.com", name: "Alex", campus: .hofstra); XCTFail("should reject") }
        catch { XCTAssertEqual(error as? APIError, .validation("Use your Hofstra University email address.")) }
    }

    func testAcceptsSubdomainEmail() {
        XCTAssertTrue(Campus.hofstra.allows(email: "a@pride.hofstra.edu"))
        XCTAssertFalse(Campus.hofstra.allows(email: "a@nothofstra.edu"))
    }

    func testCannotSelfAssignOfficer() async throws {
        let api = try await signedIn()
        do { _ = try await api.join(clubId: "law", role: .officer, contact: .events, requestId: "r1"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .forbiddenRole) }
    }

    func testApprovalClubCreatesPendingMembership() async throws {
        let api = try await signedIn()
        let m = try await api.join(clubId: "pottery", role: .member, contact: .events, requestId: "r2")
        XCTAssertEqual(m.status, .pending)
    }

    func testLastAdminCannotLeave() async throws {
        let api = try await signedIn()
        do { try await api.leave(clubId: "drama"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .lastAdmin) }
    }

    func testCheckInIsIdempotentAndUnique() async throws {
        let api = try await signedIn()
        let a = try await api.checkIn(eventId: "e1", subject: .member(id: "p_sam", name: "Sam T."), requestId: "same")
        let b = try await api.checkIn(eventId: "e1", subject: .member(id: "p_sam", name: "Sam T."), requestId: "same")
        XCTAssertEqual(a.record.id, b.record.id)
        let c = try await api.checkIn(eventId: "e1", subject: .member(id: "p_sam", name: "Sam T."), requestId: "different")
        XCTAssertEqual(c.status, .duplicate)
    }

    func testNonOfficerCannotCheckIn() async throws {
        let api = try await signedIn()   // member (not officer) of "rocket" → e2
        do { _ = try await api.checkIn(eventId: "e2", subject: .member(id: "p_sam", name: "X"), requestId: "r"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .forbidden) }
    }

    func testPassIsEventBound() async throws {
        let api = try await signedIn()
        let pass = try await api.issuePass(eventId: "e3")
        do { _ = try await api.checkIn(eventId: "e1", subject: .pass(token: pass.token), requestId: "r"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .validation("This pass is for a different event.")) }
    }

    func testCorrectionNeedsReasonAndKeepsOriginal() async throws {
        let api = try await signedIn()
        let res = try await api.checkIn(eventId: "e1", subject: .guest(name: "Leo"), requestId: "g")
        do { try await api.correct(recordId: res.record.id, reason: "  ", requestId: "c1"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .validation("A reason is required.")) }
        try await api.correct(recordId: res.record.id, reason: "Wrong person", requestId: "c2")
        let rows = try await api.attendance(eventId: "e1")
        XCTAssertEqual(rows.first { $0.id == res.record.id }?.removedReason, "Wrong person")
    }

    func testNetworkFailureIsNotCached() async throws {
        let api = try await signedIn()
        await api.setFailNext(true)
        do { _ = try await api.setRSVP(eventId: "e1", going: true, requestId: "x"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .network) }
        let ok = try await api.setRSVP(eventId: "e1", going: true, requestId: "x")
        XCTAssertTrue(ok)
    }

    func testCannotRSVPToCancelledEvent() async throws {
        let api = try await signedIn()
        do { _ = try await api.setRSVP(eventId: "e4", going: true, requestId: "r"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .validation("This event was cancelled.")) }
    }

    func testOfficerReviewsJoinRequests() async throws {
        let api = try await signedIn()   // officer of drama, which has a seeded request
        let reqs = try await api.joinRequests(clubId: "drama")
        XCTAssertEqual(reqs.map(\.name), ["Sam T."])
        try await api.reviewJoinRequest(clubId: "drama", userId: "p_sam", approve: true)
        let after = try await api.joinRequests(clubId: "drama")
        XCTAssertTrue(after.isEmpty)
        do { _ = try await api.joinRequests(clubId: "rocket"); XCTFail() }    // member, not officer
        catch { XCTAssertEqual(error as? APIError, .forbidden) }
    }

    func testBlockedClubCannotBeJoined() async throws {
        let api = try await signedIn()
        try await api.setBlocked(clubId: "law", blocked: true)
        let blocked = try await api.blockedClubs()
        XCTAssertEqual(blocked, ["law"])
        do { _ = try await api.join(clubId: "law", role: .member, contact: .events, requestId: "b"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .validation("Unblock this club before joining.")) }
    }

    func testOfficerSearchFindsMembers() async throws {
        let api = try await signedIn()
        let found = try await api.searchAttendees(eventId: "e1", query: "pri")
        XCTAssertEqual(found.map(\.name), ["Priya N."])
    }

    func testServerErrorMapping() {
        XCTAssertEqual(SupabaseAPI.map("forbidden|Only officers"), .forbidden)
        XCTAssertEqual(SupabaseAPI.map("last_admin|x"), .lastAdmin)
        XCTAssertEqual(SupabaseAPI.map("forbidden_role|x"), .forbiddenRole)
        XCTAssertEqual(SupabaseAPI.map("validation|A reason is required."), .validation("A reason is required."))
        XCTAssertEqual(SupabaseAPI.map("something unexpected"), .validation("something unexpected"))
    }
}
