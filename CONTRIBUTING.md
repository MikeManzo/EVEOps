# Contributing to EVEOps

Thanks for your interest in contributing. EVEOps is a native macOS app for EVE Online built in Swift and SwiftUI, and contributions of all kinds are welcome — bug fixes, new features, documentation improvements, and more.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Reporting Bugs](#reporting-bugs)
- [Proposing Features](#proposing-features)
- [Pull Request Process](#pull-request-process)
- [Code Style](#code-style)
- [Architecture Overview](#architecture-overview)
- [EVE / ESI Specifics](#eve--esi-specifics)

---

## Code of Conduct

Be respectful. Critique code, not people. If a discussion becomes unproductive, disengage.

---

## Getting Started

### Prerequisites

| Requirement | Version |
|---|---|
| macOS | 14 (Sonoma) or later |
| Xcode | 15 or later |
| EVE Online account | Any |
| ESI application | [developers.eveonline.com](https://developers.eveonline.com) |

### Setup

1. Fork the repository and clone your fork.

2. Register an ESI application at [developers.eveonline.com](https://developers.eveonline.com):
   - Set the callback URL to `eveops://callback`.
   - Add the scopes listed in the README for the features you plan to work on.
   - Copy your **Client ID**.

3. Open `EVEOps/Auth/SSOAuthenticator.swift` and replace the placeholder:

   ```swift
   static let `default` = SSOConfiguration(
       clientID: "YOUR_CLIENT_ID",
       ...
   )
   ```

4. Open `EVEOps.xcodeproj` in Xcode and build the `EVEOps` target.

> **Never commit your Client ID.** It must remain a local-only change. If you accidentally push it, revoke it immediately at developers.eveonline.com and create a new one.

---

## Reporting Bugs

Before filing a new issue, search existing issues to avoid duplicates.

When opening a bug report, include:

- **macOS version** and **EVEOps version** (shown in Settings)
- **Steps to reproduce** — the minimal sequence that triggers the problem
- **Expected behavior** vs. **actual behavior**
- **Diagnostic logs** if available — EVEOps writes structured logs you can copy from the in-app diagnostics panel
- **ESI scope** involved, if the bug is data-related

For crashes, include the crash report from `~/Library/Logs/DiagnosticReports/`.

---

## Proposing Features

For anything beyond a small, self-contained change, **open an issue first** to discuss the idea before writing code. This avoids duplicated effort and ensures the proposed change aligns with the direction of the project.

A good feature proposal answers:

- What problem does this solve for EVE players?
- Which ESI endpoints or scopes does it require?
- Does it affect character data, corporation data, or both?
- Are there third-party services involved (Janice, zKillboard, EVE Scout, etc.)?

---

## Pull Request Process

1. Create a branch from `main` with a descriptive name (`fix/wallet-escrow-calculation`, `feature/moon-extraction-alerts`).

2. Keep the scope of each PR focused. A PR that fixes a bug and adds an unrelated feature is harder to review and harder to revert.

3. Build and test before opening the PR. The project must compile without warnings.

4. Fill out the PR description with:
   - What changed and why
   - Any ESI endpoints or scopes added or changed
   - Screenshots for any UI changes

5. PRs are reviewed on a best-effort basis. Please be patient — this is a solo-maintained project.

6. A PR may be closed without merging if it conflicts with the project's direction. Opening an issue to discuss first is the best way to avoid this.

---

## Code Style

EVEOps follows standard Swift conventions with a few project-specific rules:

### General

- **4-space indentation**, no tabs.
- `PascalCase` for types, `camelCase` for properties and methods.
- Use `let` wherever possible; reach for `var` only when mutation is necessary.
- Avoid force-unwrapping (`!`). Prefer `guard let`, `if let`, or provide a meaningful default.

### SwiftUI

- Each view owns its own file.
- State belongs as close to the view that uses it as possible. Lift only when necessary.
- Use `@State private var` for local view state. Reach for `@Environment` or `@Bindable` for shared state.
- Prefer `.task {}` for async work triggered by view appearance over `onAppear`.

### Concurrency

- Use `async`/`await` and actors throughout. **Do not introduce Combine.**
- Shared mutable state lives in actors. UI-facing state lives in `@MainActor @Observable` classes.
- Mark actor-isolated types explicitly. Do not rely on implicit isolation.

### Comments

- Default to no comments. Code should be self-documenting through clear naming.
- Add a comment only when the *why* is non-obvious: a hidden ESI constraint, a CCP quirk, a workaround for a specific API behavior.

### No Dead Code

- Do not leave commented-out code, unused variables, or `TODO` stubs in a PR. File an issue instead.

---

## Architecture Overview

Understanding where things live will help you place new code correctly.

| Layer | Key Types | Notes |
|---|---|---|
| **Auth** | `SSOAuthenticator`, `KeychainHelper` | OAuth 2.0 + PKCE; tokens never leave the Keychain |
| **Networking** | `ESIClient`, `ZKillboardClient`, `JaniceClient`, … | Each service has its own client; `ESIClient` handles caching via `Expires` headers |
| **Services** | `AccountManager`, `UniverseCache`, `NameResolver`, `DashboardPrefetcher` | Actors or `@MainActor @Observable`; long-lived singletons |
| **Models** | `ESIModels.swift`, `StoredAccount`, `CachedName` | Plain Swift types; `StoredAccount` is SwiftData-backed |
| **Views** | `Views/Character/`, `Views/Corporation/`, `Views/Main/`, … | Pure SwiftUI; views read from services via environment or direct reference |

**`ESIClient`** is the single point of contact with the ESI API. If you are adding a new ESI endpoint, add the fetch method there.

**`AccountManager`** owns the canonical character state. If your feature needs to expose new character data to views, surface it through `AccountManager`.

**`UniverseCache`** and **`NameResolver`** are disk-backed actor singletons. Resolved names and static universe data (types, systems, stations) are persisted across launches with a 7-day TTL. If your feature resolves IDs to names, use `NameResolver` rather than calling ESI directly.

---

## EVE / ESI Specifics

### ESI Rate Limits

EVEOps respects ESI `Expires` and `X-Esi-Error-Limit-Remain` headers. Do not bypass the existing cache in `ESIClient`. If a new endpoint needs a different refresh cadence, add a dedicated TTL rather than calling it on every view appearance.

### Scope Handling

Features that require an ESI scope the character hasn't granted should degrade gracefully — show a placeholder or a "scope not granted" message rather than crashing or showing an error alert.

When adding a new scope requirement, document it in the README's **Required ESI Scopes** section and make sure the feature works with the scope absent.

### Third-Party Services

EVEOps integrates with several third-party services (Janice, zKillboard, EVE Scout, Fuzzwork, EVE Ref). Contributions that add new third-party integrations should:

- Use an isolated client struct (following the pattern of `JaniceClient`, `ZKillboardClient`, etc.)
- Make all network calls through `async`/`await`
- Handle network unavailability gracefully — these services have no uptime guarantee

### CCP Fair Use Policy

All contributions must comply with [CCP's Developer License Agreement](https://developers.eveonline.com/resource/license-agreement) and [Third-Party Developer Policy](https://developers.eveonline.com/resource/third-party-developer-policy). Do not build features that automate in-game actions or violate the EVE Online EULA.

---

## Disclaimer

EVEOps is an unofficial third-party application and is not affiliated with or endorsed by Fenris Creations. EVE Online and all related trademarks are property of Fenris Creations.
