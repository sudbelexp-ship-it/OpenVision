// OpenVision - Constants.swift
// App-wide constants

import Foundation

enum Constants {
    // MARK: - OpenClaw

    enum OpenClaw {
        /// Maximum reconnection attempts before giving up
        static let maxReconnectAttempts = 12

        /// Initial reconnection delay in seconds
        static let initialReconnectDelay: TimeInterval = 1.0

        /// Maximum reconnection delay in seconds
        static let maxReconnectDelay: TimeInterval = 30.0

        /// Heartbeat ping interval in seconds
        static let heartbeatInterval: TimeInterval = 20.0

        /// Pong timeout in seconds
        static let pongTimeout: TimeInterval = 10.0
    }

    // MARK: - Gemini Live

    enum GeminiLive {
        /// WebSocket endpoint for Gemini Live API
        static let websocketEndpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

        /// Model name (native audio model for real-time voice + video)
        static let modelName = "models/gemini-2.5-flash-native-audio-preview-12-2025"

        /// Input audio sample rate (Hz)
        static let inputSampleRate = 16000

        /// Output audio sample rate (Hz)
        static let outputSampleRate = 24000

        /// Audio chunk size in milliseconds
        static let audioChunkMs = 100

        /// JPEG quality for video frames (0.0 - 1.0)
        static let videoJPEGQuality: CGFloat = 0.5

        /// Default video frame rate (fps)
        static let defaultVideoFPS = 1
    }

    // MARK: - OpenAI Realtime

    enum OpenAIRealtime {
        /// Path appended to the OpenAI base URL to reach the Realtime WebSocket.
        /// The base URL's https:// scheme is rewritten to wss:// at connect time.
        static let websocketPath = "/realtime"

        /// Realtime model id (GA). Override in settings for a pinned snapshot.
        static let modelName = "gpt-realtime"

        /// Default realtime voice.
        static let voice = "marin"

        /// Input audio sample rate (Hz). OpenAI Realtime uses 24 kHz PCM16 mono.
        static let inputSampleRate = 24000

        /// Output audio sample rate (Hz). OpenAI Realtime emits 24 kHz PCM16 mono.
        static let outputSampleRate = 24000

        /// JPEG quality for video frames sent as image messages (0.0 - 1.0)
        static let videoJPEGQuality: CGFloat = 0.5

        /// Default video frame rate (fps)
        static let defaultVideoFPS = 1
    }

    // MARK: - Voice

    enum Voice {
        /// Default wake word (см. PLAN.md, Фаза 4 — распознавание речи переведено на ru-RU).
        static let defaultWakeWord = "Окей, очки"

        /// Локаль распознавания и синтеза речи — фиксированное решение (PLAN.md, раздел 0).
        static let speechLocaleIdentifier = "ru-RU"

        /// Фразы для контекстной подсказки распознавателю (SFSpeechAudioBufferRecognitionRequest
        /// .contextualStrings) — человекочитаемые варианты фразы активации по умолчанию.
        static let wakeWordContextualPhrases = ["Окей, очки", "Окей очки", "Очки"]

        /// Варианты распознавания фразы активации по умолчанию ("Окей, очки") для сопоставления
        /// с транскриптом — подобраны по фонетическому сходству, без проверки на реальном железе
        /// (см. NOTES.md, риск №5). Ожидаемо потребуют уточнения после теста на очках.
        static let wakeWordVariations: [String] = [
            "окей очки", "окей, очки", "окей очке", "окей очков",
            "ок очки", "ok очки", "хоккей очки", "какие очки", "эй очки"
        ]

        /// Стоп-слова ("Окей, очки, стоп") — распознаются ТОЛЬКО вместе с фразой активации
        /// (см. VoiceCommandService.isStopPhrase), поэтому список короткий и не пересекается
        /// с обычной речью.
        static let stopWords: [String] = ["стоп", "хватит", "тихо", "замолчи", "отмена", "прекрати"]

        /// Wake word cooldown to prevent double-detection (seconds)
        static let wakeWordCooldown: TimeInterval = 0.8

        /// Command capture timeout (seconds)
        static let commandTimeout: TimeInterval = 10.0

        /// Silence timeout to end command capture (seconds).
        ///
        /// FALLBACK ONLY — used when acoustic VAD is unavailable. It measures "no new transcript
        /// for N seconds", not silence, and SFSpeechRecognizer emits partials in bursts with ~1s
        /// gaps mid-sentence, so it has to stay long or it cuts the user off. With VAD the turn is
        /// committed from real end-of-speech plus `vadCommitGrace` instead.
        static let silenceTimeout: TimeInterval = 4.0

        /// Extra wait after VAD reports end-of-speech before committing the turn (seconds).
        ///
        /// Short on purpose: Silero has already absorbed ~0.75s of silence hysteresis before it
        /// fires, and speech resuming inside this window cancels the commit. This buys a little
        /// room for the recognizer's final partial to land, which trails the audio slightly.
        static let vadCommitGrace: TimeInterval = 0.35

        /// Default conversation timeout (seconds)
        static let conversationTimeout: TimeInterval = 30.0
    }

    // MARK: - Audio

    enum Audio {
        /// PCM format: 16-bit signed integer
        static let pcmBitDepth = 16

        /// Mono channel count
        static let monoChannels = 1

        /// Audio buffer size in samples
        static let bufferSize = 1024
    }

    // MARK: - Camera

    enum Camera {
        /// Maximum photo dimension for compression
        static let maxPhotoDimension: CGFloat = 512

        /// JPEG compression quality for photos
        static let photoJPEGQuality: CGFloat = 0.5

        /// Photo capture timeout (seconds)
        static let captureTimeout: TimeInterval = 10.0
    }

    // MARK: - Sber (GigaChat)

    enum Sber {
        /// GigaChat OAuth (Authorization Key -> Access Token).
        static let oauthURL = "https://ngw.devices.sberbank.ru:9443/api/v2/oauth"
        /// GigaChat REST API base (files, chat/completions).
        static let apiBase = "https://gigachat.devices.sberbank.ru/api/v1"
        /// Scope for физлиц (Freemium) — см. PLAN.md.
        static let scope = "GIGACHAT_API_PERS"
        /// Хост, к которому применяется доверие сертификату НУЦ Минцифры (SberTrustDelegate).
        static let trustedHostSuffix = ".devices.sberbank.ru"

        /// Кадр перед загрузкой: длинная сторона не больше этого значения (без апскейла),
        /// короткая — по возможности не меньше `minShortSide` (см. PLAN.md, Фаза 3b).
        static let maxLongSide: CGFloat = 1600
        static let minShortSide: CGFloat = 800
        static let jpegQuality: CGFloat = 0.8

        /// Токен обновляется заранее, а не строго по истечении.
        static let tokenRefreshMarginMs: Int64 = 60_000
        /// Максимум повторов при HTTP 429, с растущей паузой (см. `GigaChatClient`).
        static let maxRateLimitRetries = 2
    }

    // MARK: - UI

    enum UI {
        /// Animation duration for state transitions
        static let animationDuration: TimeInterval = 0.3

        /// Debounce interval for search/filter
        static let debounceInterval: TimeInterval = 0.3
    }

    // MARK: - Storage

    enum Storage {
        /// Settings file name
        static let settingsFileName = "settings.json"

        /// Conversations file name
        static let conversationsFileName = "conversations.json"

        /// Maximum conversations to keep
        static let maxConversations = 100

        /// Conversation inactivity timeout before starting new (seconds)
        static let conversationInactivityTimeout: TimeInterval = 300 // 5 minutes
    }
}
