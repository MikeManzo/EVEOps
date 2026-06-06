//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import OSLog

extension Logger {
    static var app: EVELogger { EVELogger(category: "app") }
    static var auth: EVELogger { EVELogger(category: "auth") }
    static var network: EVELogger { EVELogger(category: "network") }
    static var prefetch: EVELogger { EVELogger(category: "prefetch") }
    static var api: EVELogger { EVELogger(category: "api") }
    static var sdeData: EVELogger { EVELogger(category: "sdeData") }
    static var dogmaEngine: EVELogger { EVELogger(category: "dogmaEngine") }
    static var systemSearch: EVELogger { EVELogger(category: "systemSearch") }
    static var eveRef: EVELogger { EVELogger(category: "eveRef") }
}
