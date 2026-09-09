import Foundation
import GRDB

/// A row from ZCode's model_usage table
struct UsageRecord: Codable, FetchableRecord, TableRecord, Identifiable {
    static let databaseTableName = "model_usage"

    var id: String
    var turnId: String?
    var sessionId: String
    var inputTokens: Int
    var outputTokens: Int
    var reasoningTokens: Int
    var cacheReadInputTokens: Int
    var cacheCreationInputTokens: Int
    var computedTotalTokens: Int
    var modelId: String
    var providerId: String
    var durationMs: Int
    var status: String
    var startedAtMs: Int64

    var createdAt: Date { Date(timeIntervalSince1970: Double(startedAtMs) / 1000.0) }

    enum CodingKeys: String, CodingKey {
        case id
        case turnId = "turn_id"
        case sessionId = "session_id"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case reasoningTokens = "reasoning_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case computedTotalTokens = "computed_total_tokens"
        case modelId = "model_id"
        case providerId = "provider_id"
        case durationMs = "duration_ms"
        case status
        case startedAtMs = "started_at"
    }
}

/// A row from ZCode's turn_usage table
struct TurnRecord: Codable, FetchableRecord, TableRecord, Identifiable {
    static let databaseTableName = "turn_usage"

    var sessionId: String
    var turnId: String
    var inputTokens: Int
    var outputTokens: Int
    var reasoningTokens: Int
    var cacheReadInputTokens: Int
    var cacheCreationInputTokens: Int
    var computedTotalTokens: Int
    var modelRequestCount: Int
    var toolCallCount: Int
    var durationMs: Int
    var status: String
    var startedAtMs: Int64

    var id: String { "\(sessionId)/\(turnId)" }
    var startedAt: Date { Date(timeIntervalSince1970: Double(startedAtMs) / 1000.0) }
    var createdAt: Date { startedAt }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case turnId = "turn_id"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case reasoningTokens = "reasoning_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case computedTotalTokens = "computed_total_tokens"
        case modelRequestCount = "model_request_count"
        case toolCallCount = "tool_call_count"
        case durationMs = "duration_ms"
        case status
        case startedAtMs = "started_at"
    }
}

/// Daily aggregated usage for charting
struct DailyUsage: Identifiable {
    var id = UUID()
    let date: Date
    let inputTokens: Int
    let outputTokens: Int
    let computedTotal: Int

    init(date: String, inputTokens: Int, outputTokens: Int, computedTotal: Int) {
        self.id = UUID()
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.computedTotal = computedTotal
        // SQLite date() returns "yyyy-MM-dd"; fall back to a safe default on failure
        self.date = DailyUsage.dateFormatter.date(from: date) ?? Date.distantPast
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
}

/// Cumulative totals
struct UsageTotals {
    let totalInput: Int
    let totalOutput: Int
    let totalComputed: Int
    let callCount: Int
}

/// A discovered skill from ~/.zcode/skills/
struct SkillInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let path: String
    let source: String  // "local", "plugin", "symlink"

    var slashCommand: String { "/\(name)" }
}

/// A discovered plugin
struct PluginInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let description: String
    let path: String
    let skillNames: [String]
    let isEnabled: Bool

    var slashCommand: String { "/\(name)" }
}