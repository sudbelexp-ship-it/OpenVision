// OpenVision - SberTrustDelegate.swift
// URLSessionDelegate доверяющий корневому сертификату НУЦ Минцифры России для хостов GigaChat.
//
// GigaChat API (*.devices.sberbank.ru) отдаёт цепочку сертификатов от российского удостоверяющего
// центра, которому iOS не доверяет "из коробки" — без этого делегата TLS-хендшейк с GigaChat падает
// даже при NSAllowsArbitraryLoads = true (тот флаг снимает ATS-политику домена, но не саму проверку
// цепочки сертификата на уровне URLSession). Применяется ТОЛЬКО к нужным хостам; для всех остальных —
// стандартная системная проверка, ATS глобально не трогаем.

import Foundation
import Security

final class SberTrustDelegate: NSObject, URLSessionDelegate {

    private let anchorCertificate: SecCertificate?

    override init() {
        self.anchorCertificate = Self.loadAnchorCertificate()
        super.init()
        if anchorCertificate == nil {
            NSLog("[Sber] ВНИМАНИЕ: russian_trusted_root_ca.pem не загружен — запросы к GigaChat завершатся ошибкой TLS")
        }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        guard host.hasSuffix(Constants.Sber.trustedHostSuffix), let anchor = anchorCertificate else {
            // Не хост GigaChat (или сертификат не загрузился) — стандартная системная проверка.
            completionHandler(.performDefaultHandling, nil)
            return
        }

        SecTrustSetAnchorCertificates(serverTrust, [anchor] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, false)

        var evalError: CFError?
        if SecTrustEvaluateWithError(serverTrust, &evalError) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            NSLog("[Sber] проверка сертификата не прошла для %@: %@", host,
                  evalError.map { String(describing: $0) } ?? "unknown")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: - Загрузка сертификата из бандла

    private static func loadAnchorCertificate() -> SecCertificate? {
        guard let url = Bundle.main.url(forResource: "russian_trusted_root_ca", withExtension: "pem"),
              let pemData = try? Data(contentsOf: url),
              let derData = derData(fromPEM: pemData) else {
            return nil
        }
        return SecCertificateCreateWithData(nil, derData as CFData)
    }

    /// PEM = base64(DER) обёрнутый в строки `-----BEGIN/END CERTIFICATE-----`.
    private static func derData(fromPEM pem: Data) -> Data? {
        guard let text = String(data: pem, encoding: .utf8) else { return nil }
        let base64 = text
            .split(separator: "\n")
            .filter { !$0.hasPrefix("-----") }
            .joined()
        return Data(base64Encoded: base64)
    }
}
