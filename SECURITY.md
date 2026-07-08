# Security Policy

## Supported Versions

Only the latest release of EVEOps receives security fixes. We do not backport patches to older versions.

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |
| Older   | No        |

## Reporting a Vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

To report a vulnerability, send an email to **manzo.mike@gmail.com** with the subject line `[EVEOps Security]`. Include as much detail as possible:

- A clear description of the vulnerability
- Steps to reproduce or a proof-of-concept
- The potential impact (data exposure, privilege escalation, etc.)
- Your name/handle if you'd like to be credited

You should receive an acknowledgement within **48 hours**. If you haven't heard back after 72 hours, please follow up.

Once a report is confirmed:

1. A fix will be developed privately.
2. A new release will be cut and published.
3. A security advisory will be opened on GitHub with credit to the reporter (unless you prefer to remain anonymous).

## Scope

EVEOps is a macOS companion app for EVE Online. Areas of particular security sensitivity:

- **OAuth 2.0 + PKCE authentication** — EVE SSO token handling and storage in the macOS Keychain
- **ESI API responses** — parsing and displaying data returned by `esi.evetech.net`
- **Sparkle update mechanism** — integrity and authenticity of app updates delivered via appcast
- **Third-party network clients** — requests to ZKillboard, Janice, Fuzzwork, EVE Scout, and similar services

Issues outside EVEOps itself — such as vulnerabilities in the EVE Online game, the ESI API, or CCP's infrastructure — should be reported directly to CCP Games.

## Security Design Notes

- EVE SSO tokens are stored exclusively in the macOS Keychain and are never transmitted to any server other than `login.eveonline.com` and `esi.evetech.net`.
- The app uses OAuth 2.0 with PKCE; no client secret is embedded in the binary.
- App updates are distributed via Sparkle with EdDSA signature verification — unsigned updates are rejected.
- No analytics or telemetry data is collected or transmitted.

## Preferred Languages

Reports may be submitted in English.
