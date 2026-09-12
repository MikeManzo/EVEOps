# Privacy Policy

**Effective date: September 12, 2026**

This Privacy Policy explains what data EVEOps (the "App") accesses, stores, and transmits, and to whom. EVEOps is a local, unofficial third-party macOS companion app for EVE Online — there is no EVEOps-operated server, account system, or database. Nearly everything described below happens directly between your Mac and the third party in question (CCP Games, Discord, or a community data provider), not through any infrastructure run by the App's developer.

## 1. Data EVEOps Accesses

### EVE Online account data (via EVE SSO / ESI)

When you add a character, EVEOps authenticates you directly against CCP Games' EVE SSO using OAuth 2.0 with PKCE. EVEOps never sees or stores your EVE Online password. The resulting access/refresh tokens are stored in the **macOS Keychain**, scoped to the app, and are used only to call the official ESI API (`esi.evetech.net`) on your behalf — e.g. wallet, skills, assets, contracts, location, and the other data shown in the app's various views. This data is cached locally (in a local file under `~/Library/Application Support/EVEOps/` and in-memory) purely to make the app responsive; it is not uploaded anywhere else.

### Local diagnostic logs

EVEOps keeps a local diagnostic log (`~/Library/Application Support/EVEOps/diagnostics.json`) to help you or the developer troubleshoot issues, viewable from within the app. This file never leaves your Mac unless you choose to share it yourself (e.g. attaching it to a bug report).

### Discord webhook alerts (optional, off by default)

If you enable "Send alerts to Discord" and provide a webhook URL, EVEOps sends the same alert content shown in your native macOS notifications (e.g. "Skill queue empty," "Structure fuel low") to that URL. The webhook URL itself is stored in the macOS Keychain. EVEOps does not read anything back from Discord, does not access your Discord account, and does not see your Discord server's other content.

### Discord Rich Presence (optional, off by default)

If you enable "Show current character in Discord status," EVEOps connects directly to the Discord desktop client running on your own Mac (via a local inter-process socket — not a network request) and sets your Discord activity status to your currently selected character's ship and solar system. No Discord login, token, or account access is involved; this only works while the Discord desktop app is open on the same machine, and stops the moment you disable the feature, switch it off, or quit EVEOps.

### Third-party lookups (optional, as used)

Certain features call out to community-run EVE data services on your behalf when you use them, for example zKillboard (killmail data), Janice/Fuzzwork (market pricing), and EVE Scout (wormhole connections). These requests go directly from your Mac to those services; EVEOps does not proxy, log, or retain a copy of them beyond normal in-memory/display use.

## 2. What EVEOps Does *Not* Do

- **No EVEOps-operated server or account.** There is nothing to sign up for, and no central database that stores your data.
- **No analytics, telemetry, or crash-reporting SDKs.** EVEOps does not track your usage, behavior, or install any third-party analytics library.
- **No advertising, and no sale of data.** EVEOps does not monetize or share your data with advertisers or data brokers — there's nothing to share, since nothing is collected by the developer in the first place.
- **No access to your Discord account.** The webhook and Rich Presence features described above do not use Discord OAuth or require you to sign in to Discord through EVEOps.

## 3. Where Your Data Lives

| Data | Location | Leaves your Mac? |
|---|---|---|
| EVE SSO tokens | macOS Keychain | Only to `login.eveonline.com` / `esi.evetech.net` |
| Discord webhook URL | macOS Keychain | Only in the POST bodies you configure it to send |
| Cached ESI data (wallet, skills, etc.) | Local app cache | No |
| Diagnostic logs | Local app support folder | No (unless you share it yourself) |

## 4. Children's Privacy

EVEOps is intended for use by EVE Online players, consistent with CCP Games' own age requirements for EVE Online. The App does not knowingly collect data from children, and — per Section 1 — does not collect personal data on any server in the first place.

## 5. Changes to This Policy

This policy may be updated as the App's features change. Updates are published to this file in the [EVEOps repository](https://github.com/MikeManzo/EVEOps), with the effective date revised accordingly.

## 6. Contact

Questions about this policy, or to report a data-handling concern, can be raised via [GitHub Issues](https://github.com/MikeManzo/EVEOps/issues) or by emailing **manzo.mike@gmail.com**. For security vulnerabilities specifically, see [SECURITY.md](SECURITY.md).

## 7. Disclaimer

EVEOps is an unofficial third-party application and is not affiliated with or endorsed by [Fenris Creations](https://fenriscreations.com). EVE Online and all related trademarks are property of Fenris Creations. EVEOps is similarly not affiliated with or endorsed by Discord Inc. Your use of CCP Games' and Discord's own services remains subject to their respective privacy policies:

- [CCP Games Privacy Policy](https://www.ccpgames.com/privacy)
- [Discord Privacy Policy](https://discord.com/privacy)
