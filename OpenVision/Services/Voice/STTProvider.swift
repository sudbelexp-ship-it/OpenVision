// OpenVision - STTProvider.swift
// Протокол движка распознавания речи + текущая Apple-реализация (SFSpeechRecognizer).
//
// VoiceCommandService сам управляет AVAudioEngine, VAD и всей логикой wake word/перезапусков —
// это НЕ трогаем (сложная, проверенная временем логика). Абстракция — только вокруг "кто слушает
// аудио-буферы и превращает их в текст", ровно та часть, которая отличалась бы у Yandex SpeechKit.
//
// Двухфазный API (prepareRequest → startTask) сохраняет точный порядок исходного кода: буферы от
// таппа AVAudioEngine должны накапливаться уже ДО того, как аудио-движок запущен, а сама задача
// распознавания стартует ПОСЛЕ — это осознанный порядок из оригинального кода (см. комментарий
// "Start audio engine first (before recognition task)" в VoiceCommandService).

import Foundation
import Speech
import AVFoundation

/// Движок распознавания речи. `nonisolated` — колбэки распознавателя приходят на произвольном
/// потоке, вызывающая сторона (VoiceCommandService) сама переходит на MainActor внутри них.
protocol STTProvider: AnyObject {
    /// Поддерживает ли текущая локаль офлайн (on-device) распознавание прямо сейчас.
    var supportsOnDeviceRecognition: Bool { get }

    /// Подготовить новый запрос распознавания (задача ещё НЕ запущена) и вернуть приёмник
    /// аудио-буферов. `contextualStrings` — фразы, к которым распознаватель более чувствителен
    /// (в первую очередь — фраза активации).
    func prepareRequest(contextualStrings: [String]) -> STTAudioSink

    /// Запустить задачу распознавания для приёмника, подготовленного `prepareRequest`.
    /// `resultHandler` вызывается на каждое событие — как оригинальный
    /// `SFSpeechRecognitionTask` resultHandler: с текстом (или nil, если это ошибка без текста),
    /// признаком финальности и опциональной ошибкой.
    func startTask(
        for sink: STTAudioSink,
        resultHandler: @escaping (_ text: String?, _ isFinal: Bool, _ error: Error?) -> Void
    )
}

/// Приёмник аудио-буферов одного запроса распознавания. VoiceCommandService продолжает сам
/// владеть AVAudioEngine — просто отдаёт буферы сюда вместо прямого
/// `SFSpeechAudioBufferRecognitionRequest.append(...)`.
protocol STTAudioSink: AnyObject {
    func append(_ buffer: AVAudioPCMBuffer)
    func endAudio()
    /// Отменяет задачу распознавания и завершает запрос — объединяет то, что в оригинальном коде
    /// было двумя отдельными вызовами (`recognitionTask?.cancel()` + `recognitionRequest?.endAudio()`),
    /// которые всегда происходили вместе.
    func cancel()
}

// MARK: - Apple (SFSpeechRecognizer)

final class AppleSTTProvider: STTProvider {
    private let recognizer: SFSpeechRecognizer?

    init(locale: Locale) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    var supportsOnDeviceRecognition: Bool {
        recognizer?.supportsOnDeviceRecognition ?? false
    }

    /// Прайм для короткой фразы + фразы активации: `.search` (короткая фраза) надёжнее
    /// `.dictation` (длинная речь) для "фраза активации + команда". `contextualStrings` — главный
    /// фактор надёжного распознавания фразы активации через некачественный Bluetooth-HFP микрофон
    /// очков (8 кГц).
    func prepareRequest(contextualStrings: [String]) -> STTAudioSink {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .search
        request.contextualStrings = contextualStrings
        // Офлайн-распознавание, если локаль его поддерживает; иначе — серверное Apple (см. PLAN.md).
        if supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        return AppleSTTSession(request: request)
    }

    func startTask(
        for sink: STTAudioSink,
        resultHandler: @escaping (String?, Bool, Error?) -> Void
    ) {
        guard let session = sink as? AppleSTTSession else { return }
        session.task = recognizer?.recognitionTask(with: session.request) { result, error in
            resultHandler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error)
        }
    }
}

private final class AppleSTTSession: STTAudioSink {
    let request: SFSpeechAudioBufferRecognitionRequest
    var task: SFSpeechRecognitionTask?

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
    func endAudio() { request.endAudio() }

    func cancel() {
        task?.cancel()
        request.endAudio()
    }
}
