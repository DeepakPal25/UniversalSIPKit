import Foundation

/// An immutable snapshot of a SIP call at a point in time.
public struct SIPCall: Sendable, Identifiable, Equatable {

    public let id: UUID
    public let accountID: UUID
    public let remoteNumber: String
    public let isIncoming: Bool
    public let state: SIPCallState
    public let isMuted: Bool
    public let isOnHold: Bool

    public init(
        id: UUID,
        accountID: UUID,
        remoteNumber: String,
        isIncoming: Bool,
        state: SIPCallState,
        isMuted: Bool = false,
        isOnHold: Bool = false
    ) {
        self.id = id
        self.accountID = accountID
        self.remoteNumber = remoteNumber
        self.isIncoming = isIncoming
        self.state = state
        self.isMuted = isMuted
        self.isOnHold = isOnHold
    }

    /// Returns a copy of the call with an updated state, preserving identity.
    public func with(
        state: SIPCallState? = nil,
        isMuted: Bool? = nil,
        isOnHold: Bool? = nil
    ) -> SIPCall {
        SIPCall(
            id: id,
            accountID: accountID,
            remoteNumber: remoteNumber,
            isIncoming: isIncoming,
            state: state ?? self.state,
            isMuted: isMuted ?? self.isMuted,
            isOnHold: isOnHold ?? self.isOnHold
        )
    }
}
