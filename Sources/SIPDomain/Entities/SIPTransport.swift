import Foundation

/// The network transport used for SIP signaling.
public enum SIPTransport: String, Sendable, Codable, CaseIterable {
    case udp
    case tcp
    case tls
}
