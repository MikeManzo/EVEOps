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
import OSLog

/// Records an error on a path that is deliberately non-fatal — a sidebar badge
/// count, a detail-pane enrichment, a best-effort cache write. The caller keeps
/// degrading gracefully; this just makes the failure visible in Diagnostic Logs
/// instead of vanishing into an empty `catch {}`.
///
/// Task cancellation is not a failure and is dropped silently.
@MainActor
func logSuppressed(
    _ error: Error,
    _ context: String,
    category: EVELogger? = nil
) {
    if error is CancellationError { return }
    if let urlError = error as? URLError, urlError.code == .cancelled { return }
    (category ?? Logger.app).debug("\(context) — suppressed error: \(error.localizedDescription)")
}
