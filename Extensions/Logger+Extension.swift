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
    static var sdeData: EVELogger { EVELogger(category: "sdeData") }
    static var dogmaEngine: EVELogger { EVELogger(category: "dogmaEngine") }
    static var systemSearch: EVELogger { EVELogger(category: "systemSearch") }
}
