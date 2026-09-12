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

    private let anchorCertificates: [SecCertificate]

    override init() {
        self.anchorCertificates = Self.loadAnchorCertificates()
        super.init()
        if anchorCertificates.isEmpty {
            NSLog("[Sber] ВНИМАНИЕ: сертификаты НУЦ Минцифры не загружены из бандла — запросы к GigaChat завершатся ошибкой TLS")
        }
    }

    /// Сколько сертификатов НУЦ Минцифры реально нашлось в бандле (ожидается 2: корневой +
    /// промежуточный) — для экрана «Диагностика», единственного способа проверить это без
    /// Mac/Xcode. Не зависит от того, создавался ли уже реальный делегат.
    static func bundledCertificateCount() -> Int {
        loadAnchorCertificates().count
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
        guard host.hasSuffix(Constants.Sber.trustedHostSuffix), !anchorCertificates.isEmpty else {
            // Не хост GigaChat (или сертификаты не загрузились) — стандартная системная проверка.
            completionHandler(.performDefaultHandling, nil)
            return
        }

        SecTrustSetAnchorCertificates(serverTrust, anchorCertificates as CFArray)
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

    // MARK: - Загрузка сертификатов из бандла

    /// Корневой + промежуточный (Sub CA) — на случай, если сервер GigaChat не отдаёт
    /// промежуточный сертификат в цепочке сам (частый случай для сайтов на НУЦ Минцифры).
    private static func loadAnchorCertificates() -> [SecCertificate] {
        ["russian_trusted_root_ca", "russian_trusted_sub_ca"].compactMap { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "pem"),
                  let pemData = try? Data(contentsOf: url),
                  let der = derData(fromPEM: pemData) else {
                NSLog("[Sber] не найден в бандле: %@.pem", name)
                return nil
            }
            return SecCertificateCreateWithData(nil, der as CFData)
        }
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
