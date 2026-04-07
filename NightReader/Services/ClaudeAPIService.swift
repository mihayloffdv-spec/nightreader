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

    /// Ask a question about the book with chapter context.
    static func askQuestion(
        question: String,
        bookTitle: String,
        chapterText: String,
        history: [ChatMessage] = []
    ) async throws -> String {
        let system = """
            Ты — помощник для чтения книги «\(bookTitle)». Отвечай на вопросы \
            читателя, опираясь на текст. Отвечай на русском, кратко (3-5 предложений), \
            если вопрос не требует развёрнутого ответа. Цитируй текст где уместно.
            """

        var messages: [ClaudeMessage] = []
        // Add conversation history (last 6 messages max)
        for msg in history.suffix(6) {
            messages.append(ClaudeMessage(role: msg.role, content: msg.content))
        }
        messages.append(ClaudeMessage(role: "user", content: """
            Контекст из книги:
            \(chapterText.prefix(8000))

            Вопрос: \(question)
            """))

        return try await sendMessages(
            system: system,
            messages: messages,
            model: AIActionType.explain.modelID,
            maxTokens: 1024
        )
    }

    /// Generate chapter review questions after reading a chapter.
    static func generateChapterQuestions(
        chapterText: String,
        bookTitle: String,
        chapterTitle: String?
    ) async throws -> ChapterQuestionResult {
        let chapterCtx = chapterTitle.map { " «\($0)»" } ?? ""
        let system = """
            Ты — вдумчивый преподаватель. Сгенерируй 3 вопроса для размышления \
            после прочтения главы\(chapterCtx) книги «\(bookTitle)». \
            Вопросы должны побуждать к рефлексии, а не проверять знания. \
            Также дай краткое резюме главы (2-3 предложения). \
            Верни JSON: {"questions": ["вопрос1", "вопрос2", "вопрос3"], "summary": "резюме"}
            """

        let response = try await sendMessage(
            system: system,
            userMessage: "Текст главы:\n\(chapterText.prefix(8000))",
            model: AIActionType.explain.modelID,
            maxTokens: 1024
        )

        // Defensive JSON extraction
        guard let jsonData = JSONExtractor.extractObject(from: response) else {
            return ChapterQuestionResult(questions: [], summary: nil)
        }

        do {
            return try JSONDecoder().decode(ChapterQuestionResult.self, from: jsonData)
        } catch {
            #if DEBUG
            print("[ClaudeAPI] Failed to decode chapter questions: \(error)")
            #endif
            return ChapterQuestionResult(questions: [], summary: nil)
        }
    }

    /// Analyze chapter text and return smart highlight suggestions.
    /// - typeWeights: optional weights from save/dismiss ratios (nil = equal distribution)
    static func analyzeChapter(
        text: String,
        bookTitle: String,
        chapterTitle: String?,
        density: Int = 5,
        typeWeights: [SmartHighlightType: Double]? = nil
    ) async throws -> [SmartHighlightResult] {
        // Skip very short chapters — not enough context
        let wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        guard wordCount >= 200 else { return [] }

        let chapterCtx = chapterTitle.map { ", глава «\($0)»" } ?? ""

        // Build type preference hint from save/dismiss ratios
        var typeHint = ""
        if let weights = typeWeights {
            let sorted = weights.sorted { $0.value > $1.value }
            let preferred = sorted.first?.key.rawValue ?? "thesis"
            let avoided = sorted.last?.key.rawValue ?? "actionable"
            if sorted.first!.value > sorted.last!.value + 0.1 {
                typeHint = " Читатель предпочитает тип «\(preferred)» и реже сохраняет «\(avoided)». Учти это при выборе."
            }
        }

        let system = """
            Ты — вдумчивый читатель, отмечающий самые ценные предложения в книге. \
            Отмечай только то, что заставит человека остановиться и задуматься. \
            Максимум \(density) предложений. \
            Ссылайся на конкретное содержание текста. \
            Никогда не используй общие фразы вроде «важный момент» или «ключевой аргумент». \
            Твоё объяснение должно доказать, что ты прочитал и понял отрывок.\(typeHint) \
            Верни JSON массив: [{"text": "точное предложение из текста", "type": "thesis|insight|actionable", "rationale": "одно предложение почему"}]
            """

        let userMessage = "Книга: «\(bookTitle)»\(chapterCtx)\n\nТекст главы:\n\(text.prefix(12000))"

        let response = try await sendMessage(
            system: system,
            userMessage: userMessage,
            model: AIActionType.explain.modelID,
            maxTokens: 2048
        )

        // Defensive JSON extraction
        guard let jsonData = JSONExtractor.extractArray(from: response) else {
            return []
        }

        do {
            return try JSONDecoder().decode([SmartHighlightResult].self, from: jsonData)
        } catch {
            #if DEBUG
            print("[ClaudeAPI] Failed to decode smart highlights: \(error)")
            #endif
            return []
        }
    }

    // MARK: - Network Layer

    /// Send with multiple messages (for chat history).
    private static func sendMessages(system: String, messages: [ClaudeMessage], model: String, maxTokens: Int = 1024) async throws -> String {
        guard let apiKey = KeychainManager.getAPIKey(), !apiKey.isEmpty else {
            throw ClaudeAPIError.noAPIKey
        }
        let request = ClaudeRequest(model: model, maxTokens: maxTokens, system: system, messages: messages)
        var urlRequest = URLRequest(url: URL(string: baseURL)!)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 401: throw ClaudeAPIError.invalidAPIKey
                case 429: throw ClaudeAPIError.rateLimited
                case 529: throw ClaudeAPIError.serverOverloaded
                default: throw ClaudeAPIError.apiError("Ошибка сервера (\(httpResponse.statusCode))")
                }
            }
            throw ClaudeAPIError.networkError("Неверный ответ сервера")
        }
        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = claudeResponse.text, !text.isEmpty else { throw ClaudeAPIError.emptyResponse }
        return text
    }

    private static func sendMessage(system: String, userMessage: String, model: String, maxTokens: Int = 1024) async throws -> String {
        guard let apiKey = KeychainManager.getAPIKey(), !apiKey.isEmpty else {
            throw ClaudeAPIError.noAPIKey
        }

        let request = ClaudeRequest(
            model: model,
            maxTokens: maxTokens,
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
