// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// The Cursor plan's request quota, as Cursor's own server reports it.
///
/// The desktop app signs in with the account and keeps that sign-in in its
/// local database. This reader borrows that sign-in for one question the
/// account itself answers: how many premium requests each model used of its
/// monthly allowance. The token is read fresh for every check, never kept,
/// never written anywhere and never sent anywhere but Cursor's own server.
/// Without a sign-in, or when the server's answer is not one this version
/// knows, there are no limits and the local usage still stands on its own.
///
/// Local request records carry context sizes, not billed requests, so these
/// windows describe the plan while the records describe the work.
enum AgentCursorUsage {
    /// Where Cursor keeps its sign-in, on every OS under a different folder.
    static func databaseURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb",
                       directoryHint: .notDirectory)
    }

    static let timeout: TimeInterval = 10

    /// The access token Cursor signed in with; nil when signed out or when
    /// the database cannot be read. The token never leaves this call except
    /// towards Cursor's own server.
    static func accessToken(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let path = databaseURL(home: home).path
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1000)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'",
                                 -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let raw = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }) else { return nil }
        // The value may be stored JSON-quoted.
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return token.isEmpty ? nil : token
    }

    /// Asks the account for its monthly request quota. Calls back on an
    /// arbitrary queue; nil when the account cannot answer right now.
    static func fetch(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                      token: String? = nil, now: Date = Date(),
                      completion: @escaping (AgentLimits?) -> Void) {
        guard let token = token ?? accessToken(home: home) else {
            completion(nil)
            return
        }
        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/auth/usage")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data, data.count < 1 << 20,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let limits = limits(from: data, now: now) else {
                completion(nil)
                return
            }
            completion(limits)
        }.resume()
    }

    /// Turns the server's per-model request counts into monthly windows that
    /// renew on the first of next month. Anything unexpected reads as
    /// nothing: the server may rename models or fields at any time.
    static func limits(from data: Data, now: Date) -> AgentLimits? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var windows: [AgentLimitWindow] = []
        for (model, value) in json {
            guard let counts = value as? [String: Any],
                  let used = (counts["numRequests"] as? NSNumber)?.doubleValue, used.isFinite, used >= 0,
                  let quota = (counts["maxRequestUsage"] as? NSNumber)?.doubleValue, quota.isFinite, quota > 0
            else { continue }
            let name = AgentLogParser.native(model)
            guard !name.isEmpty else { continue }
            windows.append(AgentLimitWindow(id: "cursor.\(name)", kind: .other, minutes: nil, scope: name,
                                            usedPercent: min(100, max(0, used / quota * 100)),
                                            resetsAt: nextMonth(after: now)))
        }
        guard !windows.isEmpty else { return nil }
        windows.sort { $0.usedPercent > $1.usedPercent }
        return AgentLimits(provider: .cursor, windows: windows, observedAt: now, source: .account)
    }

    /// Midnight on the first of next month, in UTC: the server brackets its
    /// quota month in UTC (`startOfMonth` reads midnight UTC).
    static func nextMonth(after now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let start = calendar.startOfDay(for: now)
        var parts = calendar.dateComponents([.year, .month], from: start)
        parts.month = (parts.month ?? 1) + 1
        parts.day = 1
        return calendar.date(from: parts)
    }
}
