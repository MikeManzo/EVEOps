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
