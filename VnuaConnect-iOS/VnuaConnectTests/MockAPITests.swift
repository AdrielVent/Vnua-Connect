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
        do { try await api.requestCode(email: "alex@gmail.com", campus: .hofstra); XCTFail("should reject") }
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
        let a = try await api.checkIn(eventId: "e1", subject: .member(name: "Sam T."), requestId: "same")
        let b = try await api.checkIn(eventId: "e1", subject: .member(name: "Sam T."), requestId: "same")
        XCTAssertEqual(a.record.id, b.record.id)
        let c = try await api.checkIn(eventId: "e1", subject: .member(name: "Sam T."), requestId: "different")
        XCTAssertEqual(c.status, .duplicate)
    }

    func testNonOfficerCannotCheckIn() async throws {
        let api = try await signedIn()   // member (not officer) of "rocket" → e2
        do { _ = try await api.checkIn(eventId: "e2", subject: .member(name: "X"), requestId: "r"); XCTFail() }
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
}
