//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import Foundation

/// Shared HTTP identity for every outbound request EVEOps makes.
///
/// CCP's ESI guidelines ask third-party apps to send a descriptive `User-Agent`
/// that carries the app name, a version, and a contact URL, so they can reach the
/// maintainer before rate-limiting or blocking a misbehaving client. The same
/// string is reused for the other public APIs (zKillboard, Fuzzwork, Janice,
/// EVERef, EVE-Scout) which have the same expectation.
enum HTTPClientInfo {
    /// e.g. `EVEOps/0.9.10.6.1 (+https://github.com/MikeManzo/EVEOps; build 42)`
    static let userAgent: String = {
        let info    = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "dev"
        let build   = (info?["CFBundleVersion"] as? String) ?? "0"
        return "EVEOps/\(version) (+https://github.com/MikeManzo/EVEOps; build \(build))"
    }()
}
