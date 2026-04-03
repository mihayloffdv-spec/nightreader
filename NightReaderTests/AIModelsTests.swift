import XCTest
@testable import NightReader

// MARK: - Тесты для AI-моделей

final class AIModelsTests: XCTestCase {

    // MARK: - AIActionType.modelID

    /// Оба типа действий используют модель Haiku
    func testModelID_explainUsesHaiku() {
        let modelID = AIActionType.explain.modelID
        XCTAssertTrue(modelID.contains("haiku"))
    }

    func testModelID_translateUsesHaiku() {
        let modelID = AIActionType.translate.modelID
        XCTAssertTrue(modelID.contains("haiku"))
    }

    /// Оба возвращают одинаковый ID модели
    func testModelID_bothReturnSameModel() {
        XCTAssertEqual(AIActionType.explain.modelID, AIActionType.translate.modelID)
    }

    // MARK: - AIActionType.displayName

    /// explain → "Объяснение"
    func testDisplayName_explain() {
        XCTAssertEqual(AIActionType.explain.displayName, "Объяснение")
    }

    /// translate → "Перевод"
    func testDisplayName_translate() {
        XCTAssertEqual(AIActionType.translate.displayName, "Перевод")
    }

    // MARK: - AIResponseState equality

    /// idle == idle
    func testResponseState_idleEquality() {
        XCTAssertEqual(AIResponseState.idle, AIResponseState.idle)
    }

    /// loading == loading
    func testResponseState_loadingEquality() {
        XCTAssertEqual(AIResponseState.loading, AIResponseState.loading)
    }

    /// success с одинаковым текстом — равны
    func testResponseState_successEquality() {
        XCTAssertEqual(AIResponseState.success("текст"), AIResponseState.success("текст"))
    }

    /// error с одинаковым текстом — равны
    func testResponseState_errorEquality() {
        XCTAssertEqual(AIResponseState.error("ошибка"), AIResponseState.error("ошибка"))
    }

    /// Разные состояния — не равны
    func testResponseState_differentStatesNotEqual() {
        XCTAssertNotEqual(AIResponseState.idle, AIResponseState.loading)
        XCTAssertNotEqual(AIResponseState.loading, AIResponseState.success("ok"))
        XCTAssertNotEqual(AIResponseState.success("ok"), AIResponseState.error("ok"))
        XCTAssertNotEqual(AIResponseState.idle, AIResponseState.error("err"))
    }

    /// success с разным текстом — не равны
    func testResponseState_successDifferentText() {
        XCTAssertNotEqual(AIResponseState.success("а"), AIResponseState.success("б"))
    }

    // MARK: - ClaudeRequest encoding

    /// Проверяем что JSON содержит правильные ключи
    func testClaudeRequest_encoding() throws {
        let request = ClaudeRequest(
            model: "claude-haiku-4-5-20251001",
            maxTokens: 512,
            system: "Ты помощник.",
            messages: [ClaudeMessage(role: "user", content: "Привет")]
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["model"] as? String, "claude-haiku-4-5-20251001")
        XCTAssertEqual(json?["max_tokens"] as? Int, 512)
        XCTAssertEqual(json?["system"] as? String, "Ты помощник.")

        // Проверяем массив сообщений
        let messages = json?["messages"] as? [[String: Any]]
        XCTAssertNotNil(messages)
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"] as? String, "user")
        XCTAssertEqual(messages?.first?["content"] as? String, "Привет")
    }

    /// Запрос без system — ключ system может быть nil в JSON
    func testClaudeRequest_encodingWithoutSystem() throws {
        let request = ClaudeRequest(
            model: "claude-haiku-4-5-20251001",
            messages: [ClaudeMessage(role: "user", content: "Тест")]
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["model"] as? String, "claude-haiku-4-5-20251001")
        XCTAssertEqual(json?["max_tokens"] as? Int, 1024) // значение по умолчанию
    }

    // MARK: - ClaudeResponse decoding

    /// Парсинг JSON-ответа от Claude API
    func testClaudeResponse_decoding() throws {
        let jsonString = """
        {
            "id": "msg_123",
            "content": [
                {
                    "type": "text",
                    "text": "Это объяснение текста."
                }
            ],
            "stop_reason": "end_turn"
        }
        """

        let data = jsonString.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        XCTAssertEqual(response.id, "msg_123")
        XCTAssertEqual(response.stop_reason, "end_turn")
        XCTAssertEqual(response.content.count, 1)
        XCTAssertEqual(response.content[0].type, "text")
        XCTAssertEqual(response.content[0].text, "Это объяснение текста.")

        // Проверяем вспомогательное свойство text
        XCTAssertEqual(response.text, "Это объяснение текста.")
    }

    /// Ответ с несколькими блоками контента — text берёт первый текстовый
    func testClaudeResponse_multipleContentBlocks() throws {
        let jsonString = """
        {
            "id": "msg_456",
            "content": [
                {
                    "type": "text",
                    "text": "Первый блок"
                },
                {
                    "type": "text",
                    "text": "Второй блок"
                }
            ],
            "stop_reason": "end_turn"
        }
        """

        let data = jsonString.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        XCTAssertEqual(response.content.count, 2)
        // text возвращает первый текстовый блок
        XCTAssertEqual(response.text, "Первый блок")
    }
}
