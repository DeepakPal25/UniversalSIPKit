# UniversalSIPKit — Technical Reference

A deep, implementation-level description of how UniversalSIPKit works: the
problem it solves, the theory behind each layer, every runtime flow, the
concurrency and event contracts, the security model, and the full catalogue of
edge cases and known limitations.

> Audience: contributors and integrators who need the "why", not just the "how".
> For a quick start see [`README.md`](../README.md); for the engine decision see
> [`ENGINE-EVALUATION.md`](ENGINE-EVALUATION.md); for the Baresip bring-up see
> [`BARESIP-POC.md`](BARESIP-POC.md).

---

## 1. The problem

Adding voice calling to an iOS app is deceptively large. A team that wants "let
users call each other" must independently build and maintain:

- SIP registration + digest authentication, or a vendor SDK's auth/token flow.
- SIP signaling (INVITE/ACK/BYE/CANCEL) or the vendor's proprietary signaling.
- RTP/SRTP media and codec negotiation.
- **CallKit** so calls use the native incoming-call UI and the system call log.
- **PushKit + APNs VoIP** so calls ring when the app is backgrounded/suspended.
- **AVAudioSession** lifecycle, including Bluetooth/AirPods routing and the
  delicate hand-off with CallKit.
- Secure credential storage (Keychain).
- Call/registration state machines, network recovery, multi-account support.

Two structural problems make this worse:

1. **Engine lock-in.** Almost every iOS SIP library (PJSIP, Linphone, Baresip
   wrappers) couples your app to one C stack *and* often to a copyleft/commercial
   license. Swapping engines means rewriting your call code.
2. **SIP ≠ "calling".** Cloud voice vendors (Twilio, Vonage, Agora) are not SIP
   from the app's perspective — they use access tokens and proprietary
   signaling. SIP-shaped SDKs can't model them at all.

**What UniversalSIPKit solves:** it owns the hard iOS calling fabric once, behind
a small stable Swift API, and makes the *engine* a replaceable detail — SIP
engines and non-SIP vendors are interchangeable. The host app keeps its UX and
business logic; the SDK keeps the plumbing.

The product thesis in one line:

> **One SDK API + multiple providers + replaceable engines + reusable iOS calling infrastructure.**

---

## 2. Theoretical foundations

The codebase is a fairly literal application of several well-known ideas. Each is
chosen for a concrete payoff, not decoration.

### 2.1 Clean Architecture & the Dependency Rule
Source code dependencies point **inward only**. The innermost layer (Domain)
knows nothing about SIP, CallKit, PJSIP, or Foundation networking. Outer layers
depend on inner ones, never the reverse. Payoff: the business rules (call state,
validation, use cases) are testable in isolation and survive any engine or OS
change. Enforced physically by the SPM target graph (§3).

### 2.2 Ports & Adapters (Hexagonal Architecture)
The Domain defines **ports** (protocols): `VoiceProviderProtocol`,
`AccountRepositoryProtocol`, `CredentialStoreProtocol`, `CallRepositoryProtocol`.
The Infrastructure/Data layers provide **adapters** that implement them. The
application core talks only to ports, so any adapter (a SIP engine, a vendor
SDK, an in-memory fake, a Keychain, a mock) plugs into the same socket.

### 2.3 Dependency Inversion & the Composition Root
High-level policy (use cases) does not construct low-level details. Everything is
wired in exactly one place — `SIPDependencyContainer` (the composition root).
This is constructor injection end-to-end; there are no service-locator
singletons inside the layers. (`UniversalSIPKit.shared` is a *convenience* entry
point, not an internal dependency.)

### 2.4 Strategy pattern for engines
`VoiceProviderProtocol` is a strategy. `InMemoryVoiceProvider`, `BaresipEngine`,
`PJSIPAdapter`, and `TwilioVoiceProvider` are interchangeable strategies selected
at composition time. Swapping them requires zero changes above the Infrastructure
layer.

### 2.5 The actor model & structured concurrency
Engine state (registrations, calls, C handles) is mutable shared state accessed
from multiple contexts (app calls, network/C callbacks). Rather than locks, each
stateful component is a Swift **actor**, giving data-race-free serialized access
checked by the compiler under Swift 6 strict concurrency. Values that cross
isolation boundaries are `Sendable` by construction (see §7).

### 2.6 Value semantics & immutability
Domain entities (`SIPCall`, `SIPAccount`, `VoiceAccount`, events) are immutable
`struct`s. State transitions produce new values (`SIPCall.with(...)`) rather than
mutating in place. This makes events safe to broadcast to many observers and
eliminates aliasing bugs.

### 2.7 Reactive state via async sequences
Call/registration changes are modeled as a stream of immutable events
(`AsyncStream<SIPCallEvent>`), not callbacks or Combine. This is a pull-based,
back-pressure-aware, cancellation-aware reactive model native to Swift
concurrency (§6).

---

## 3. Module topology & the dependency graph

Four source targets plus the C bridge, mirroring the layers:

```
            ┌────────────────────────────────────────────┐
            │            UniversalSIPKit (public)         │   facade + DI (composition root)
            │   UniversalSIPKit.swift, SIPConfiguration,  │
            │   SIPAccountConfiguration, SIPDependency…   │
            └───────────────┬───────────────┬─────────────┘
                            │               │
                 depends on │               │ depends on
                            ▼               ▼
                   ┌────────────┐   ┌────────────────────────────┐
                   │  SIPData   │   │      SIPInfrastructure      │
                   │ repository │   │ providers (InMemory/Baresip │
                   │ impls      │   │ /PJSIP/Twilio), CallKit,    │
                   │            │   │ PushKit, Audio, Keychain,   │
                   │            │   │ Logging, EventBroadcaster   │
                   └──────┬─────┘   └──────┬──────────────┬───────┘
                          │                │              │
                          ▼                ▼              ▼
                   ┌──────────────────────────┐   ┌───────────────┐
                   │        SIPDomain         │   │ BaresipBridge │  (C target; libre/baresip)
                   │ entities, use cases,     │   │  stub until    │
                   │ ports (protocols),       │   │  XCFramework   │
                   │ errors — NO deps         │   │  is linked     │
                   └──────────────────────────┘   └───────────────┘
```

Rules the graph enforces (`Package.swift`):

- `SIPDomain` has **no** dependencies (not even on Infrastructure types).
- `SIPData` → `SIPDomain` only.
- `SIPInfrastructure` → `SIPDomain` + `BaresipBridge`.
- `UniversalSIPKit` → all of the above; it is the only place concrete types meet.
- Nothing depends on `UniversalSIPKit` except the host app.

Because the arrows only point down/inward, a violation (e.g. Domain importing
CallKit) fails to compile — the architecture is machine-checked, not a
convention.

---

## 4. The core abstraction (why it is provider-neutral)

Three Domain types make "universal" real:

### `VoiceProviderProtocol` (the port)
```swift
protocol VoiceProviderProtocol: Sendable {
    var providerID: String { get }
    func initialize() async throws
    func shutdown() async throws
    func events() async -> AsyncStream<SIPCallEvent>
    func register(account: VoiceAccount, credential: ProviderCredential) async throws
    func unregister(accountID: UUID) async throws
    func makeCall(accountID: UUID, destination: String) async throws -> SIPCall
    func answerCall(callID: UUID) async throws
    func rejectCall(callID: UUID) async throws
    func endCall(callID: UUID) async throws
    func setMuted(callID: UUID, muted: Bool) async throws
    func setHeld(callID: UUID, held: Bool) async throws
    func currentCalls() async -> [SIPCall]
}
```
The call verbs are universal across SIP and vendors. Only `register`/`unregister`
differ in meaning: a SIP REGISTER vs. "prepare this identity / register push
credentials" for a token vendor. `SIPEngineProtocol` is kept as a type-alias for
continuity.

### `VoiceAccount`
```swift
struct VoiceAccount { let id: UUID; let providerID: String; let identity: String; let settings: [String:String] }
```
SIP specifics (domain/port/transport) live in `settings` instead of being baked
into the type, so a Twilio account (identity + region) fits the same shape. A
`SIPAccount` projects into it via `asVoiceAccount(providerID:)`.

### `ProviderCredential`
```swift
enum ProviderCredential: Sendable, Equatable, Codable {
    case sip(SIPCredentials)      // digest auth
    case accessToken(String)      // Twilio/Vonage/Agora
    case custom([String:String])  // anything else
}
```
`Codable` so it can be persisted uniformly; `description` is **redacted** so
secrets never print. `isEmpty` drives credential validation.

This triplet is the entire reason the SDK is not SIP-locked: the boundary speaks
in provider-neutral nouns, and each engine interprets them.

---

## 5. Layer-by-layer deep dive

### 5.1 Domain (`SIPDomain`)

**Entities.**
- `SIPAccount` — public SIP metadata (never holds a password). Computes a `uri`
  (`sips:` when transport is TLS, else `sip:`).
- `SIPCredentials` — `authName`/`password`/`realm`; `Codable`; redacts password in
  `description`/`debugDescription`.
- `SIPCall` — immutable snapshot: `id`, `accountID`, `remoteNumber`, `isIncoming`,
  `state`, `isMuted`, `isOnHold`. `with(...)` returns a mutated copy preserving
  identity.
- `SIPCallState` — `idle, incoming, connecting, ringing, connected, onHold,
  reconnecting, ended, failed`; `isTerminal` is true for `ended`/`failed`.
- `SIPRegistrationState` — `unregistered, registering, registered, failed(reason)`.
- `VoiceAccount`, `ProviderCredential` — §4.

**The call state machine (theoretical model).** A call is a finite-state machine.
Legal transitions:
```
            ┌────────── makeCall ──────────┐
 idle ──────┤                              ▼
            └── incoming ──► (answer) ──► connecting ─► ringing ─► connected ──► ended
                    │                                      │           │ ▲         ▲
                 (reject)                               (progress)  (hold)│(resume) │
                    ▼                                                └────┘ onHold ─┘
                  ended                        any state ── error ──► failed ──► (terminal)
```
`ended` and `failed` are **absorbing** states: once entered, no further events for
that call id are valid (enforced by the event contract, §6).

**Errors.** `SIPError` is a flat, `Equatable`, `Sendable` enum with a
`LocalizedError` description, e.g. `invalidConfiguration`, `invalidCredentials`,
`registrationFailed/Timeout`, `accountNotRegistered/NotFound`,
`invalidDestination`, `callFailed/NotFound`, `networkUnavailable`,
`authenticationFailed`, `audioSessionFailed`, `pushRegistrationFailed`,
`unsupportedOperation`, `notInitialized`, `internalError`. Engine-specific codes
(PJSIP/baresip status, Twilio errors) are mapped **into** these so the public
surface never leaks engine internals.

**Use cases.** One type per business operation, each a tiny `Sendable` struct with
`callAsFunction` (so they read like functions): `InitializeSIPUseCase`,
`RegisterAccountUseCase`, `UnregisterAccountUseCase`, `MakeCallUseCase`,
`AnswerCallUseCase`, `RejectCallUseCase`, `EndCallUseCase`, `HoldCallUseCase`,
`MuteCallUseCase`, `ObserveCallEventsUseCase`. They coordinate *ports*, holding
no engine knowledge. Business validation lives here:
- `RegisterAccountUseCase` rejects empty identity (`invalidConfiguration`) and
  empty credentials (`invalidCredentials`) before touching the repository.
- `MakeCallUseCase` trims the destination and rejects empty (`invalidDestination`).

**Validation.** `SIPAccountValidator.validate` is a pure function: non-empty
username, a domain containing a dot, port in `1...65535`; throws
`invalidConfiguration` otherwise.

### 5.2 Data (`SIPData`)

**`AccountRepositoryImpl`** (an actor) coordinates persistence + registration and
is where the **transactional rollback** rule lives:
```
save(credential)               // 1. persist secret first
try register(account, …)       // 2. ask the provider to register
  └─ on failure: delete(credential); rethrow   // 3. roll back so no orphan secret
accounts[id] = account         // 4. only record on success
```
This guarantees the store never retains a secret for an account that failed to
register. `removeAccount` throws `accountNotFound` for unknown ids, otherwise
unregisters then best-effort deletes the credential.

**`CallRepositoryImpl`** is a thin, stateless projection over the provider:
`observeCallEvents()` → `provider.events()`, `currentCalls()` →
`provider.currentCalls()`. It exists so use cases depend on a Domain port, not on
an Infrastructure type.

### 5.3 Infrastructure (`SIPInfrastructure`)

**Providers (strategies).**
- `InMemoryVoiceProvider` (actor) — a fully working *simulator*. No real
  signaling/media. It is the reference implementation of the event contract and
  powers tests/demos. Configurable `providerID` lets one instance stand in for a
  SIP or a vendor provider. Simulated sequences:
  - `register`: emits `registrationChanged(.registering)` → `(.registered)`.
  - `makeCall`: emits `outgoingCallStarted`, transitions ringing→connected
    internally, then emits `callStateChanged(.connected)` + `callConnected`
    (3 events).
  - `simulateIncomingCall(...)`: emits `incomingCall` for tests.
- `BaresipEngine` / `BaresipAdapter` (actor) — SIP via libre/baresip through the C
  bridge. Full Swift control flow exists; the native body is pending the
  XCFramework. Maps `usk_baresip_status` → `SIPError`. Provides `startAudio`/
  `stopAudio` for the CallKit hand-off.
- `PJSIPAdapter` (actor) — SIP fallback skeleton (GPL/commercial engine).
- `TwilioVoiceProvider` (actor) — non-SIP skeleton; requires
  `ProviderCredential.accessToken`, otherwise throws `invalidCredentials`.

**`EventBroadcaster`** (actor) — multiplexes one event source to N independent
subscribers. Each `subscribe()` builds an `AsyncStream` and registers its
continuation (keyed by a `UUID`) synchronously inside the stream's builder
closure; `onTermination` removes it. `emit` fans out to all continuations in
registration order; `finishAll` ends every stream on shutdown. Default buffering
is unbounded (see §6 for the ordering/back-pressure implications).

**The C bridge (`BaresipBridge`).** A deliberately tiny, stable C surface
(`usk_baresip_*`) that never exposes libre/baresip types. `BaresipBridge.m`
compiles in two modes via `#if __has_include(<baresip.h>) && __has_include(<re.h>)`:
real calls when the XCFramework is linked, otherwise a stub returning
`USK_BARESIP_ENOTAVAIL`. `usk_baresip_is_available()` reports which. This is why
the whole package builds today with no native SIP library.

**The callback boundary (C → Swift).** baresip calls back on its own thread
through a non-capturing `@convention(c)` **trampoline** in `BaresipEngine.swift`.
The trampoline reconstructs the `BaresipEventBridge` from an opaque `void*`
context (`Unmanaged.passUnretained`), copies the C strings into Swift `String`s,
and dispatches onto the bridge actor via `Task`. `BaresipEventBridge` (actor)
owns the engine-string-id ⇄ `UUID` mapping and translates coarse C event codes
into `SIPCallEvent`s, emitting through its `EventBroadcaster`.

**iOS adapters** (all guarded by `#if os(iOS)`/`canImport`, so macOS/CI builds
exclude them):
- `CallKitManager` — configures `CXProvider`, reports incoming/outgoing calls,
  and forwards `CXAction`s. It takes a `CallKitActions` struct of `@Sendable`
  closures so it stays decoupled from the engine. Delegate methods capture only
  `Sendable` values and `fulfill()` synchronously (avoids passing non-`Sendable`
  `CXAction`s across isolation).
- `VoIPPushManager` — PushKit registration + incoming VoIP pushes. Exposes
  `onTokenUpdate` (forward to your gateway) and `onIncomingPush` (report a call to
  CallKit, then complete). A `CompletionBox` wraps PushKit's non-`Sendable`
  completion so it can be invoked from the `@Sendable` handler.
- `AudioSessionManager` — configures `AVAudioSession` for VoIP
  (`.playAndRecord`/`.voiceChat`, Bluetooth options) and exposes
  `activate`/`deactivate`/`setSpeakerEnabled`. It is designed to *follow* CallKit,
  not fight it (§8).
- `SIPLogger` — `OSLog` wrapper with categories; callers must never pass secrets.

**Security (`SIPInfrastructure/Security`).**
- `KeychainCredentialStore` (actor) — JSON-encodes `ProviderCredential` into a
  Keychain generic-password item keyed by account id, protected with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (available to background VoIP
  pushes, never migrates off device).
- `InMemoryCredentialStore` (actor) — process-memory only; tests/previews.

### 5.4 Public API + Composition Root (`UniversalSIPKit`)

**`SIPDependencyContainer`** — the composition root. Its initializer takes a
`VoiceProviderProtocol` + `CredentialStoreProtocol`, constructs the repositories,
and vends configured use cases (`makeRegisterUseCase()`, `makeMakeCallUseCase()`,
…). `inMemory()` is the zero-config factory used by default. To ship a real
engine you build a container with `BaresipEngine()` (+ `KeychainCredentialStore`)
or `TwilioVoiceProvider()`.

**`UniversalSIPKit`** — the facade, an `actor` holding a small state machine:
- State: `container`, optional `configuration`, `pendingAccounts`
  (added-not-yet-registered), `registeredAccounts`, `isInitialized`.
- Lifecycle: `initialize()` (idempotent) runs `InitializeSIPUseCase`;
  `configure(configuration:)` stores SIP defaults then initializes;
  `useContainer(_:)` swaps the container **only before** init (else
  `unsupportedOperation`).
- Accounts: `addAccount(SIPAccountConfiguration)` (validates, builds a
  `.sip` `VoiceAccount`+credential, queues it — requires prior `configure`);
  `addAccount(VoiceAccount, credential:)` (generic path, queues any provider);
  `removeAccount(id:)` (drops from pending and unregisters if registered).
- Connection: `connect()` registers every pending account and promotes it to
  registered; `disconnect()` unregisters all registered accounts.
- Calls: `call(to:)`, `call(to:from:)`, `answer`, `reject`, `endCall`,
  `setMuted(_:callID:)`, `setHeld(_:callID:)`, `currentCalls()`.
- Events: `observeEvents()` returns a fresh `AsyncStream<SIPEvent>` each call.

`SIPConfiguration` (server/domain/port/transport) and
`SIPAccountConfiguration` (username/password/authName) are the SIP-ergonomic
inputs; `@_exported import SIPDomain` re-exports the Domain types so hosts only
`import UniversalSIPKit`.

---

## 6. The event model & its contract

Events are the single source of truth higher layers observe.

`SIPCallEvent` (aliased publicly as `SIPEvent`):
`registrationChanged(accountID,state)`, `incomingCall(SIPCall)`,
`outgoingCallStarted(SIPCall)`, `callStateChanged(SIPCall)`,
`callConnected(callID)`, `callEnded(callID)`, `callFailed(callID,error)`.

**Contract a conforming provider must honor:**
1. **No events after a terminal event** (`callEnded`/`callFailed`) for the same
   call id.
2. **Sensible ordering** per call: start → ringing/progress → connected → ended.
3. **Independent subscribers**: each `observeEvents()` yields its own stream;
   all active streams receive the same events in the same order.

**Buffering & the subscribe-before-act rule.** `AsyncStream` here uses the
default **unbounded** buffer, and `subscribe()` registers the continuation
*synchronously*. Therefore events emitted *after* `observeEvents()` returns are
retained even if you haven't started `for await` yet. But events emitted *before*
you subscribe are lost. Practical rule: **subscribe before `connect()`/`call()`**
if you need the registration/first-call events. (The tests follow this.)

**Ordering caveat for the native engine.** Within `BaresipEventBridge.handle`,
emits are awaited sequentially, so a single event's sub-emissions are ordered.
However, the C trampoline dispatches *each* callback via a separate `Task`, and
the order in which independent `Task`s are scheduled is **not guaranteed**. If
baresip fires two callbacks in extremely quick succession, their resulting events
could, in principle, be reordered. The `InMemoryVoiceProvider` has no such gap
(it awaits emits inline). This is a known limitation to harden during the PoC
(e.g. a single serial processing task). See §11.

---

## 7. Concurrency model

- **Every stateful component is an actor**: providers, `EventBroadcaster`,
  `BaresipEventBridge`, credential stores, the `UniversalSIPKit` facade,
  `AccountRepositoryImpl`. Mutable state is therefore race-free by construction
  under Swift 6 strict concurrency.
- **`Sendable` boundary**: all values crossing isolation (entities, events,
  errors, configs) are `Sendable` value types. `CallKitManager`/`VoIPPushManager`
  are `NSObject` delegates marked `@unchecked Sendable` with the unsafety confined
  to CallKit/PushKit's own queues.
- **C interop**: the `@convention(c)` trampoline cannot capture context, so it
  uses the classic `void*` + `Unmanaged` pattern; it copies all C strings into
  `Sendable` Swift values *before* entering the `Task`, so nothing non-`Sendable`
  escapes.
- **No Combine, no locks, no GCD queues in the core** — only actors and
  async/await, per the project's concurrency guideline.

---

## 8. CallKit & audio — the critical integration

CallKit owns `AVAudioSession` activation. The engine must **never**
activate/deactivate the session itself; it only configures the category up front
and starts/stops its audio *streams* in response to CallKit callbacks. The
intended wiring:

```
Outgoing:
  app.call(to:)               → CallKit CXStartCallAction → engine.makeCall(...)
  CXProvider didActivate audio → engine.startAudio(callID:)   // streams begin
  app.endCall / remote BYE     → engine.endCall(...)
  CXProvider didDeactivate     → engine.stopAudio(callID:)

Incoming:
  VoIP push / INVITE           → SIPCallEvent.incomingCall → report to CallKit
  user answers (CXAnswerCall)  → engine.answerCall(...)
  CXProvider didActivate audio → engine.startAudio(callID:)
```

`AudioSessionManager.configureForCall()` sets `.playAndRecord`/`.voiceChat` with
Bluetooth options *before* the call is reported; CallKit then performs the actual
activation and fires `didActivate`. This hand-off is the single biggest unproven
risk for the Baresip engine and is the explicit pass/fail gate of the PoC.

---

## 9. End-to-end flows

### 9.1 Initialization
`configure(config)` → facade stores config → `InitializeSIPUseCase` →
`provider.initialize()`. On the stub Baresip engine this throws
`unsupportedOperation`; with `InMemoryVoiceProvider` it succeeds. `isInitialized`
guards all later operations (`notInitialized` otherwise).

### 9.2 Registration
`addAccount(SIPAccountConfiguration)` validates and queues → `connect()` →
`RegisterAccountUseCase` → `AccountRepositoryImpl.addAccount` (persist→register→
rollback-on-failure) → `provider.register` → emits `registrationChanged`
(`.registering`→`.registered`). Account moves pending → registered.

### 9.3 Outgoing call
`call(to:)` picks a registered account → `MakeCallUseCase` (validates
destination) → `provider.makeCall` → `outgoingCallStarted` →
(ringing/progress) → `callStateChanged(.connected)` + `callConnected`. With a real
engine, CallKit's `didActivate` triggers `startAudio`.

### 9.4 Incoming call (foreground)
Engine receives INVITE → `incomingCall(SIPCall)` → host reports it to CallKit →
user answers → `answer(callID:)` → `connected` + `callConnected` → `startAudio`.

### 9.5 Incoming call (backgrounded/suspended)
SIP server/gateway → APNs VoIP → PushKit wakes the app → `VoIPPushManager`
`onIncomingPush` → the SDK reports a call to CallKit **promptly** (required by
iOS) → on answer, engine establishes the session. PushKit is intentionally
independent of SIP registration.

### 9.6 Mute / hold
`setMuted(_:callID:)`/`setHeld(_:callID:)` → use case → `provider.setMuted/
setHeld` → `callStateChanged` with updated `isMuted`/`isOnHold`/`state(.onHold)`.

### 9.7 Teardown
`endCall(callID:)` → `callEnded`; `disconnect()` unregisters all;
`provider.shutdown()` ends calls, clears state, and `finishAll()`s event streams.

### 9.8 Non-SIP (Twilio) — identical shape
`initialize()` → `addAccount(VoiceAccount(providerID:"twilio",…), .accessToken(t))`
→ `connect()` (registers push creds / prepares) → `call(to:)`. The public API and
event stream are byte-for-byte the same as SIP; only the injected provider
differs. This is exercised by `testNonSIPProviderAccountFlow`.

---

## 10. Edge cases — the "if / but" matrix

| Situation | Behaviour |
|---|---|
| `addAccount(SIPAccountConfiguration)` before `configure` | throws `invalidConfiguration` (no server defaults yet) |
| `configure` not called, generic `addAccount(VoiceAccount,…)` used | allowed — the generic path doesn't need `SIPConfiguration`; call `initialize()` first |
| Any call/register before `initialize` | `notInitialized` |
| `connect()` with no pending accounts | no-op (loop over empty set) |
| Registration fails after credential saved | credential **rolled back**, error rethrown, account not recorded |
| `removeAccount(id:)` for unknown id | if also not pending, repository throws `accountNotFound` |
| `removeAccount` for pending-but-not-registered | removed from pending; no unregister call |
| `call(to:)` with **multiple** registered accounts | uses `registeredAccounts.keys.first`, which is **nondeterministic** (dictionary order). Use `call(to:from:)` to be explicit. *(Known limitation.)* |
| `call(to:)` with zero registered accounts | `accountNotRegistered` |
| Empty/whitespace destination | `invalidDestination` |
| Empty password / empty token | `invalidCredentials` (via `ProviderCredential.isEmpty`) |
| Invalid SIP account (no dot in domain, bad port) | `invalidConfiguration` from `SIPAccountValidator` |
| `answer` on an outgoing call (InMemory) | `unsupportedOperation` (only incoming can be answered) |
| Operation on unknown `callID` | `callNotFound` |
| Baresip engine with no XCFramework linked | every op → `unsupportedOperation`; `isEngineAvailable == false` → fall back to another provider |
| `TwilioVoiceProvider.register` with a `.sip` credential | `invalidCredentials` (vendor needs a token) |
| Subscribe to events **after** `connect()`/`call()` | earlier events missed (buffer only retains post-subscribe events) |
| Many subscribers | each gets an independent, identically-ordered stream |
| Subscriber stops iterating | `onTermination` removes its continuation; `emit` simply skips it |
| Two baresip callbacks in rapid succession | possible reordering because each is dispatched as a separate `Task` *(known limitation, §6/§11)* |
| `useContainer` after `initialize` | `unsupportedOperation` |
| Keychain access while device locked (pre-first-unlock) | item unavailable by design; after first unlock it is available to VoIP pushes |
| App force-quit by the **user** | iOS gives no guarantee of VoIP-push relaunch; must be tested & documented, not assumed |
| macOS / CI build | CallKit/PushKit/Audio adapters are compiled out via `#if os(iOS)`; Domain/Data/engines still build & test |
| Vendor access token expires | no built-in refresh hook yet — host must re-add with a fresh token *(known limitation)* |
| `SIPConfiguration.server` (outbound proxy) | stored but not yet threaded into the account AOR (which uses `domain`) *(known limitation)* |

---

## 11. Known limitations (honest list)

1. **No real signaling/media yet.** Only `InMemoryVoiceProvider` is functional;
   Baresip/PJSIP/Twilio are skeletons. The native `BaresipBridge.m` body and the
   on-device CallKit audio gate are the PoC's remaining work.
2. **Native event ordering** could reorder under rapid back-to-back baresip
   callbacks (separate `Task`s). Fix: funnel callbacks through a single serial
   task/continuation in `BaresipEventBridge`.
3. **Multi-account outgoing selection** via `call(to:)` is nondeterministic; use
   `call(to:from:)`.
4. **Token lifecycle** for vendors lacks a refresh/`tokenProvider` hook.
5. **Outbound proxy** (`server`) and advanced SIP knobs aren't wired through.
6. **Network recovery / reconnection** (`reconnecting` state) is modeled but not
   yet driven.
7. **One active call** is the v1 assumption (multiple registered accounts, single
   active call).
8. **No LICENSE yet** — permissive license pending the dependency audit.

---

## 12. Extending the SDK — add a new provider

1. Create an actor in `SIPInfrastructure` conforming to `VoiceProviderProtocol`
   (copy `TwilioVoiceProvider` as a template). Give it a unique `providerID`.
2. Translate the vendor/engine callbacks into `SIPCallEvent`s via an
   `EventBroadcaster` (and an id-mapping actor if ids differ from `UUID`).
3. Map vendor error codes into `SIPError`.
4. Interpret `VoiceAccount.settings` + the expected `ProviderCredential` case.
5. Wire it in a `SIPDependencyContainer(provider:credentialStore:)`.

**Nothing in Domain, Data, use cases, or the public API changes.** That
invariant — the entire point of the port — is what makes the engine replaceable.

---

## 13. Testing

- **SIPDomainTests** — validation (username/domain/port), `uri` scheme selection,
  terminal-state logic, `SIPCall.with` identity preservation, credential
  redaction.
- **SIPDataTests** — credential persistence, the **rollback** path (a
  `FailingProvider` forces a registration failure and asserts the credential is
  gone), `accountNotFound`.
- **UniversalSIPKitTests** — full outgoing flow and its event sequence,
  `accountNotRegistered` guard, incoming-call surfacing + answer, and the
  **non-SIP (Twilio-style)** flow through the generic account path.

Run: `swift test` (16 tests). Event collection uses a timeout-guarded task group
so tests never hang. CI should also run the iOS build
(`xcodebuild -scheme UniversalSIPKit -destination 'generic/platform=iOS' build`)
to type-check the iOS-only adapters and the C bridge.

---

## 14. Glossary

- **AOR** — Address of Record, `sip:user@domain`.
- **Port / Adapter** — a Domain protocol / its Infrastructure implementation.
- **Composition Root** — the single place (`SIPDependencyContainer`) where
  concrete types are wired.
- **Provider / Engine** — a `VoiceProviderProtocol` implementation (SIP or vendor).
- **Terminal event** — `callEnded`/`callFailed`; no further events follow for that
  call id.
- **Stub bridge** — `BaresipBridge` compiled without the native library, returning
  `ENOTAVAIL`.
