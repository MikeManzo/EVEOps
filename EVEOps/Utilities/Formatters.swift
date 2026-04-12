import Foundation

enum EVEFormatters {
    static let iskFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    static func formatISK(_ value: Double) -> String {
        let formatted = iskFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "\(formatted) ISK"
    }

    static func formatISKShort(_ value: Double) -> String {
        let abs = abs(value)
        let sign = value < 0 ? "-" : ""
        switch abs {
        case 1_000_000_000_000...:
            return "\(sign)\(String(format: "%.1fT", abs / 1_000_000_000_000)) ISK"
        case 1_000_000_000...:
            return "\(sign)\(String(format: "%.1fB", abs / 1_000_000_000)) ISK"
        case 1_000_000...:
            return "\(sign)\(String(format: "%.1fM", abs / 1_000_000)) ISK"
        case 1_000...:
            return "\(sign)\(String(format: "%.1fK", abs / 1_000)) ISK"
        default:
            return formatISK(value)
        }
    }

    static func formatDuration(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    static func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "Done" }
        return formatDuration(Int(interval))
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
