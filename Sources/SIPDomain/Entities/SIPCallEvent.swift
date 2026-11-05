import Foundation

/// A typed event emitted by the SIP engine as registration and call state change.
///
/// Events are the single source of truth that higher layers observe. Terminal
/// call events (`callEnded`, `callFailed`) must not be followed by further
/// events for the same call identifier.
public enum SIPCallEvent: Sendable, Equatable {

    case registrationChanged(accountID: UUID, state: SIPRegistrationState)

    case incomingCall(SIPCall)

    case outgoingCallStarted(SIPCall)

    case callStateChanged(SIPCall)

    case callConnected(callID: UUID)

    case callEnded(callID: UUID)

    case callFailed(callID: UUID, error: SIPError)
}
