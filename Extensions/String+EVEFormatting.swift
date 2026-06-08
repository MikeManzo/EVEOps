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

extension String {
    /// Strips EVE Online markup from a description string.
    /// Handles literal \\uXXXX Unicode escapes (common in EVE bios/item descriptions),
    /// <br> line-break tags, arbitrary HTML tags, and common HTML entities.
    var strippingEVEMarkup: String {
        var result = self
        // ESI sometimes returns bios stored as Python unicode literals: u'...'
        if result.hasPrefix("u'") && result.hasSuffix("'") {
            result = String(result.dropFirst(2).dropLast())
        }
        result = result.decodingUnicodeEscapes
        result = result.replacingOccurrences(of: "<br>",   with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "<br/>",  with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // EVE bios sometimes store literal \uXXXX sequences as text instead of actual Unicode characters.
    private var decodingUnicodeEscapes: String {
        guard contains("\\u") else { return self }
        guard let pattern = try? NSRegularExpression(pattern: "\\\\u([0-9a-fA-F]{4})") else { return self }
        var result = self
        let matches = pattern.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let hexRange = Range(match.range(at: 1), in: result),
                  let codePoint = UInt32(result[hexRange], radix: 16),
                  let scalar = Unicode.Scalar(codePoint),
                  let fullRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(fullRange, with: String(scalar))
        }
        return result
    }
}
