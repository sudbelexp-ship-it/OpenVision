# NOTES.md — разведка перед добавлением бэкенда GigaChat и русской локализации

> Документ подготовлен как чистая разведка (без изменений кода) по репозиторию `D:\OpenVision`
> (форк OpenVision — iOS-приложение для очков Meta Ray-Ban). Дата: 2026-09-11.

---

## 1. Карта проекта

Архитектура — MVVM + "протокольные швы" (protocol seams), как явно описано в `docs/architecture.md`.

```
OpenVision/
├── App/                 Точка входа (OpenVisionApp), обработка URL-колбэков
├── Config/              Constants.swift (константы) + Config.swift (опциональные дефолт-ключи,
│                         генерируется из Config.swift.example, в git не коммитится)
├── Managers/             Синглтоны уровня приложения:
│   ├── SettingsManager.swift   — JSON-персистентность настроек (Documents/settings.json)
│   ├── GlassesManager.swift    — обёртка над Meta DAT SDK (регистрация, стрим, фото)
│   └── ConversationManager.swift — история диалогов
├── Models/
│   ├── AppSettings.swift  — модель настроек + enum AIBackendType + enum TTSEngineType
│   └── Conversation.swift
├── Services/             Один каталог на домен:
│   ├── AIBackend/        AIBackendProtocol.swift (протокол + реестр) + AIBackendConformances.swift
│   │                     (адаптеры) + OpenAIService.swift (эталонная облачная реализация)
│   ├── AppleFoundation/  Apple Intelligence backend (on-device, iOS 26+)
│   ├── GeminiLive/       Gemini Live WebSocket backend (GeminiLiveService, GeminiVisionService)
│   ├── GemmaLocal/       On-device MLX модели (Gemma 4, SmolVLM2, FastVLM, Qwen)
│   ├── LocalAgent/       Общий "роутинг-мозг" для on-device моделей (JSON-in-text)
│   ├── OpenAIRealtime/   OpenAI Realtime (живое видео/аудио)
│   ├── OpenClaw/         OpenClaw agentic backend (WebSocket)
│   ├── NativeTools/      Продуктивити-инструменты (таймер, календарь, заметки, …)
│   ├── TTS/              TTSService.swift (Apple AVSpeechSynthesizer) + KokoroTTSService.swift
│   │                     (on-device нейросетевой голос через MLX)
│   ├── Voice/            VoiceCommandService.swift (wake word + Apple Speech STT) +
│   │                     SpeechActivityDetector.swift (акустический VAD, Silero через FluidAudio)
│   ├── Audio/             AudioSessionManager, AudioCaptureService, AudioPlaybackService, SoundService
│   ├── Vision/            Распознавание лиц (Apple Vision)
│   └── Web/               Веб-поиск (Tavily / DuckDuckGo)
├── Views/                 SwiftUI. Views — только рендер, ViewModel — вся оркестрация.
│   ├── VoiceAgent/        VoiceAgentView + VoiceAgentViewModel (главный экран, вся логика)
│   ├── Settings/          Экраны настроек (по одному на бэкенд/фичу)
│   ├── History/           История переписки
│   └── Components/        Переиспользуемые UI-компоненты
└── Utilities/             Хелперы
OpenVisionTests/          Юнит-тесты чистой логики (без железа/сети/моделей)
```

Ключевые паттерны (см. `docs/architecture.md`):
- **@MainActor** почти везде; все менеджеры и сервисы изолированы на главном акторе.
- **Синглтоны** (`Service.shared`), которыми управляет `VoiceAgentViewModel`.
- **Callbacks**, а не Combine, для событийной модели сервисов.
- **Протокольные швы**: `AIBackend` (диалоговые бэкенды), `LocalTextLLM` (on-device роутинг),
  `NativeTool` (инструменты), `LiveVideoService` (реалтайм-бэкенды видео/аудио).

---

## 2. Точки интеграции нового бэкенда (GigaChat)

Файл `docs/architecture.md` прямо описывает 4 шага добавления бэкенда — они и есть план для GigaChat:

1. **Написать сервис** — новый файл, например `OpenVision/Services/GigaChat/GigaChatService.swift`
   (по аналогии с `OpenVision/Services/AIBackend/OpenAIService.swift`, 212 строк — эталон "простого"
   облачного REST-бэкенда: singleton `.shared`, `@Published isConnected`, `sendMessage(_:imageData:)`,
   системный промпт, цикл tool-calling, парсинг ответа, `enum ...Error: LocalizedError`).
2. **Конформировать к протоколу** `AIBackend` в
   `OpenVision/Services/AIBackend/AIBackendConformances.swift` (добавить блок
   `extension GigaChatService: AIBackend { var backendType: AIBackendType { .gigaChat }; var
   supportsImageInput: Bool { true } }` — тонкий адаптер, как у OpenClaw/OpenAI/Gemma, если сигнатуры
   совпадают "из коробки").
3. **Добавить кейс в enum** `AIBackendType` — файл `OpenVision/Models/AppSettings.swift`, строки 7-48
   (плюс `displayName`, `description`, `icon`) — и **одну строку** в `AIBackendRegistry.backend(for:)`
   в `OpenVision/Services/AIBackend/AIBackendProtocol.swift` (строки 43-56):
   ```swift
   case .gigaChat: return GigaChatService.shared
   ```
4. **Если нужен function-calling** (таймеры/календарь/заметки) — подключить
   `NativeToolRegistry.shared` (см. как это делает `OpenAIService.swift`, строки 76-139: секция
   `web_search` tool + `NativeToolRegistry.shared.openAISpecs`, цикл `maxIterations = 4`).

### Модель настроек и хранение ключа
- `OpenVision/Models/AppSettings.swift` — добавить поля вида `var gigaChatAuthKey: String = ""`,
  `var gigaChatScope: String = "GIGACHAT_API_PERS"` (Sber использует OAuth2 client-credentials:
  Authorization Key → access token, а не прямой API-ключ как у OpenAI — это архитектурно ДРУГАЯ
  схема авторизации, потребует отдельного OAuth-клиента внутри `GigaChatService`) + computed
  `var isGigaChatConfigured: Bool` + строку в `isCurrentBackendConfigured` (switch, строки 205-213).
- **ВАЖНО:** ключи сейчас хранятся в **обычном JSON-файле**, не в Keychain (см. раздел 8) — так что
  паттерн для GigaChat будет тем же, что и для остальных (не нужно городить отдельное
  Keychain-хранилище — но если решите делать по уму, это будет архитектурным отступлением от
  остальных бэкендов, придётся мигрировать все разом или тащить два хранилища).

### UI настроек
- `OpenVision/Views/Settings/AIBackendSettingsView.swift` — добавить пункт выбора бэкенда в секцию
  "Choose Your AI" (цикл по `AIBackendType.allCases`, работает автоматически после добавления кейса
  в enum) и `NavigationLink` на новый экран конфигурации в секции "Configuration" (строки 50-102).
- Новый экран `OpenVision/Views/Settings/GigaChatSettingsView.swift` — калька с
  `OpenAISettingsView.swift` (107 строк: `@State` поля → `onAppear` подгружает из
  `settingsManager.settings` → `onDisappear`/кнопка "Save" сохраняет через `saveNow()`).

### project.yml
- Никаких новых SPM-зависимостей не требуется, если GigaChat дергается через обычный
  `URLRequest`/`URLSession` (как OpenAI). Но нужно учесть self-signed сертификат Минцифры России
  (GigaChat API по умолчанию требует либо отключения проверки сертификата, либо установки
  российского корневого сертификата НУЦ Минцифры) — это повлияет на `URLSession`-конфигурацию
  (`NSAppTransportSecurity` уже настроен permissive: `NSAllowsArbitraryLoads = true` в Info.plist,
  так что на уровне ATS проблем не будет, но сама валидация TLS-цепочки на устройстве без
  установленного российского корневого сертификата, скорее всего, будет падать — нужен кастомный
  `URLSessionDelegate` с pinning/доверием к нужному CA, либо предложить пользователю установить
  сертификат вручную).

---

## 3. STT / TTS / Wake Word — как устроено сейчас

**Абстракции НЕТ.** Голосовые сервисы жёстко привязаны к конкретным Apple API, протокола
"SpeechRecognizer" или "TTSEngine" не существует — придётся вводить его с нуля, если понадобится
переключаемый бэкенд (например, чтобы в будущем воткнуть Yandex SpeechKit STT наравне с Apple Speech).

### STT (распознавание речи)
- Файл: `OpenVision/Services/Voice/VoiceCommandService.swift`, строка 87:
  ```swift
  private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
  ```
  **Локаль жёстко зашита как `en-US`** — единственная точка, куда нужно завести
  `Locale(identifier: "ru-RU")` (или сделать настраиваемой из `AppSettings`).
- Wake word и стоп-фразы тоже **захардкожены на английском** прямо в коде (не в конфиге):
  массивы вариантов `["ok vision", "okay vision", "hey vision", "hi vision", "a vision",
  "heavy vision", "have vision", "obey vision", "oak vision"]` встречаются в 4 местах:
  `configureRecognitionRequest` (строка 294), `detectWakeWord` (673-689),
  `wakeWordAtStart` (649-654), `extractCommandAfterWakeWord` (703-708), `handleCommandComplete`
  (752). Пользовательская фраза (`SettingsManager.shared.settings.wakeWord`, дефолт `"Ok Vision"`
  в `Constants.Voice.defaultWakeWord`) добавляется в начало списка, но англоязычные "мисрекогнишны"
  всегда в списке — для русской фразы активации эти списки нужно будет либо параметризовать по
  локали, либо дублировать русским набором вариантов ("окей вижен" и т.п. не подходят по смыслу —
  тут потребуется придумать русскую фразу-триггер и её типичные искажения распознавания).
- `SpeechActivityDetector.swift` (акустический VAD, Silero через пакет `FluidAudio`) —
  языконезависим (просто определяет "тишина/не тишина" по звуку), русской локализации не касается.

### TTS (озвучка)
- Файл: `OpenVision/Services/TTS/TTSService.swift`, строка 50:
  ```swift
  return AVSpeechSynthesisVoice(language: "en-US")
  ```
  Дефолтный голос — `en-US`; пользователь может выбрать любой установленный голос через
  `selectedVoiceIdentifier` (экран `OpenVision/Views/Settings/VoiceSelectionView.swift`,
  `TTSService.availableVoices(for:)` фильтрует по префиксу языка, по умолчанию `"en"` —
  **для русского нужно передавать `"ru"`**). Технически Apple system voices поддерживают русский
  "из коробки" (iOS ships `ru-RU` voices), так что переключение на русский **не требует новых
  зависимостей** — только правки UI/логики выбора языка.
- `OpenVision/Services/TTS/KokoroTTSService.swift` (on-device нейро-TTS, MLX) — **жёстко только
  английский**: строки 122, 223, 268 —
  ```swift
  let language: Language = voice.first == "b" ? .enGB : .enUS
  ```
  Модель Kokoro-82M (вендорится в `Vendor/kokoro-ios`) в текущей интеграции поддерживает только
  `enUS`/`enGB` — для русского Kokoro либо не подойдёт вовсе (модель не обучена на русском /
  библиотека `MisakiSwift` — G2P-фронтенд — заточена под английскую фонетику), либо потребует
  отдельной русскоязычной TTS-модели и нового вендор-пакета. Это **не тривиальная задача**, в
  отличие от Apple TTS.

### Итог по локали
Единственный реально "дешёвый" путь к русской озвучке/распознаванию — Apple Speech (STT) +
Apple AVSpeechSynthesizer (TTS), оба поддерживают `ru-RU` на уровне ОС. Kokoro (нейро-TTS) и
хардкод wake-word листов — места, требующие содержательной доработки, а не просто конфигурации.

---

## 4. Meta DAT SDK — версия и требования

- **Расхождение в документации** (см. раздел 7 "Риски"): `README.md` (строка 135) и `SETUP.md`
  (строка 135) в тексте утверждают "pinned to `0.4.0`", но **фактически закреплённая версия —
  `0.9.0`**, подтверждено в трёх местах:
  - `project.yml`, строки 106-117: `exactVersion: "0.9.0"`.
  - `OpenVision.xcodeproj/project.pbxproj`, строка 1176: `version = 0.9.0;`.
  - Комментарий в `project.yml` объясняет, почему именно 0.9.0: это "camera-consolidation API"
    (`DeviceSession.addCamera(config:) -> Camera -> camera.stream`, старые `StreamSession`/
    `addStream` убраны), требует **iOS 17.2+** на уровне SDK (сам проект целится в iOS 18.0 из-за
    on-device Gemma 4 — см. `project.yml` строки 4-8).
  - Пин версии **намеренный и жёсткий** (`exactVersion`, не `from:`): комментарий предупреждает,
    что SDK переписывает API почти в каждом релизе (0.6.0 сделал `StreamSession.init`
    недоступным, 0.7.0 переименовал тип). GigaChat-интеграция сама по себе SDK не касается, но
    если параллельно будут трогать `GlassesManager.swift`, версию SDK менять не стоит без
    отдельной регрессии на Gen 1/2 очках (это прямо указано в комментарии `project.yml`).
- Требуемые SPM-продукты: `MWDATCore`, `MWDATCamera` (см. `project.yml`, target `OpenVision`,
  строки 70-73).
- Минимальный iOS для самого приложения — **18.0** (`project.yml`, deploymentTarget), но это
  из-за MLX/Gemma 4, а не из-за DAT SDK (который требует только 17.2+ по комментарию в project.yml;
  официальная документация Meta, полученная через WebFetch, называет ещё более низкую планку —
  **iOS 15.2+ / Xcode 14.0+** — как общий минимум для toolkit'а, но это относится к более ранним
  версиям SDK, а не к закреплённой здесь 0.9.0).

---

## 5. Developer Mode без полной регистрации + Mock Device Kit

Официальный репозиторий: https://github.com/facebook/meta-wearables-dat-ios
Документация: https://wearables.developer.meta.com/docs/

### Info.plist / ключи MWDAT
Подтверждено и репозиторием, и текущим `OpenVision/Resources/Info.plist` (строки 145-156), 4 ключа
внутри словаря `MWDAT`:

| Ключ | Источник значения | Обязателен без публикации приложения? |
|---|---|---|
| `MetaAppID` | Генерируется в Wearables Developer Center при создании app | Да (кроме отдельного случая Developer Mode, см. ниже) |
| `ClientToken` | Автогенерируется там же, формат `AR\|<AppID>\|<hash>` | Да |
| `TeamID` | Apple Developer Team ID (Xcode → Signing & Capabilities) | Да |
| `AppLinkURLScheme` | Произвольная custom URL scheme приложения, формат `"myapp://"` | Да |

Официальная документация (страница build-integration-ios) содержит важную фразу:
**"Unless using Developer Mode, set this key using the ID from the app registered in Wearables
Developer Center"** — то есть Developer Mode **не отменяет необходимость создать приложение и
получить MetaAppID/ClientToken**, он лишь освобождает от процедуры *публикации/ревью* приложения
Meta (см. цитату ниже). Полностью "без регистрации" (без захода на
wearables.developer.meta.com вообще) поднять реальные очки, по всей видимости, **нельзя** — это
подтверждает и уже существующий `SETUP.md` в проекте (шаги 2.4-2.5: создать аккаунт/организацию/
приложение на wearables.developer.meta.com, затем включить Developer Mode в приложении Meta AI).

Что именно даёт "Developer Mode" (со страницы getting-started-toolkit, дословно по WebFetch):
> "Enable developer mode in the Meta AI app. Developer mode allows your unpublished app to
> register and interact with your AI glasses without the need to submit it for publishing review."

Т.е. Developer Mode = обходит только "publishing review" Meta (по умолчанию сборки нельзя
распространять иначе как через invite-only release channels, до 100 тестеров — это уже
зафиксировано в существующем `SETUP.md`, строки 5-18). Регистрация приложения (бесплатная) всё
равно нужна для получения `MetaAppID`/`ClientToken`.

### Mock Device Kit (тестирование без реальных очков)
Подтверждено официальной документацией (страницы mock-device-kit, testing-mdk-ios):
- Это часть toolkit'а, позволяющая **полностью симулировать** сессию устройства, permissions и
  видеопоток без физических очков — "simulates the full device session, permissions, and camera
  stream".
- Использование (из документации, пример на CameraAccess sample-приложении):
  1. Включить MockDeviceKit (debug-иконка "ladybug" → "Enable MockDeviceKit").
  2. "Pair RayBan Meta" — создать mock-устройство, переключить его состояния Power/Don (надето).
  3. Указать источник видео: фронтальная/задняя камера телефона или видеофайл.
  4. Симулировать касания (tap, tap-and-hold) на карточке устройства.
  5. Нажать "Start streaming" в приложении — увидеть симулированный поток.
- **В текущем коде OpenVision (`GlassesManager.swift`) интеграции с MockDeviceKit НЕТ** — весь
  код работает через реальный `Wearables.shared`, `DeviceSession`, `Camera` (SDK 0.9.0 API). Из
  документации не удалось подтвердить, нужен ли для MockDeviceKit тот же валидный
  `MetaAppID`/`ClientToken` в Info.plist, или он работает поверх "пустых"/тестовых значений —
  **это открытый вопрос**, требующий отдельной проверки в самой SDK (например, через sample-проект
  `samples/` в репозитории `meta-wearables-dat-ios`, который не был клонирован в рамках этой
  разведки — только просмотрен через GitHub-страницу).
- README проекта уже упоминает частичный fallback без очков: "iPhone camera works as a fallback"
  (используется `GlassesSettingsView.swift` / переключатель "Use iPhone Camera" — это НЕ
  MockDeviceKit, а полностью отдельный путь, минующий Meta DAT SDK целиком).

---

## 6. Путь фото от очков до облачного бэкенда

Полная цепочка (проверено чтением кода):

1. **Источник**: `OpenVision/Managers/GlassesManager.swift`, метод `capturePhoto()` (строки
   280-295) — вызывает `camera?.stream.capturePhoto(format: .jpeg)` (не бросает исключение с
   версии SDK 0.9.0; ошибки приходят через `errorPublisher`).
2. **Приём**: `setupStreamListeners`, `photoDataPublisher.listen` (строки 357-364) — получает
   `photoData.data` (тип **`Data`**, JPEG), сохраняет в `@Published var lastPhotoData: Data?` и
   вызывает колбэк `onPhotoCaptured: ((Data) -> Void)?`.
3. **Оркестрация**: `OpenVision/Views/VoiceAgent/VoiceAgentViewModel.swift`,
   `capturePhotoFromGlasses()` (строки 1909-1927) — поллит `glassesManager.lastPhotoData` до 5
   секунд, возвращает `Data?`.
4. **Диспетчеризация в бэкенд** (строка 1843, общая для всех бэкендов через протокол):
   ```swift
   try await backend.sendMessage(prompt, imageData: backend.supportsImageInput ? imageData : nil)
   ```
   т.е. **единая точка входа** — сигнатура протокола `AIBackend.sendMessage(_:imageData:)` из
   `OpenVision/Services/AIBackend/AIBackendProtocol.swift` (строка 26). Ровно ту же сигнатуру
   должен принять `GigaChatService`.
5. **Приём на стороне облачного клиента** (образец —
   `OpenVision/Services/AIBackend/OpenAIService.swift`, строки 34-56):
   ```swift
   func sendMessage(_ text: String, imageData: Data? = nil) async throws {
       ...
       if let imageData {
           let dataURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
           userContent = [
               ["type": "text", "text": text...],
               ["type": "image_url", "image_url": ["url": dataURL]]
           ]
       }
   ```
   OpenAI получает **сырой `Data` (JPEG)** и сам кодирует в base64 data-URL перед отправкой в
   `messages` (формат Chat Completions). Для GigaChat нужно свериться с форматом Sber API для
   мультимодальных запросов (GigaChat Vision/загрузка файлов через отдельный `/files` эндпоинт с
   `purpose=general`, а не inline base64, как у OpenAI, — это стоит проверить отдельно на этапе
   реализации, т.к. отличается от паттерна OpenAI/Gemini).
   Для сравнения, Gemini использует тот же base64, но в поле `inlineData.data` внутри
   WebSocket-сообщения (`GeminiLive/GeminiLiveService.swift` строка 318,
   `GeminiVisionService.swift` строки 230/283).
6. Дополнительно фото сжимается/ресайзится на уровне констант: `Constants.Camera.maxPhotoDimension
   = 512`, `Constants.Camera.photoJPEGQuality = 0.5` (`OpenVision/Config/Constants.swift`,
   строки 121-132) — хотя конкретно `capturePhoto()` в `GlassesManager` берёт JPEG прямо из SDK
   (`format: .jpeg`) без явного вызова ресайза в этом методе — компрессия, судя по всему,
   применяется в других путях (стрим-фреймы, `onVideoFrame`), это стоит перепроверить перед тем,
   как полагаться на точный размер фото, попадающего к бэкенду.

---

## 7. Info.plist разрешения, язык, и хранилище ключей

### Разрешения (Info.plist)
Файл: `OpenVision/Resources/Info.plist`. Все `NS*UsageDescription` строки **написаны на
английском** (строки 96-134): микрофон, камера, распознавание речи, Bluetooth (Always +
Peripheral), фотобиблиотека (Add + полный доступ), геолокация, календарь (+FullAccess),
напоминания (+FullAccess). Локализации `.lproj`/`InfoPlist.strings` под другие языки в проекте
**не найдено** (папка `OpenVision/Resources` не содержит `ru.lproj` или подобных — проверялось
листингом каталога `Services`/`Managers`/`Views`, отдельного поиска `*.lproj` не проводилось, но
ни `project.yml`, ни README не упоминают локализацию UI/строк вообще — судя по всему, весь UI
(`Views/`) на английском тоже, интернационализация в проект не заведена).
`CFBundleDevelopmentRegion` = `$(DEVELOPMENT_LANGUAGE)` (переменная Xcode, не захардкожена, но
проекта локализации для неё нет).

### Хранилище ключей — Keychain НЕТ
Поиском `Keychain` по всему `OpenVision/` — **ни одного совпадения**. Все секреты (`openClawAuthToken`,
`geminiAPIKey`, `openAIAPIKey`, `tavilyAPIKey`, телеметрия — `telemetryToken`/`telemetryPassword`)
хранятся **в открытом виде** в структуре `AppSettings` (`OpenVision/Models/AppSettings.swift`),
которая целиком сериализуется в **обычный JSON-файл** `Documents/settings.json` через
`SettingsManager.swift` (`JSONEncoder`, без шифрования — см. `performSave()`, строки 98-108).
Так что для ключа GigaChat (`Authorization Key` для OAuth) правильный с точки зрения
**согласованности с остальным проектом** путь — просто новое поле в `AppSettings` (как у
остальных), а не отдельное Keychain-хранилище. Если захочется добавить Keychain — это отдельная,
не связанная с GigaChat задача повышения безопасности всего приложения (заслуживает отдельного
issue/PR, а не части фичи одного бэкенда).

---

## 8. Риски и открытые вопросы

1. **Несоответствие версии Meta DAT SDK в документации.** `README.md` и `SETUP.md` в явном тексте
   называют "0.4.0", тогда как реально закреплено (`project.yml` + `.pbxproj`) — **0.9.0**. Это
   значит: (a) документация Setup-гайда устарела и должна быть исправлена отдельно (вне рамок
   данной разведки — не трогать по заданию, но пользователю стоит знать); (b) при написании кода
   для GigaChat ориентироваться **только на project.yml/pbxproj**, не на текст README/SETUP.md.
2. **GigaChat — другая модель авторизации, чем у остальных бэкендов.** OpenAI/Gemini/OpenClaw
   используют статический API-ключ/токен. GigaChat (Sber) использует OAuth2 client-credentials
   (Authorization Key → обмен на Access Token с ограниченным сроком жизни, ~30 мин) — это
   потребует отдельного модуля обновления токена внутри `GigaChatService`, не имеющего аналога
   среди текущих бэкендов (ближе всего по духу — ничего, нужно писать с нуля).
3. **TLS/сертификаты НУЦ Минцифры.** GigaChat API по умолчанию отдаёт сертификат от российского
   удостоверяющего центра, которому iOS не доверяет "из коробки". `NSAllowsArbitraryLoads = true`
   в Info.plist отключает ATS-политики домена, но **не** отключает базовую проверку цепочки
   сертификата на уровне `URLSession` — потребуется либо кастомный `URLSessionDelegate` с ручной
   валидацией/pinning, либо инструкция пользователю установить корневой сертификат в профиль
   устройства. Это стоит проверить эмпирически перед реализацией.
4. **Региональные ограничения.** README уже фиксирует похожий риск для Gemini ("not all regions
   supported"). GigaChat API, вероятно, имеет ограничения по доступности вне РФ/для не-российских
   аккаунтов — требует отдельной проверки условий использования Sber на момент реализации.
5. **Отсутствие абстракции STT/TTS усложняет локализацию.** Хардкод `en-US` и англоязычных
   вариантов wake-word — не баг, а осознанная точка расширения (по комментариям в коде видно, что
   авторы уже боролись за надёжность распознавания именно английской фразы через Bluetooth HFP
   8kHz mic очков) — русская версия потребует не просто смены Locale, а переосмысления
   специфичных для распознавания "мисрекогнишнов" под русскую фонетику.
6. **Kokoro TTS не поддерживает русский** — либо отключать Kokoro-опцию для русской локали
   (fallback на Apple TTS, который русский поддерживает), либо вообще не решать эту часть в
   первой фазе.
7. **MockDeviceKit не интегрирован в проект и не до конца задокументирован публично** — неясно,
   требует ли он валидных `MetaAppID`/`ClientToken`, что важно для тестирования GigaChat-фичей
   (фото/видео с очков) без реального железа. Требует отдельного эксперимента с sample-проектом
   `meta-wearables-dat-ios/samples/`, который не клонировался в рамках этой разведки.
8. **Открытое хранение ключей.** Не специфично для GigaChat, но релевантно: если для GigaChat
   заведут Keychain "с нуля" ради одного ключа, это создаст несогласованность в кодовой базе
   (остальные ключи — в JSON). Лучше явно решить на уровне архитектуры (сразу для всех бэкендов,
   отдельной задачей) до или отдельно от фичи GigaChat.
9. **Формат передачи изображений у GigaChat, вероятно, отличается** от inline-base64 паттерна
   OpenAI/Gemini (в Sber API для мультимодальных запросов обычно используется отдельная загрузка
   файла с получением `file_id`, а не data URL) — при реализации `GigaChatService.sendMessage`
   потребуется отдельный HTTP-запрос загрузки файла перед основным chat-запросом, в отличие от
   единственного round-trip у `OpenAIService`.
10. **Сжатие фото перед отправкой** (`Constants.Camera.maxPhotoDimension`/`photoJPEGQuality`)
    применяется не факт что ко всем путям захвата (см. раздел 6, пункт 6) — стоит перепроверить
    перед тем как полагаться на размер файла, отправляемого в GigaChat (лимиты по размеру файла
    у разных облачных API отличаются).

---

## Прочитанные файлы (для справки)

- `README.md`, `SETUP.md`, `docs/architecture.md`, `project.yml`, `Config.xcconfig.example`
- `OpenVision/Resources/Info.plist`, `OpenVision/Config/Config.swift.example`,
  `OpenVision/Config/Constants.swift`
- `OpenVision/Services/AIBackend/AIBackendProtocol.swift`,
  `AIBackendConformances.swift`, `OpenAIService.swift`
- `OpenVision/Managers/SettingsManager.swift`, `GlassesManager.swift`
- `OpenVision/Models/AppSettings.swift`
- `OpenVision/Views/Settings/AIBackendSettingsView.swift`, `OpenAISettingsView.swift`
- `OpenVision/Services/Voice/VoiceCommandService.swift`
- `OpenVision/Services/TTS/TTSService.swift`, `KokoroTTSService.swift` (частично, grep по locale)
- `OpenVision/Views/VoiceAgent/VoiceAgentViewModel.swift` (фрагменты — путь фото)
- `OpenVision.xcodeproj/project.pbxproj` (grep — версия SPM-пакета)
- Внешние источники (WebFetch/WebSearch):
  https://github.com/facebook/meta-wearables-dat-ios ,
  https://wearables.developer.meta.com/docs/build-integration-ios/ ,
  https://wearables.developer.meta.com/docs/develop/dat/mock-device-kit/ ,
  https://wearables.developer.meta.com/docs/develop/dat/getting-started-toolkit/
