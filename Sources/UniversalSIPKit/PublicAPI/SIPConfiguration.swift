import Foundation
import SIPDomain

/// Server-level configuration shared by all accounts registered with the SDK.
public struct SIPConfiguration: Sendable {

    public let server: String
    public let domain: String
    public let port: Int
    public let transport: SIPTransport

    public init(
        server: String,
        domain: String,
        port: Int = 5060,
        transport: SIPTransport = .udp
    ) {
        self.server = server
        self.domain = domain
        self.port = port
        self.transport = transport
    }
}
