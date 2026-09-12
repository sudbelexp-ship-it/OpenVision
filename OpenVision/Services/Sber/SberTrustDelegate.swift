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

    /// Точная причина последнего провала проверки сертификата — единственный способ увидеть, ПОЧЕМУ
    /// не прошла проверка, без Mac/Xcode: `error.localizedDescription` от URLSession здесь всегда
    /// один и тот же generic текст ("A TLS error caused..."), а реальная причина (какой именно шаг
    /// цепочки не сошёлся — просрочен, не хватает промежуточного, не совпадает хост и т.д.) видна
    /// только внутри `SecTrustEvaluateWithError`. GigaChatSettingsView добавляет это к сообщению об
    /// ошибке в UI. Статическое — делегат живёт всё время работы приложения (создаётся один раз
    /// в init() у GigaChatClient/SberAuth, не на каждый запрос), так что это просто "последний раз,
    /// когда наш delegate вообще увидел challenge проверки сертификата", а не состояние инстанса.
    static private(set) var lastTrustEvaluationError: String?

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
            Self.lastTrustEvaluationError = nil
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            // Что именно прислал сервер, помимо ПОЧЕМУ не сошлось — часто это и есть ответ:
            // например, если сервер отдаёт leaf-сертификат от совсем другого промежуточного, чем
            // наш "Russian Trusted Sub CA", то самой ошибки недостаточно, а список subject'ов
            // presented-цепочки показывает это напрямую.
            let presentedChain = (SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate]) ?? []
            let subjects = presentedChain.map { cert -> String in
                (SecCertificateCopySubjectSummary(cert) as String?) ?? "?"
            }.joined(separator: " → ")
            let detail = evalError.map { String(describing: $0) } ?? "unknown"
            Self.lastTrustEvaluationError = "\(detail) | цепочка сервера: \(subjects.isEmpty ? "пусто" : subjects)"
            NSLog("[Sber] проверка сертификата не прошла для %@: %@", host, Self.lastTrustEvaluationError ?? "")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: - Загрузка сертификатов из бандла

    /// Корневой + промежуточный (Sub CA) — на случай, если сервер GigaChat не отдаёт
    /// промежуточный сертификат в цепочке сам (частый случай для сайтов на НУЦ Минцифры).
    private static func loadAnchorCertificates() -> [SecCertificate] {
        ["russian_trusted_root_ca", "russian_trusted_sub_ca"].compactMap { name in
            guard let url = findResourceURL(named: name, extension: "pem"),
                  let pemData = try? Data(contentsOf: url),
                  let der = derData(fromPEM: pemData) else {
                NSLog("[Sber] не найден в бандле: %@.pem", name)
                return nil
            }
            return SecCertificateCreateWithData(nil, der as CFData)
        }
    }

    /// `Bundle.main.url(forResource:withExtension:)` без `subdirectory:` ищет только в корне
    /// бандла — а XcodeGen для одиночного файла вне основной папки таргета (наш случай: сертификаты
    /// лежат в `certs/` на корне репозитория, не в `OpenVision/Resources`) может сохранить
    /// относительный путь и положить файл в подпапку `certs/` ВНУТРИ бандла, а не в корень.
    /// Пробуем по очереди: корень бандла → подпапка "certs" → полный обход бандла по расширению
    /// (страховка на случай, если реальное поведение XcodeGen окажется ещё каким-то третьим).
    private static func findResourceURL(named name: String, extension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "certs") {
            return url
        }
        // Последняя страховка: обходим весь бандл файловой системой напрямую, а не через
        // Bundle-API (чьи допущения о плоской/вложенной структуре мы, похоже, угадали неверно —
        // см. комментарий выше). Бандл небольшой (одно приложение), полный обход недорог и
        // выполняется один раз при создании делегата, не на каждый запрос.
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: Bundle.main.bundleURL, includingPropertiesForKeys: nil
        ) else { return nil }
        for case let url as URL in enumerator
        where url.pathExtension == ext && url.deletingPathExtension().lastPathComponent == name {
            return url
        }
        return nil
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
