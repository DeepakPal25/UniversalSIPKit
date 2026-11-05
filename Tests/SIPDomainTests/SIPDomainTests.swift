import XCTest
@testable import SIPDomain

final class SIPDomainTests: XCTestCase {

    // MARK: - Account validation

    func testValidAccountPasses() throws {
        let account = SIPAccount(username: "1001", domain: "example.com", port: 5060, transport: .udp)
        XCTAssertNoThrow(try SIPAccountValidator.validate(account))
    }

    func testEmptyUsernameFails() {
        let account = SIPAccount(username: " ", domain: "example.com")
        XCTAssertThrowsError(try SIPAccountValidator.validate(account)) { error in
            XCTAssertEqual(error as? SIPError, .invalidConfiguration)
        }
    }

    func testDomainWithoutDotFails() {
        let account = SIPAccount(username: "1001", domain: "localhost")
        XCTAssertThrowsError(try SIPAccountValidator.validate(account)) { error in
            XCTAssertEqual(error as? SIPError, .invalidConfiguration)
        }
    }

    func testInvalidPortFails() {
        let account = SIPAccount(username: "1001", domain: "example.com", port: 70000)
        XCTAssertThrowsError(try SIPAccountValidator.validate(account))
    }

    // MARK: - Account URI

    func testURIUsesSipsForTLS() {
        let account = SIPAccount(username: "1001", domain: "example.com", transport: .tls)
        XCTAssertEqual(account.uri, "sips:1001@example.com")
    }

    func testURIUsesSipOtherwise() {
        let account = SIPAccount(username: "1001", domain: "example.com", transport: .udp)
        XCTAssertEqual(account.uri, "sip:1001@example.com")
    }

    // MARK: - Call state

    func testTerminalStates() {
        XCTAssertTrue(SIPCallState.ended.isTerminal)
        XCTAssertTrue(SIPCallState.failed.isTerminal)
        XCTAssertFalse(SIPCallState.connected.isTerminal)
        XCTAssertFalse(SIPCallState.incoming.isTerminal)
    }

    func testCallWithPreservesIdentity() {
        let id = UUID()
        let accountID = UUID()
        let call = SIPCall(id: id, accountID: accountID, remoteNumber: "1002", isIncoming: false, state: .connecting)
        let updated = call.with(state: .connected, isMuted: true)
        XCTAssertEqual(updated.id, id)
        XCTAssertEqual(updated.accountID, accountID)
        XCTAssertEqual(updated.state, .connected)
        XCTAssertTrue(updated.isMuted)
        XCTAssertFalse(updated.isOnHold)
    }

    // MARK: - Credentials redaction

    func testCredentialsRedactPassword() {
        let credentials = SIPCredentials(authName: "1001", password: "s3cret")
        XCTAssertFalse("\(credentials)".contains("s3cret"))
        XCTAssertTrue("\(credentials)".contains("redacted"))
    }
}
