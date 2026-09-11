// OpenVision - GigaChatClient.swift
// Низкоуровневый REST-клиент GigaChat: загрузка/удаление файла, chat/completions.
//
// Сериализован намеренно: тариф Freemium для физлиц обслуживает ровно один запрос одновременно —
// параллельный второй получает ошибку. `actor` сам по себе НЕ гарантирует это (Swift-акторы
// реентерабельны на await), поэтому запросы дополнительно проходят через явную последовательную
// очередь `enqueue`.
//
// Формат передачи изображения отличается от OpenAI/Gemini (inline base64): GigaChat требует
// отдельной загрузки файла через POST /files с получением `id`, который затем передаётся в
// `attachments` чат-запроса — подтверждено реальным прогоном в Фазе 3a (см. NOTES.md, раздел 9).

import Foundation

actor GigaChatClient {
    static let shared = GigaChatClient()

    private let session: URLSession
    private var queueTail: Task<Void, Never> = Task {}

    private init() {
        session = URLSession(configuration: .default, delegate: SberTrustDelegate(), delegateQueue: nil)
    }

    // MARK: - Публичное API (каждый вызов встаёт в очередь `enqueue`)

    func uploadImage(_ jpeg: Data, authKey: String) async throws -> String {
        try await enqueue { try await self.performUpload(jpeg, authKey: authKey) }
    }

    func deleteFile(_ fileId: String, authKey: String) async throws {
        try await enqueue { try await self.performDelete(fileId, authKey: authKey) }
    }

    /// `body` — уже сериализованный JSON `{"model": ..., "messages": [...]}`. Готовится в
    /// SberService (на MainActor) и передаётся сюда как `Data`, а не `[String: Any]`, — тип
    /// пересекает границу актора, а `Any` внутри словаря не `Sendable`.
    func chat(body: Data, authKey: String) async throws -> String {
        try await enqueue { try await self.performChat(body: body, authKey: authKey) }
    }

    /// OAuth + GET /models — используется кнопкой "Проверить подключение" в настройках.
    /// Возвращает количество доступных моделей (просто индикатор успеха для UI).
    func checkConnection(authKey: String) async throws -> Int {
        try await enqueue { try await self.performListModels(authKey: authKey) }
    }

    // MARK: - Последовательная очередь

    /// Ждёт завершения всех ранее поставленных операций, затем выполняет `operation` — так все
    /// запросы к GigaChat идут строго по одному, даже если вызваны параллельно.
    private func enqueue<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let previous = queueTail
        var outcome: Result<T, Error>!
        let task = Task {
            _ = await previous.value
            do {
                outcome = .success(try await operation())
            } catch {
                outcome = .failure(error)
            }
        }
        queueTail = Task { await task.value }
        await task.value
        return try outcome.get()
    }

    // MARK: - Запросы

    private func performUpload(_ jpeg: Data, authKey: String) async throws -> String {
        let boundary = "OpenVision-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n".data(using: .utf8)!)
        body.append("general\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let data = try await send(authKey: authKey) { token in
            var request = URLRequest(url: URL(string: "\(Constants.Sber.apiBase)/files")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = body
            request.timeoutInterval = 60
            return request
        }
        return try GigaChatFileResponse.parse(data).id
    }

    private func performDelete(_ fileId: String, authKey: String) async throws {
        _ = try await send(authKey: authKey) { token in
            var request = URLRequest(
                url: URL(string: "\(Constants.Sber.apiBase)/files/\(fileId)/delete")!
            )
            // Подтверждено в Фазе 3a: POST, а не DELETE-метод.
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 30
            return request
        }
    }

    private func performChat(body: Data, authKey: String) async throws -> String {
        let data = try await send(authKey: authKey) { token in
            var request = URLRequest(url: URL(string: "\(Constants.Sber.apiBase)/chat/completions")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = body
            request.timeoutInterval = 60
            return request
        }
        return try GigaChatChatResponse.parse(data)
    }

    private func performListModels(authKey: String) async throws -> Int {
        let data = try await send(authKey: authKey) { token in
            var request = URLRequest(url: URL(string: "\(Constants.Sber.apiBase)/models")!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 30
            return request
        }
        return try GigaChatModelsResponse.parse(data).count
    }

    /// Общая обвязка: подставляет актуальный токен, повторяет один раз на 401 (принудительно
    /// обновив токен), до `maxRateLimitRetries` раз на 429 (с растущей паузой), 402 — понятная
    /// ошибка "закончился лимит токенов".
    private func send(
        authKey: String,
        makeRequest: @escaping (String) -> URLRequest
    ) async throws -> Data {
        var token = try await SberAuth.shared.accessToken(authKey: authKey)
        var retried401 = false
        var rateLimitRetries = 0

        while true {
            let (data, response) = try await session.data(for: makeRequest(token))
            guard let http = response as? HTTPURLResponse else { throw SberError.noResponse }

            switch http.statusCode {
            case 200...299:
                return data
            case 401 where !retried401:
                retried401 = true
                token = try await SberAuth.shared.forceRefresh(authKey: authKey)
            case 429 where rateLimitRetries < Constants.Sber.maxRateLimitRetries:
                rateLimitRetries += 1
                let delayMs = 1_000 + rateLimitRetries * 500 // 1.5s, затем 2.0s
                try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            case 402:
                throw SberError.tokenExhausted
            default:
                throw SberError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
        }
    }
}

/// Разбор `POST /files` — только `id` (UUID-строка), нужен для `attachments` в чат-запросе.
/// Подтверждено реальным прогоном в Фазе 3a (NOTES.md, раздел 9).
struct GigaChatFileResponse: Equatable {
    let id: String

    enum ParseError: Error, Equatable { case invalidJSON, missingId }

    static func parse(_ data: Data) throws -> GigaChatFileResponse {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }
        guard let id = obj["id"] as? String, !id.isEmpty else {
            throw ParseError.missingId
        }
        return GigaChatFileResponse(id: id)
    }
}

/// Разбор `GET /models` — формат OpenAI-совместимый: `{"data": [{"id": "..."}, ...]}`.
struct GigaChatModelsResponse: Equatable {
    let count: Int

    enum ParseError: Error, Equatable { case invalidJSON }

    static func parse(_ data: Data) throws -> GigaChatModelsResponse {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["data"] as? [[String: Any]] else {
            throw ParseError.invalidJSON
        }
        return GigaChatModelsResponse(count: models.count)
    }
}

/// Разбор `POST /chat/completions` — формат OpenAI-совместимый: `choices[0].message.content`.
enum GigaChatChatResponse {
    enum ParseError: Error, Equatable { case invalidJSON, emptyChoices, missingContent }

    static func parse(_ data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]] else {
            throw ParseError.invalidJSON
        }
        guard let message = choices.first?["message"] as? [String: Any] else {
            throw ParseError.emptyChoices
        }
        guard let content = (message["content"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw ParseError.missingContent
        }
        return content
    }
}
