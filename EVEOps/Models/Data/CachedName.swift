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
import SwiftData

@Model
final class CachedName {
    @Attribute(.unique) var id: Int
    var name: String
    var category: String
    var lastUpdated: Date

    init(id: Int, name: String, category: String) {
        self.id = id
        self.name = name
        self.category = category
        self.lastUpdated = Date()
    }
}
