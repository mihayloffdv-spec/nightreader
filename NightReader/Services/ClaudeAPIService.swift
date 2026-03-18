import Foundation

// MARK: - Claude API Service
//
// HTTP client for Claude Messages API. Handles explain and translate actions.
//
//  ┌───────────┐   selectedText    ┌──────────────────┐
//  │ViewModel  │──────────────────▶│ ClaudeAPIService  │
//  │ .explain()│                   │                    │
//  │ .translate│                   │  1. Check API key  │
//  └───────────┘                   │  2. Build prompt   │
//                                  │  3. POST to API    │
//                                  │  4. Parse response  │
//                                  └────────┬───────────┘
//                                           │
//                                  ┌────────▼───────────┐
//                                  │ api.anthropic.com   │
//                                  │ /v1/messages        │
//                                  └────────────────────┘

enum ClaudeAPIError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case rateLimited
    case serverOverloaded
    case emptyResponse
    case networkError(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "API ключ не задан. Введите ключ в настройках."
        case .invalidAPIKey: return "Неверный API ключ. Проверьте ключ в настройках."
        case .rateLimited: return "Слишком много запросов. Подождите немного."
        case .serverOverloaded: return "Сервис перегружен. Попробуйте позже."
        case .emptyResponse: return "Пустой ответ от AI. Попробуйте ещё раз."
        case .networkError(let msg): return "Ошибка сети: \(msg)"
        case .apiError(let msg): return msg
        }
    }
}

enum ClaudeAPIService {

    private static let baseURL = "https://api.anthropic.com/v1/messages"
    private static let apiVersion = "2023-06-01"
    private static let timeout: TimeInterval = 30

    // MARK: - Public API

    /// Explain selected text in simple terms.
    static func explain(text: String, bookContext: String? = nil) async throws -> String {
        let system = "Ты — помощник для чтения книг. Объясняй простым, понятным языком. Отвечай кратко — 2-4 предложения. Если текст на иностранном языке, объясняй на русском."

        var userMessage = "Объясни этот фрагмент простым языком:\n\n\"\(text)\""
        if let context = bookContext, !context.isEmpty {
            userMessage += "\n\nКонтекст из книги:\n\(context)"
        }

        return try await sendMessage(
            system: system,
            userMessage: userMessage,
            model: AIActionType.explain.modelID
        )
    }

    /// Translate selected text.
    static func translate(text: String) async throws -> String {
        let system = "Ты — переводчик. Если текст на русском — переведи на английский. Если на любом другом языке — переведи на русский. Давай только перевод, без пояснений. Если текст — одно слово, дай перевод и краткое определение."

        let userMessage = "Переведи:\n\n\"\(text)\""

        return try await sendMessage(
            system: system,
            userMessage: userMessage,
            model: AIActionType.translate.modelID
        )
    }

    // MARK: - Network Layer

    private static func sendMessage(system: String, userMessage: String, model: String) async throws -> String {
        guard let apiKey = KeychainManager.getAPIKey(), !apiKey.isEmpty else {
            throw ClaudeAPIError.noAPIKey
        }

        let request = ClaudeRequest(
            model: model,
            maxTokens: 1024,
            system: system,
            messages: [ClaudeMessage(role: "user", content: userMessage)]
        )

        var urlRequest = URLRequest(url: URL(string: baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut:
                throw ClaudeAPIError.networkError("Превышено время ожидания")
            case .notConnectedToInternet, .networkConnectionLost:
                throw ClaudeAPIError.networkError("Нет подключения к интернету")
            default:
                throw ClaudeAPIError.networkError(urlError.localizedDescription)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.networkError("Неверный ответ сервера")
        }

        switch httpResponse.statusCode {
        case 200:
            break // success
        case 401:
            throw ClaudeAPIError.invalidAPIKey
        case 429:
            throw ClaudeAPIError.rateLimited
        case 529:
            throw ClaudeAPIError.serverOverloaded
        default:
            // Log raw error for debugging but show sanitized message to user
            if let errorResponse = try? JSONDecoder().decode(ClaudeErrorResponse.self, from: data) {
                #if DEBUG
                print("[ClaudeAPI] Error \(httpResponse.statusCode): \(errorResponse.error.message)")
                #endif
            }
            throw ClaudeAPIError.apiError("Ошибка сервера (\(httpResponse.statusCode)). Попробуйте позже.")
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = claudeResponse.text, !text.isEmpty else {
            throw ClaudeAPIError.emptyResponse
        }

        return text
    }
}
