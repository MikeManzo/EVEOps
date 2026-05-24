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
    private static let subsystem = Bundle.main.bundleIdentifier ?? "CitizenCoder.EVEops"
    
    static let sdeData = Logger(subsystem: subsystem, category: "sdeData")
    static let dogmaEngine = Logger(subsystem: subsystem, category: "dogmaEngine")
    static let systemSearch = Logger(subsystem: subsystem, category: "systemSearch")
}
