import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let smartHighlightsReady = Notification.Name("smartHighlightsReady")
}

// MARK: - AI Action Types

enum AIActionType: String {
    case explain = "explain"
    case translate = "translate"

    var displayName: String {
        switch self {
        case .explain: return "Объяснение"
        case .translate: return "Перевод"
        }
    }

    var menuTitle: String {
        switch self {
        case .explain: return "Объясни проще"
        case .translate: return "Переведи"
        }
    }

    var menuIcon: String {
        switch self {
        case .explain: return "lightbulb"
        case .translate: return "globe"
        }
    }

    /// Which Claude model to use for this action type.
    /// Haiku for fast/simple tasks, Sonnet for complex ones.
    var modelID: String {
        switch self {
        case .explain: return "claude-haiku-4-5-20251001"
        case .translate: return "claude-haiku-4-5-20251001"
        }
    }
}

// MARK: - AI Request/Response State

enum AIResponseState: Equatable {
    case idle
    case loading
    case success(String)
    case error(String)

    static func == (lhs: AIResponseState, rhs: AIResponseState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.loading, .loading): return true
        case (.success(let a), .success(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Claude API Request/Response (Messages API)

struct ClaudeRequest: Encodable {
    let model: String
    let max_tokens: Int
    let messages: [ClaudeMessage]
    let system: String?

    init(model: String, maxTokens: Int = 1024, system: String? = nil, messages: [ClaudeMessage]) {
        self.model = model
        self.max_tokens = maxTokens
        self.system = system
        self.messages = messages
    }
}

struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

struct ClaudeResponse: Decodable {
    let id: String
    let content: [ContentBlock]
    let stop_reason: String?

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    /// Extract the text from the first text content block.
    var text: String? {
        content.first(where: { $0.type == "text" })?.text
    }
}

struct ClaudeErrorResponse: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let type: String
        let message: String
    }
}

// MARK: - Chat Message (for AI Q&A)

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String          // "user" or "assistant"
    let content: String
    let timestamp = Date()
}

// MARK: - Chapter Question Result

struct ChapterQuestionResult: Decodable {
    let questions: [String]
    let summary: String?
}

// MARK: - Smart Highlight API Response

struct SmartHighlightResult: Decodable {
    let text: String
    let type: String       // "thesis", "insight", "actionable"
    let rationale: String

    var highlightType: SmartHighlightType {
        SmartHighlightType(rawValue: type) ?? .insight
    }
}

// MARK: - Argument Map (AI chapter structure analysis)

struct ArgumentMap: Codable, Identifiable {
    let id: UUID
    let chapterIndex: Int
    let chapterTitle: String?
    let thesis: String           // core claim of the chapter
    let evidence: [String]       // supporting points
    let conclusion: String       // what the author concludes
    let createdAt: Date

    init(chapterIndex: Int, chapterTitle: String?, thesis: String, evidence: [String], conclusion: String) {
        self.id = UUID()
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.thesis = thesis
        self.evidence = evidence
        self.conclusion = conclusion
        self.createdAt = Date()
    }
}

struct ArgumentMapResult: Decodable {
    let thesis: String
    let evidence: [String]
    let conclusion: String
}

// MARK: - JSON Extraction Helper

enum JSONExtractor {
    /// Extract a JSON array from a potentially messy Claude response.
    /// Handles: clean JSON, markdown code fences, preamble text.
    static func extractArray(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences if present
        var cleaned = trimmed
        if let fenceStart = cleaned.range(of: "```json") ?? cleaned.range(of: "```") {
            cleaned = String(cleaned[fenceStart.upperBound...])
        }
        if let fenceEnd = cleaned.range(of: "```", options: .backwards) {
            cleaned = String(cleaned[..<fenceEnd.lowerBound])
        }

        // Find the JSON array: first '[' to last ']'
        guard let arrayStart = cleaned.firstIndex(of: "["),
              let arrayEnd = cleaned.lastIndex(of: "]") else {
            return nil
        }

        let jsonString = String(cleaned[arrayStart...arrayEnd])
        return jsonString.data(using: .utf8)
    }

    /// Extract a JSON object {...} from a messy response.
    static func extractObject(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleaned = trimmed
        if let fenceStart = cleaned.range(of: "```json") ?? cleaned.range(of: "```") {
            cleaned = String(cleaned[fenceStart.upperBound...])
        }
        if let fenceEnd = cleaned.range(of: "```", options: .backwards) {
            cleaned = String(cleaned[..<fenceEnd.lowerBound])
        }
        guard let objStart = cleaned.firstIndex(of: "{"),
              let objEnd = cleaned.lastIndex(of: "}") else { return nil }
        let jsonString = String(cleaned[objStart...objEnd])
        return jsonString.data(using: .utf8)
    }
}
