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
    static var sdeData: Logger { Logger(subsystem: "CitizenCoder.EVEOps", category: "sdeData") }
    static var dogmaEngine: Logger { Logger(subsystem: "CitizenCoder.EVEOps", category: "dogmaEngine") }
    static var systemSearch: Logger { Logger(subsystem: "CitizenCoder.EVEOps", category: "systemSearch") }
}
