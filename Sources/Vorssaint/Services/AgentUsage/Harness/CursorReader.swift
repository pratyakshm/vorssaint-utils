// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Cursor's desktop database rows as handed over by `AgentCursorReader`.
/// Cursor writes one user bubble per request into its database. The reader
/// hands over only identifiers, time, model and context size per bubble: the
/// context size is the billed input of the request, and the reply size is
/// unknown, so the output stays at zero and the cost is a lower bound. Each
/// composer is a session of its own; its turns end by going quiet, never by a
/// word in the database.
struct CursorReader: AgentHarnessReader {
    var provider: AgentProvider { .cursor }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard AgentLogParser.contains(line, #""role":""#) || AgentLogParser.contains(line, #""type":"reset""#) else { return [] }
        guard let json = AgentLogParser.object(line) else { return [] }
        if json["type"] as? String == "reset" {
            state.openCodeSessions.removeAll()
            state.turnOpen = false
            return [.reset(now)]
        }
        guard json["role"] as? String == "user",
              let composer = json["session_id"] as? String, !composer.isEmpty,
              let id = json["id"] as? String, !id.isEmpty else { return [] }
        state.session = AgentLogParser.native(composer)
        state.parentSession = ""
        var sessionState = state.openCodeSessions[composer] ?? OpenCodeSessionState()
        if let directory = json["directory"] as? String, !directory.isEmpty {
            sessionState.project = AgentLogParser.projectName(directory)
        }
        let date = AgentLogParser.timestamp(json["time_created"]) ?? AgentLogParser.seconds(json["time_created"]) ?? now
        sessionState.lastActivity = max(sessionState.lastActivity ?? date, date)
        let model = AgentLogParser.native(json["model"] as? String ?? "")
        if !model.isEmpty { sessionState.model = model }
        let input = AgentLogParser.int(json["tokens"])
        guard input > 0 else {
            state.openCodeSessions[composer] = sessionState
            return []
        }
        var entries: [AgentLogEntry] = []
        if sessionState.turnOpen {
            entries.append(.turnActive(date))
        } else {
            sessionState.turnOpen = true
            sessionState.turnStarted = date
            entries.append(.turnBegan(date))
        }
        let tokens = AgentTokens(input: input, cacheWrite: 0, cacheRead: 0, output: 0, reasoning: 0)
        let billable = AgentBillable(tokens: tokens)
        let priced = AgentPricing.cost(billable, model: sessionState.model)
        entries.append(.usage(key: "cursor:\(composer):\(id)", record: AgentUsageRecord(
            provider: .cursor, date: date, model: sessionState.model, project: sessionState.project,
            session: composer, tokens: tokens, cost: priced.cost, savings: priced.savings), billable: billable))
        state.openCodeSessions[composer] = sessionState
        state.project = sessionState.project
        state.model = sessionState.model
        state.turnOpen = true
        return entries
    }
}
