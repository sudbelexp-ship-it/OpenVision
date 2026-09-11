// OpenVision - SberGigaChatTests.swift
// Разбор ответов GigaChat API по реальным примерам из Фазы 3a (см. NOTES.md, раздел 9) —
// JSON-фикстуры ниже воспроизводят структуру настоящих ответов сервера (значения токена/ключа
// в фикстурах не использовались и не являются секретами), без сети и без ключей.

import XCTest
@testable import OpenVision

final class SberGigaChatTests: XCTestCase {

    // MARK: - POST /api/v2/oauth

    func testOAuthParse_realExample() throws {
        // Структура и значение expires_at — реальные из прогона Фазы 3a (NOTES.md, раздел 9).
        let json = """
        {"access_token": "eyJhbGciOiJFUzI1NiJ9.example-not-a-real-token", "expires_at": 1789164972473}
        """
        let parsed = try SberOAuthResponse.parse(Data(json.utf8))
        XCTAssertFalse(parsed.accessToken.isEmpty)
        XCTAssertEqual(parsed.expiresAtMs, 1_789_164_972_473)
    }

    func testOAuthParse_missingAccessToken_throws() {
        let json = #"{"expires_at": 1789164972473}"#
        XCTAssertThrowsError(try SberOAuthResponse.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? SberOAuthResponse.ParseError, .missingAccessToken)
        }
    }

    func testOAuthParse_missingExpiresAt_throws() {
        let json = #"{"access_token": "abc"}"#
        XCTAssertThrowsError(try SberOAuthResponse.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? SberOAuthResponse.ParseError, .missingExpiresAt)
        }
    }

    func testOAuthParse_invalidJSON_throws() {
        XCTAssertThrowsError(try SberOAuthResponse.parse(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? SberOAuthResponse.ParseError, .invalidJSON)
        }
    }

    // MARK: - GET /api/v1/models

    func testModelsResponseParse_realExample() throws {
        // Подмножество реального ответа (полный прогон вернул 14 моделей — см. NOTES.md).
        let json = """
        {"data": [
            {"id": "GigaChat"},
            {"id": "GigaChat-2"},
            {"id": "GigaChat-2-Max"},
            {"id": "GigaChat-2-Pro"},
            {"id": "GigaChat-Max"}
        ]}
        """
        let parsed = try GigaChatModelsResponse.parse(Data(json.utf8))
        XCTAssertEqual(parsed.count, 5)
    }

    func testModelsResponseParse_invalidJSON_throws() {
        XCTAssertThrowsError(try GigaChatModelsResponse.parse(Data("{}".utf8)))
    }

    // MARK: - POST /api/v1/files

    func testFileResponseParse_realExample() throws {
        // id — реальный UUID из прогона Фазы 3a (файл был удалён сразу после теста).
        let json = #"{"id": "03e23836-753b-4218-8f6b-68aac90a3af5", "bytes": 11763, "purpose": "general"}"#
        let parsed = try GigaChatFileResponse.parse(Data(json.utf8))
        XCTAssertEqual(parsed.id, "03e23836-753b-4218-8f6b-68aac90a3af5")
    }

    func testFileResponseParse_missingId_throws() {
        XCTAssertThrowsError(try GigaChatFileResponse.parse(Data(#"{"bytes": 123}"#.utf8))) { error in
            XCTAssertEqual(error as? GigaChatFileResponse.ParseError, .missingId)
        }
    }

    // MARK: - POST /api/v1/chat/completions

    func testChatResponseParse_realExample() throws {
        // Текст ответа — реальный вывод GigaChat-2-Max на тестовое изображение (Фаза 3a).
        let json = """
        {
            "choices": [{
                "message": {
                    "role": "assistant",
                    "content": "На картинке изображена чашка с горячим напитком, из которой поднимается пар."
                },
                "index": 0,
                "finish_reason": "stop"
            }],
            "created": 1757620000,
            "model": "GigaChat-2-Max",
            "object": "chat.completion",
            "usage": {"prompt_tokens": 10, "completion_tokens": 20, "total_tokens": 30}
        }
        """
        let content = try GigaChatChatResponse.parse(Data(json.utf8))
        XCTAssertEqual(content, "На картинке изображена чашка с горячим напитком, из которой поднимается пар.")
    }

    func testChatResponseParse_emptyChoices_throws() {
        XCTAssertThrowsError(try GigaChatChatResponse.parse(Data(#"{"choices": []}"#.utf8))) { error in
            XCTAssertEqual(error as? GigaChatChatResponse.ParseError, .emptyChoices)
        }
    }

    func testChatResponseParse_missingContent_throws() {
        let json = #"{"choices": [{"message": {"role": "assistant"}}]}"#
        XCTAssertThrowsError(try GigaChatChatResponse.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? GigaChatChatResponse.ParseError, .missingContent)
        }
    }

    // MARK: - Изменение размера изображения перед загрузкой

    func testUploadScale_capsLongSideAt1600() {
        // Типичное фото с очков/камеры, длинная сторона больше лимита.
        let scale = SberService.uploadScale(width: 4032, height: 3024)
        XCTAssertEqual(scale, 1600.0 / 4032.0, accuracy: 0.0001)
        XCTAssertEqual(3024 * scale, 1200, accuracy: 0.5)   // короткая сторона остаётся ≥ 800
    }

    func testUploadScale_doesNotUpscaleSmallImage() {
        let scale = SberService.uploadScale(width: 640, height: 480)
        XCTAssertEqual(scale, 1.0)
    }

    // MARK: - AppSettings

    func testDefaultBackendIsSber() {
        XCTAssertEqual(AppSettings().aiBackend, .sber)
    }

    func testIsSberConfigured() {
        var settings = AppSettings()
        XCTAssertFalse(settings.isSberConfigured)
        settings.sberAuthKey = "example-key"
        XCTAssertTrue(settings.isSberConfigured)
        XCTAssertTrue(settings.isCurrentBackendConfigured)
    }
}
