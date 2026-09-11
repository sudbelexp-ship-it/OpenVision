// OpenVision - TTSProvider.swift
// Протокол движка синтеза речи — оборачивает уже существующий TTSService (AVSpeechSynthesizer)
// без изменений его внутреннего устройства: сигнатуры методов уже совпадают, поэтому это просто
// объявление соответствия (как AIBackend-конформансы в AIBackendConformances.swift).

import Foundation

@MainActor
protocol TTSProvider: AnyObject {
    var isSpeaking: Bool { get }
    var onSpeechStarted: (() -> Void)? { get set }
    var onSpeechEnded: (() -> Void)? { get set }

    func speak(_ text: String)
    func speakAmbient(_ text: String)
    func beginStreaming()
    func speakChunk(_ text: String)
    func endStreaming()
    func stop()
}

extension TTSService: TTSProvider {}
