// OpenVision - SberService.swift
// Бэкенд "Сбер" (GigaChat) — облачный текст + vision, российский стек.
//
// По структуре — калька с OpenAIService.swift (простой запрос/ответ без стриминга), но с двумя
// архитектурными отличиями GigaChat: (1) OAuth2 client-credentials вместо статического ключа
// (см. SberAuth), (2) изображение сначала грузится отдельным запросом (GigaChatClient.uploadImage),
// а не кодируется inline base64 — модель получает его по `attachments: [file_id]`.

import Foundation
import UIKit

@MainActor
final class SberService: ObservableObject {

    static let shared = SberService()

    /// Полный ответ ассистента (озвучивается через TTS в VoiceAgentView).
    var onAgentMessage: ((String) -> Void)?
    /// Начало/конец обработки (управляет состоянием "думает").
    var onProcessingChanged: ((Bool) -> Void)?

    @Published private(set) var isConnected = false

    private var settings: AppSettings { SettingsManager.shared.settings }

    private init() {}

    /// GigaChat — REST без сессии; "подключение" — просто проверка, что ключ задан.
    func connect() async throws {
        guard settings.isSberConfigured else { throw SberError.notConfigured }
        isConnected = true
    }

    /// Отправить реплику (опционально с фото) и вернуть ответ через `onAgentMessage`.
    func sendMessage(_ text: String, imageData: Data? = nil) async throws {
        guard settings.isSberConfigured else { throw SberError.notConfigured }
        NativeToolContext.shared.set(text)

        onProcessingChanged?(true)
        defer { onProcessingChanged?(false) }

        let authKey = settings.sberAuthKey
        var uploadedFileId: String?
        // Файл нужен только на время запроса — удаляем сразу после ответа (или после ошибки,
        // если успели загрузить), не оставляя мусор в хранилище GigaChat.
        defer {
            if let fileId = uploadedFileId {
                let key = authKey
                Task { try? await GigaChatClient.shared.deleteFile(fileId, authKey: key) }
            }
        }

        let userText = text.isEmpty ? "Что изображено на этой картинке?" : text
        var attachments: [String]?
        let model: String

        if let imageData {
            let resized = Self.resizeForUpload(imageData)
            let fileId = try await GigaChatClient.shared.uploadImage(resized, authKey: authKey)
            uploadedFileId = fileId
            attachments = [fileId]
            model = settings.sberVisionModel
        } else {
            model = settings.sberTextModel
        }

        var messages: [[String: Any]] = []
        let system = systemPrompt()
        if !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        // История — последние N сообщений общего диалогового контекста приложения (см.
        // ConversationContext; фото передаются только в текущем запросе, не в истории).
        let limit = max(0, settings.sberHistoryLimit)
        for turn in ConversationContext.shared.turns.suffix(limit) {
            messages.append(["role": turn.role, "content": turn.content])
        }
        var userMessage: [String: Any] = ["role": "user", "content": userText]
        if let attachments {
            userMessage["attachments"] = attachments
        }
        messages.append(userMessage)

        let payload: [String: Any] = ["model": model, "messages": messages]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let reply = try await GigaChatClient.shared.chat(body: body, authKey: authKey)
        ConversationContext.shared.record(user: text, assistant: reply)
        onAgentMessage?(reply)
    }

    // MARK: - Системный промпт

    private func systemPrompt() -> String {
        var parts = [settings.sberSystemPrompt]
        let custom = settings.userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { parts.append(custom) }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Подготовка изображения

    /// Длинная сторона ≤ `Constants.Sber.maxLongSide` (без апскейла — короткая сторона ≥
    /// `minShortSide` получается "бесплатно" для обычных фото с соотношением сторон до ~2:1,
    /// иначе — по возможности, см. PLAN.md Фаза 3b).
    static func resizeForUpload(_ jpeg: Data) -> Data {
        guard let image = UIImage(data: jpeg) else { return jpeg }
        let scale = uploadScale(width: image.size.width, height: image.size.height)
        guard scale < 1.0 else {
            return image.jpegData(compressionQuality: Constants.Sber.jpegQuality) ?? jpeg
        }
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return resized.jpegData(compressionQuality: Constants.Sber.jpegQuality) ?? jpeg
    }

    /// Чистая функция масштаба — вынесена отдельно от UIKit-рисования для юнит-теста.
    static func uploadScale(width: CGFloat, height: CGFloat) -> CGFloat {
        let longSide = max(width, height)
        guard longSide > 0 else { return 1.0 }
        return min(1.0, Constants.Sber.maxLongSide / longSide)
    }
}
