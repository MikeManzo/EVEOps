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
import Foundation

/// Thin wrapper around `Logger` that simultaneously writes to `DiagnosticLogStore`
/// so the in-app diagnostic pane receives entries without any polling.
/// @MainActor matches Logger's own isolation in this SDK.
@MainActor
struct EVELogger {
    private let logger: Logger
    private let category: String

    init(category: String) {
        self.logger = Logger(subsystem: "CitizenCoder.EVEOps", category: category)
        self.category = category
    }

    func debug(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.debug("\(msg, privacy: .public)")
        DiagnosticLogStore.shared.write(date: Date(), category: category, level: .debug, message: msg)
    }

    func info(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.info("\(msg, privacy: .public)")
        DiagnosticLogStore.shared.write(date: Date(), category: category, level: .info, message: msg)
    }

    func notice(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.notice("\(msg, privacy: .public)")
        DiagnosticLogStore.shared.write(date: Date(), category: category, level: .notice, message: msg)
    }

    func warning(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.warning("\(msg, privacy: .public)")
        DiagnosticLogStore.shared.write(date: Date(), category: category, level: .notice, message: msg)
    }

    func error(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.error("\(msg, privacy: .public)")
        DiagnosticLogStore.shared.write(date: Date(), category: category, level: .error, message: msg)
    }

    func fault(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.fault("\(msg, privacy: .public)")
        DiagnosticLogStore.shared.write(date: Date(), category: category, level: .fault, message: msg)
    }
}
