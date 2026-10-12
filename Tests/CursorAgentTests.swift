// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Cursor's desktop database holds no billed token counts, only the context
/// size, model name, time and composer of each request. These tests pin the
/// reader's field selection (nothing prompt-like leaves SQLite), the
/// parser's context estimates, and the account quota parsing.
enum CursorAgentTests {
    private static func line(_ json: String) -> Data { Data(json.utf8) }

    private static func request(composer: String = "c1", bubble: String = "b1", tokens: Int = 33501,
                                model: String = "composer-2.5",
                                time: String = "2026-07-30T15:18:28.904Z",
                                directory: String = "/Users/me/code/app") -> Data {
        line(#"{"role":"user","id":"\#(bubble)","session_id":"\#(composer)","time_created":"\#(time)","tokens":\#(tokens),"model":"\#(model)","directory":"\#(directory)"}"#)
    }

    static func run(_ suite: TestSuite) {
        parsing(suite)
        turns(suite)
        reader(suite)
        quota(suite)
    }

    private static func parsing(_ suite: TestSuite) {
        var state = AgentLogState()
        let now = AgentTimestamp.parse("2026-07-30T15:20:00Z")!
        let entries = AgentLogParser.parseCursor(request(), state: &state, now: now)
        suite.expect(entries.count == 2, "a Cursor request opens a turn and records usage")
        if case .usage(let key, let record, _)? = entries.first(where: { if case .usage = $0 { return true }; return false }) {
            suite.expect(key == "cursor:c1:b1", "a Cursor usage key names its composer and bubble")
            suite.expect(record.provider == .cursor && record.model == "composer-2.5"
                         && record.project == "app" && record.session == "c1",
                         "a Cursor record keeps model, project and session")
            suite.expect(record.tokens.input == 33501 && record.tokens.output == 0 && record.requests == 1,
                         "a Cursor record estimates the input from the context and leaves the output at zero")
            suite.expect(record.date == AgentTimestamp.parse("2026-07-30T15:18:28.904Z"),
                         "a Cursor record keeps the bubble's own date")
        } else {
            suite.expect(false, "a Cursor request records usage")
        }

        // A bubble without a context size never asked the model anything.
        var quiet = AgentLogState()
        let silent = AgentLogParser.parseCursor(request(tokens: 0), state: &quiet, now: now)
        suite.expect(!silent.contains { if case .usage = $0 { return true }; return false },
                     "a Cursor bubble without context size records no usage")

        // A second reading of the same bubble merges into the same record.
        let store = AgentUsageStore()
        store.reportsTransitions = true
        let file = "/tmp/cursor-state.vscdb#c1"
        store.apply(entries, file: file, provider: .cursor, tracksTurns: true,
                    modified: now, now: now)
        store.apply(entries, file: file, provider: .cursor, tracksTurns: true,
                    modified: now, now: now)
        suite.expect(store.records.count == 1 && store.records.first?.tokens.input == 33501,
                     "a reread Cursor bubble changes nothing")
    }

    private static func turns(_ suite: TestSuite) {
        var state = AgentLogState()
        let now = AgentTimestamp.parse("2026-07-30T15:20:00Z")!
        let first = AgentLogParser.parseCursor(request(), state: &state, now: now)
        suite.expect(first.first == .turnBegan(AgentTimestamp.parse("2026-07-30T15:18:28.904Z")!),
                     "a composer's first request begins its turn")
        let second = AgentLogParser.parseCursor(
            request(bubble: "b2", time: "2026-07-30T15:19:00.000Z"), state: &state, now: now)
        suite.expect(second.first == .turnActive(AgentTimestamp.parse("2026-07-30T15:19:00.000Z")!),
                     "a composer's next request continues its turn")
        let other = AgentLogParser.parseCursor(
            request(composer: "c2", bubble: "b1", time: "2026-07-30T15:19:10.000Z"), state: &state, now: now)
        suite.expect(other.first == .turnBegan(AgentTimestamp.parse("2026-07-30T15:19:10.000Z")!),
                     "another composer begins a turn of its own")
        let reset = AgentLogParser.parseCursor(line(#"{"type":"reset"}"#), state: &state, now: now)
        suite.expect(reset == [.reset(now)] && state.openCodeSessions.isEmpty,
                     "a replaced Cursor database forgets its composers")
    }

    /// A temporary database in Cursor's shape: headers name each composer's
    /// folder, bubbles hold prompts alongside their counters.
    private static func reader(_ suite: TestSuite) {
        let tmpDir = FileManager.default.temporaryDirectory.appending(path: "vorss-cursor-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let dbPath = tmpDir.appending(path: "state.vscdb").path

        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK, let db else {
            suite.expect(false, "temporary Cursor database opens")
            return
        }
        sqlite3_exec(db, """
        CREATE TABLE composerHeaders (composerId TEXT PRIMARY KEY, workspaceId TEXT, createdAt INTEGER,
            lastUpdatedAt INTEGER, isArchived INTEGER, isSubagent INTEGER, recency INTEGER, checkpointAt INTEGER,
            value TEXT, subagentTypeName TEXT);
        CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
        """, nil, nil, nil)
        sqlite3_exec(db, """
        INSERT INTO composerHeaders VALUES ('c1', 'ws1', 1785395935080, 1785395935208, 0, 0, 0, 0,
            '{"workspaceIdentifier":{"uri":{"fsPath":"/Users/me/code/app"}},"trackedGitRepos":[]}', '');
        INSERT INTO cursorDiskKV VALUES ('bubbleId:c1:b1',
            '{"type":1,"bubbleId":"b1","createdAt":"2026-07-30T15:18:28.904Z","modelInfo":{"modelName":"composer-2.5"},"contextWindowStatusAtCreation":{"tokensUsed":33501},"tokenCount":{"inputTokens":0,"outputTokens":0},"text":"steal this prompt"}');
        INSERT INTO cursorDiskKV VALUES ('bubbleId:c1:a1',
            '{"type":2,"bubbleId":"a1","createdAt":"2026-07-30T15:18:40.000Z","tokenCount":{"inputTokens":0,"outputTokens":0},"text":"steal this reply"}');
        INSERT INTO cursorDiskKV VALUES ('bubbleId:c1:b2',
            '{"type":1,"bubbleId":"b2","createdAt":"2026-07-30T15:19:00.000Z","modelInfo":{"modelName":"composer-2.5"},"contextWindowStatusAtCreation":{"tokensUsed":41474},"tokenCount":{"inputTokens":0,"outputTokens":0},"text":"another prompt"}');
        """, nil, nil, nil)
        sqlite3_close(db)

        let cursor = AgentLogCursor(path: dbPath, provider: .cursor)
        var payloads: [String] = []
        AgentCursorReader.readAppended(cursor) { payloads.append(String(decoding: $0, as: UTF8.self)) }
        suite.expect(payloads.count == 2, "the Cursor reader hands over one request per user bubble")
        suite.expect(payloads.allSatisfy { !$0.contains("steal this") },
                     "prompts and replies never leave the Cursor database")
        let first = (try? JSONSerialization.jsonObject(with: Data((payloads.first ?? "").utf8))) as? [String: Any]
        suite.expect(first?["directory"] as? String == "/Users/me/code/app"
                     && first?["session_id"] as? String == "c1" && first?["id"] as? String == "b1",
                     "the Cursor reader maps composers to their folders")
        suite.expect(cursor.offset == 3, "the Cursor reader moves past the last row read")

        // Incremental reads only return what was saved after them.
        var db2: OpaquePointer?
        guard sqlite3_open(dbPath, &db2) == SQLITE_OK, let db2 else {
            suite.expect(false, "re-opening Cursor database")
            return
        }
        sqlite3_exec(db2, """
        INSERT INTO cursorDiskKV VALUES ('bubbleId:c1:b3',
            '{"type":1,"bubbleId":"b3","createdAt":"2026-07-30T15:20:00.000Z","modelInfo":{"modelName":"composer-2.5"},"contextWindowStatusAtCreation":{"tokensUsed":44841},"tokenCount":{"inputTokens":0,"outputTokens":0},"text":"x"}');
        """, nil, nil, nil)
        sqlite3_close(db2)
        payloads.removeAll()
        AgentCursorReader.readAppended(cursor) { payloads.append(String(decoding: $0, as: UTF8.self)) }
        suite.expect(payloads.count == 1 && payloads.first?.contains(#""id":"b3""#) == true,
                     "an incremental Cursor read returns only newer bubbles")

        // Rows older than the horizon are let go on a first read.
        let fresh = AgentLogCursor(path: dbPath, provider: .cursor)
        payloads.removeAll()
        AgentCursorReader.readAppended(fresh, since: AgentTimestamp.parse("2026-07-30T15:19:30Z")!) {
            payloads.append(String(decoding: $0, as: UTF8.self))
        }
        suite.expect(payloads.count == 1 && payloads.first?.contains(#""id":"b3""#) == true,
                     "a first Cursor read starts at the horizon")

        // Cancellation reads nothing.
        payloads.removeAll()
        AgentCursorReader.readAppended(fresh, shouldContinue: { false }) {
            payloads.append(String(decoding: $0, as: UTF8.self))
        }
        suite.expect(payloads.isEmpty, "a cancelled Cursor read hands over nothing")
    }

    private static func quota(_ suite: TestSuite) {
        let now = AgentTimestamp.parse("2026-10-12T12:00:00Z")!
        let data = Data("""
        {"composer-2.5":{"numRequests":150,"maxRequestUsage":500},"grok-4.5":{"numRequests":500,"maxRequestUsage":500},
         "startOfMonth":"2026-10-01T00:00:00.000Z"}
        """.utf8)
        if let limits = AgentCursorUsage.limits(from: data, now: now) {
            suite.expect(limits.provider == .cursor && limits.source == .account && limits.windows.count == 2,
                         "the Cursor quota keeps one window per model")
            let spent = limits.windows.first { $0.scope == "grok-4.5" }
            suite.expect(spent?.usedPercent == 100, "a spent Cursor model reads fully used")
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
            suite.expect(limits.windows.allSatisfy { $0.resetsAt == calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)) },
                         "Cursor windows renew on the first of next month")
        } else {
            suite.expect(false, "a known Cursor quota answer parses")
        }
        suite.expect(AgentCursorUsage.limits(from: Data(#"{"other":{}}"#.utf8), now: now) == nil,
                     "an unknown Cursor quota answer reads as nothing")
        suite.expect(AgentCursorUsage.limits(from: Data("[".utf8), now: now) == nil,
                     "a broken Cursor quota answer reads as nothing")
    }
}
