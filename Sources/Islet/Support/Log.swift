import os

/// Unified logging. Read with: log stream --predicate 'subsystem == "app.islet"'
enum Log {
    nonisolated static let source = Logger(subsystem: "app.islet", category: "source")
    nonisolated static let island = Logger(subsystem: "app.islet", category: "island")
    nonisolated static let system = Logger(subsystem: "app.islet", category: "system")
}
