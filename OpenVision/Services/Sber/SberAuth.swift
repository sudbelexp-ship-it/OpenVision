// OpenVision - SberAuth.swift
// OAuth2 client-credentials для GigaChat: Authorization Key -> Access Token.
//
// Устройство GigaChat отличается от остальных бэкендов (OpenAI/Gemini/OpenClaw используют
// статический ключ): здесь ключ обменивается на короткоживущий (~30 мин) access token, который
// нужно обновлять заранее. Это единственное место в приложении, которое это делает — актор, чтобы
// параллельные вызовы sendMessage не запускали обновление токена гонкой.

import Foundation

actor SberAuth {
    static let shared = SberAuth()

    private struct Token {
        let accessToken: String
        /// Абсолютная метка истечения, миллисекунды Unix-эпохи (см. NOTES.md, раздел 9 —
        /// подтверждено реальным прогоном Фазы 3a: это НЕ длительность в секундах).
        let expiresAtMs: Int64
    }

    private var current: Token?
    private let session: URLSession

    private init() {
        session = URLSession(configuration: .default, delegate: SberTrustDelegate(), delegateQueue: nil)
    }

    /// Действующий access token; обновляет заранее (см. `Constants.Sber.tokenRefreshMarginMs`).
    func accessToken(authKey: String) async throws -> String {
        if let token = current, !isExpiringSoon(token) {
            return token.accessToken
        }
        return try await refresh(authKey: authKey)
    }

    /// Принудительное обновление — вызывается GigaChatClient при получении 401 от API.
    func forceRefresh(authKey: String) async throws -> String {
        try await refresh(authKey: authKey)
    }

    private func isExpiringSoon(_ token: Token) -> Bool {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return token.expiresAtMs - nowMs < Constants.Sber.tokenRefreshMarginMs
    }

    private func refresh(authKey: String) async throws -> String {
        guard !authKey.isEmpty else { throw SberError.notConfigured }
        guard let url = URL(string: Constants.Sber.oauthURL) else { throw SberError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Basic \(authKey)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "RqUID")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = "scope=\(Constants.Sber.scope)".data(using: .utf8)
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SberError.noResponse }
        guard (200...299).contains(http.statusCode) else {
            throw SberError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let parsed = try SberOAuthResponse.parse(data)
        current = Token(accessToken: parsed.accessToken, expiresAtMs: parsed.expiresAtMs)
        return parsed.accessToken
    }
}

/// Разбор ответа `POST /api/v2/oauth`, вынесен отдельно от сетевого кода, чтобы юнит-тесты могли
/// проверить его на реальном JSON из Фазы 3a (NOTES.md, раздел 9) без ключей/токенов.
struct SberOAuthResponse: Equatable {
    let accessToken: String
    let expiresAtMs: Int64

    enum ParseError: Error, Equatable {
        case invalidJSON
        case missingAccessToken
        case missingExpiresAt
    }

    static func parse(_ data: Data) throws -> SberOAuthResponse {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }
        guard let accessToken = obj["access_token"] as? String, !accessToken.isEmpty else {
            throw ParseError.missingAccessToken
        }
        // expires_at — число (не строка), миллисекунды Unix-эпохи.
        guard let expiresAtMs = (obj["expires_at"] as? NSNumber)?.int64Value else {
            throw ParseError.missingExpiresAt
        }
        return SberOAuthResponse(accessToken: accessToken, expiresAtMs: expiresAtMs)
    }
}

enum SberError: LocalizedError, Equatable {
    case notConfigured
    case noResponse
    case invalidResponse
    case http(Int, String)
    case tokenExhausted

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "GigaChat не настроен. Добавьте Authorization Key в настройках."
        case .noResponse:
            return "Нет ответа от GigaChat."
        case .invalidResponse:
            return "Некорректный ответ GigaChat."
        case .http(let code, let detail):
            return "Ошибка GigaChat (HTTP \(code))\(detail.isEmpty ? "" : ": \(detail)")"
        case .tokenExhausted:
            return "Закончился лимит токенов GigaChat."
        }
    }
}
