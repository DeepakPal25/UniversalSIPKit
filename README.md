# UniversalSIPKit

A provider-independent, open-source iOS calling SDK built with Clean Architecture and Swift 6 concurrency.

UniversalSIPKit lets an app add VoIP calling without implementing SIP registration, call management, RTP media, CallKit, PushKit, audio routing, or credential storage itself. SIP is just one provider — the same public API also drives non-SIP vendors (e.g. Twilio) through a provider-neutral engine seam.

> **Status:** early development. The architecture, public API, and an in-memory engine are complete and tested. Real SIP engines (Baresip/PJSIP) and the Twilio provider are scaffolded behind the engine protocol and are not yet wired to their native libraries. See [Engine status](#engine-status).

## Why

Most iOS SIP libraries (PJSIP, Linphone, Baresip wrappers) are **SIP-locked** and often **copyleft/commercial**. UniversalSIPKit aims to be different:

- **One SDK API + multiple providers + replaceable engines.** SIP engines and cloud voice vendors are interchangeable behind a single protocol.
- **Permissively licensed.** Baresip (BSD-3-Clause) is the preferred SIP engine so the SDK can ship under a permissive license usable by closed-source apps. See [`docs/ENGINE-EVALUATION.md`](docs/ENGINE-EVALUATION.md).
- **Clean Architecture.** The Domain layer has zero external dependencies; engines live in Infrastructure behind protocols.

## Features

- SIP registration, outgoing/incoming audio calls, answer/reject/end, mute, hold.
- Provider-neutral model: SIP **and** token-based vendors (Twilio/Vonage/Agora) behind one API.
- Native CallKit integration and PushKit/VoIP-push incoming calls (adapters included).
- `AVAudioSession` coordination designed around CallKit's audio-session lifecycle.
- Keychain-backed credential storage.
- Multiple accounts.
- Typed `AsyncStream` event model; Swift 6 strict concurrency (actors throughout).

## Architecture

```
Presentation / Public API   →  UniversalSIPKit (facade, DI container)
        │
      Domain                →  SIPDomain  (entities, use cases, protocols — no external deps)
        ▲        ▲
      Data      Infrastructure
   (SIPData)   (SIPInfrastructure: engines, CallKit, PushKit, audio, keychain)
```

Targets: `SIPDomain`, `SIPData`, `SIPInfrastructure`, and the public `UniversalSIPKit` umbrella. The engine boundary is [`VoiceProviderProtocol`](Sources/SIPDomain/Repositories/VoiceProviderProtocol.swift); accounts and secrets are provider-neutral via `VoiceAccount` and `ProviderCredential` (`.sip` / `.accessToken` / `.custom`).

## Installation

Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/DeepakPal25/UniversalSIPKit.git", branch: "main")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "UniversalSIPKit", package: "UniversalSIPKit")
    ])
]
```

Requirements: iOS 15+ (library also builds on macOS 12+ for tests/CI). Swift 6 toolchain.

## Quick start

### SIP

```swift
import UniversalSIPKit

let sdk = UniversalSIPKit.shared

try await sdk.configure(configuration: SIPConfiguration(
    server: "sip.example.com",
    domain: "example.com",
    port: 5060,
    transport: .tls
))

try await sdk.addAccount(SIPAccountConfiguration(
    username: "1001",
    password: "your-password"
))

try await sdk.connect()
try await sdk.call(to: "1002")
```

### Non-SIP vendor (e.g. Twilio) — same API

```swift
try await sdk.initialize()

let account = VoiceAccount(providerID: "twilio", identity: "alice", settings: ["region": "us1"])
sdk.addAccount(account, credential: .accessToken(tokenFromYourBackend))

try await sdk.connect()
try await sdk.call(to: "bob")
```

### Observing events

```swift
for await event in await sdk.observeEvents() {
    switch event {
    case .incomingCall(let call):      print("Incoming:", call.remoteNumber)
    case .callConnected(let id):       print("Connected:", id)
    case .callEnded(let id):           print("Ended:", id)
    default: break
    }
}
```

The public API: `configure` / `initialize` / `addAccount` / `removeAccount` / `connect` / `disconnect` / `call(to:)` / `answer` / `reject` / `endCall` / `setMuted` / `setHeld` / `observeEvents`.

## Engine status

| Provider | Type | State |
|---|---|---|
| `InMemoryVoiceProvider` | simulator | ✅ working — used by tests/demos |
| `BaresipAdapter` / `BaresipEngine` | SIP (BSD) | 🚧 scaffolded; needs the Baresip XCFramework — see [`docs/BARESIP-POC.md`](docs/BARESIP-POC.md) |
| `PJSIPAdapter` | SIP (GPL/commercial) | 🚧 skeleton fallback |
| `TwilioVoiceProvider` | non-SIP | 🚧 skeleton; needs the Twilio Voice SDK |

The `BaresipBridge` C target compiles as a no-op stub (guarded by `#if __has_include(<baresip.h>)`) until the engine binary is linked, so the package builds today without any native SIP library. Swap providers in the composition root (`SIPDependencyContainer`) with no changes to Domain, Data, use cases, or the public API.

## Building & testing

```sh
swift build
swift test            # 16 tests
# iOS:
xcodebuild -scheme UniversalSIPKit -destination 'generic/platform=iOS' build
```

## Documentation

- [`docs/TECHNICAL.md`](docs/TECHNICAL.md) — full technical reference: the problem, the theory behind each layer, every runtime flow, the concurrency/event contracts, security, and the complete edge-case matrix.
- [`docs/ENGINE-EVALUATION.md`](docs/ENGINE-EVALUATION.md) — Baresip vs PJSIP vs Linphone, licensing, and the build-vs-reuse analysis.
- [`docs/BARESIP-POC.md`](docs/BARESIP-POC.md) — the Baresip integration proof-of-concept runbook and validation gates.

## Roadmap

1. ✅ Clean Architecture foundation + provider-neutral engine seam.
2. 🚧 Baresip iOS PoC — the CallKit audio handoff is the decision gate.
3. `BaresipAdapter` full implementation.
4. PushKit + VoIP push gateway contract.
5. Demo app, API docs, production hardening.

## License

Intended to be released under a permissive license (MIT or BSD-3-Clause), pending a final dependency/license audit. A `LICENSE` file will be added before any tagged release. Until then, no license is granted by default.
