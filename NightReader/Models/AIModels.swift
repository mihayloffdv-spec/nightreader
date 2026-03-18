import Foundation

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
