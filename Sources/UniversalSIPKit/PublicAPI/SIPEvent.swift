import SIPDomain

// Re-export the Domain-level event and model types so host applications only
// need to `import UniversalSIPKit`.

/// The public event type observed by host applications. Alias of the Domain
/// ``SIPCallEvent`` so the public surface stays stable even if internals change.
public typealias SIPEvent = SIPCallEvent
