// OpenVision - YandexSpeechKitProvider.swift
// Пустой каркас будущей интеграции Yandex SpeechKit (STT + TTS) — см. PLAN.md, раздел 7 "Потом".
//
// НЕ реализовано намеренно. Выбор в настройках показан, но помечен «скоро» и недоступен для
// выбора (см. VoiceSettingsView) — этот тип существует только как точка расширения, чтобы
// протоколы STTProvider/TTSProvider были обкатаны на реальном втором движке ещё до реализации.

import Foundation
import AVFoundation

final class YandexSpeechKitProvider: STTProvider {
    var supportsOnDeviceRecognition: Bool { false }

    func prepareRequest(contextualStrings: [String]) -> STTAudioSink {
        NoOpSTTSink()
    }

    func startTask(
        for sink: STTAudioSink,
        resultHandler: @escaping (String?, Bool, Error?) -> Void
    ) {
        // TODO(Yandex SpeechKit): стримить аудио в STT API Яндекса и транслировать результат сюда
        // через resultHandler(text, isFinal, nil); на ошибке — resultHandler(nil, true, error).
        resultHandler(nil, true, YandexSpeechKitError.notImplemented)
    }
}

@MainActor
extension YandexSpeechKitProvider: TTSProvider {
    var isSpeaking: Bool { false }
    var onSpeechStarted: (() -> Void)? {
        get { nil }
        set { }
    }
    var onSpeechEnded: (() -> Void)? {
        get { nil }
        set { }
    }

    // TODO(Yandex SpeechKit): синтез речи через TTS API Яндекса для каждого из методов ниже.
    func speak(_ text: String) {}
    func speakAmbient(_ text: String) {}
    func beginStreaming() {}
    func speakChunk(_ text: String) {}
    func endStreaming() {}
    func stop() {}
}

private final class NoOpSTTSink: STTAudioSink {
    func append(_ buffer: AVAudioPCMBuffer) {}
    func endAudio() {}
    func cancel() {}
}

enum YandexSpeechKitError: LocalizedError {
    case notImplemented

    var errorDescription: String? {
        "Yandex SpeechKit ещё не реализован в этой сборке."
    }
}
