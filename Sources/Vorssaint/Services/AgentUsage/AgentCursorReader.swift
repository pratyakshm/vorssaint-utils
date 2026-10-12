// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// How far reading Cursor's database has got: the last rowid read, which
/// `AgentLogCursor.offset` holds. Bubbles are never updated in place, so no
/// open replies need tracking: a second reading of a row merges into the
/// same record and changes nothing.
struct AgentCursorProgress {
    /// Composer ids and the newest bubble rowid seen for each, oldest last.
    var tail: [(rowid: Int64, composer: String, bubble: String)] = []
}

/// Reads Cursor agent requests from its desktop database
/// (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`).
///
/// What is read, and what is not: each user bubble hands over only its
/// composer and bubble identifiers, its creation time, the selected model
/// name and the context size at creation. Prompts, replies, file contents,
/// tool arguments and retrieved context never leave the database: the query
/// takes out those few fields with `json_extract`, so the blobs stay inside
/// SQLite.
///
/// Cursor keeps no billed token counts on this Mac (`tokenCount` reads zero
/// everywhere): the context size is the billed input of the request that
/// followed, and the model's reply size is unknown. Records estimate the
/// input from the context and leave the output at zero, so their cost is a
/// lower bound until the price list knows the model.
enum AgentCursorReader {
    /// The database Cursor keeps in its `globalStorage` folder.
    static let database = "state.vscdb"

    /// Rows read last, newest last, to notice when the newest were deleted.
    static let tailLength = 64

    /// When the database or its write-ahead log last changed; nil when there
    /// is no database.
    static func modified(_ path: String) -> Date? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        var wal = stat()
        let walModified = stat(path + "-wal", &wal) == 0 ? date(wal.st_mtimespec) : .distantPast
        return max(date(info.st_mtimespec), walModified)
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }

    /// Reads the bubbles saved since the last read, oldest first. Calls
    /// `line` with a small JSON payload per request; see the enum comment
    /// for which fields those hold.
    static func readAppended(_ cursor: AgentLogCursor, since horizon: Date = .distantPast,
                             shouldContinue: () -> Bool = { true }, line: (Data) -> Void) {
        guard shouldContinue() else { return }
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        let identity = UInt64(info.st_ino)
        if identity != cursor.identity {
            let replaced = cursor.identity != 0
            cursor.identity = identity
            restart(cursor, announce: replaced, line: line)
        }
        cursor.modified = modified(cursor.path) ?? date(info.st_mtimespec)

        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(cursor.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return
        }
        sqlite3_busy_timeout(db, 2000)

        if !resumes(db, cursor) { restart(cursor, announce: true, line: line) }
        let projects = projectMap(db)
        let horizonText = iso(horizon)

        // Only the counters leave the database. `key` holds
        // `bubbleId:{composer}:{bubble}`; the value's creation time reads as
        // an ISO string, so a string comparison against the horizon holds.
        let select = """
        SELECT rowid, key,
            json_extract(value, '$.type'),
            json_extract(value, '$.createdAt'),
            json_extract(value, '$.modelInfo.modelName'),
            json_extract(value, '$.contextWindowStatusAtCreation.tokensUsed'),
            json_extract(value, '$.bubbleId')
        FROM cursorDiskKV WHERE rowid > ? AND key LIKE 'bubbleId:%' ORDER BY rowid
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, select, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(cursor.offset))
        while shouldContinue() && sqlite3_step(stmt) == SQLITE_ROW {
            let rowid = sqlite3_column_int64(stmt, 0)
            cursor.offset = UInt64(max(0, rowid))
            guard let key = text(stmt, 1),
                  sqlite3_column_type(stmt, 2) != SQLITE_NULL,
                  sqlite3_column_int(stmt, 2) == 1,
                  let created = text(stmt, 3), created >= horizonText,
                  let bubble = text(stmt, 6) ?? text(stmt, 1).flatMap({ $0.split(separator: ":").last.map(String.init) }),
                  !bubble.isEmpty
            else { continue }
            let tokens = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? 0 : Int(sqlite3_column_int64(stmt, 5))
            // A bubble without a context size never asked the model anything.
            guard tokens > 0 else { continue }
            let parts = key.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { continue }
            let composer = parts[1]
            var json: [String: Any] = [
                "role": "user",
                "id": bubble,
                "session_id": composer,
                "time_created": created,
                "tokens": tokens,
            ]
            if let model = text(stmt, 4), !model.isEmpty { json["model"] = model }
            if let directory = projects[composer], !directory.isEmpty { json["directory"] = directory }
            cursor.openCode.tail.append((rowid, bubble))
            if cursor.openCode.tail.count > AgentOpenCodeReader.tailLength { cursor.openCode.tail.removeFirst() }
            if let data = try? JSONSerialization.data(withJSONObject: json) { line(data) }
        }
    }

    /// The folder each composer works in, from the headers table: the
    /// workspace path when Cursor knows it, else the first tracked
    /// repository. Nothing else in that table is read.
    private static func projectMap(_ db: OpaquePointer?) -> [String: String] {
        var map: [String: String] = [:]
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT composerId, value FROM composerHeaders", -1, &stmt, nil) == SQLITE_OK
        else { return map }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let composer = text(stmt, 0), !composer.isEmpty,
                  let raw = text(stmt, 1), let data = raw.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { continue }
            var directory = ((json["workspaceIdentifier"] as? [String: Any])?["uri"] as? [String: Any])?["fsPath"] as? String
            if directory == nil || directory?.isEmpty == true {
                directory = ((json["trackedGitRepos"] as? [[String: Any]])?.first)?["repoPath"] as? String
            }
            if let directory, !directory.isEmpty { map[composer] = directory }
        }
        return map
    }

    /// Starts over from the horizon, telling the parser to forget what the
    /// earlier reading left open.
    private static func restart(_ cursor: AgentLogCursor, announce: Bool, line: (Data) -> Void) {
        cursor.offset = 0
        cursor.openCode = AgentOpenCodeProgress()
        cursor.state = AgentLogState()
        if announce {
            line(Data(#"{"type":"reset"}"#.utf8))
        }
    }

    /// False when every row read last is gone or holds another bubble, so
    /// the place reached means nothing. When only the newest were deleted,
    /// reading goes on after the newest one still there.
    private static func resumes(_ db: OpaquePointer?, _ cursor: AgentLogCursor) -> Bool {
        let tail = cursor.openCode.tail
        guard !tail.isEmpty else { return true }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT key FROM cursorDiskKV WHERE rowid = ?", -1, &stmt, nil) == SQLITE_OK else {
            return true
        }
        defer { sqlite3_finalize(stmt) }
        for position in tail.indices.reversed() {
            sqlite3_reset(stmt)
            sqlite3_bind_int64(stmt, 1, tail[position].rowid)
            guard sqlite3_step(stmt) == SQLITE_ROW, let key = text(stmt, 0),
                  key.hasSuffix(":" + tail[position].id) else { continue }
            cursor.offset = UInt64(tail[position].rowid)
            cursor.openCode.tail.removeLast(tail.count - 1 - position)
            return true
        }
        return false
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func iso(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }
}
