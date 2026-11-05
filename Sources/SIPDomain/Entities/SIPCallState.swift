import Foundation

/// The lifecycle state of a single SIP call.
public enum SIPCallState: String, Sendable, Equatable {
    case idle
    case incoming
    case connecting
    case ringing
    case connected
    case onHold
    case reconnecting
    case ended
    case failed

    /// Whether this is a terminal state from which no further transitions occur.
    public var isTerminal: Bool {
        self == .ended || self == .failed
    }
}
