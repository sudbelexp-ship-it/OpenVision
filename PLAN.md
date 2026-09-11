# OpenVision-RU: единый план (Ray-Ban Meta Gen 2 + iPhone 17 Pro + GigaChat)

Версия плана: 11.09.2026. Файл положить в корень форка как `PLAN.md` и дать Claude Code команду из раздела 3.

---

## 0. Зафиксированные решения (без вариантов)

| Что | Решение |
|---|---|
| База | Форк `rayl15/OpenVision` (MIT), **публичный** репозиторий на GitHub |
| Анализ изображений | GigaChat API напрямую (developers.sber.ru), модель `GigaChat-2-Max`, тариф Freemium |
| Текстовые ответы | `GigaChat-2-Pro` (в настройках можно переключить на Max) |
| Распознавание речи | Apple `SFSpeechRecognizer`, `ru-RU`, on-device где доступно |
| Озвучка | Apple `AVSpeechSynthesizer`, голос `ru-RU` |
| Yandex SpeechKit | Потом. Сейчас только протоколы `STTProvider` / `TTSProvider`, чтобы подключить без переделок |
| Сборка | GitHub Actions, runner `macos-26`, **неподписанный** `.ipa` как артефакт |
| Подпись и установка | Sideloadly на Windows, бесплатный Apple ID (подпись живёт 7 дней) |
| Секреты | В репозитории **ничего секретного**. Ключ GigaChat вводится в приложении и хранится в Keychain. Meta App ID / Client Token — через GitHub Secrets |
| Запуск анализа | Голосовая фраза (по умолчанию «Окей, очки», меняется в настройках) + кнопка в приложении |
| Язык интерфейса и ответов | Русский |
| Тест до прихода очков | Режим «Камера iPhone»: тот же конвейер, но кадр с камеры телефона |

VPN нужен только для: GitHub, Claude Code, Meta AI app, Meta Wearables Developer Center, входа Apple ID в Sideloadly. Сам GigaChat работает без VPN (при тесте GigaChat VPN лучше выключить или добавить домены Сбера в исключения).

---

## 1. Ручные шаги Ивана (Claude Code их сделать не может)

Делать до запуска Claude Code, по порядку. Ориентир — 2–3 часа.

### 1.1 Windows
1. Включить VPN.
2. Установить **Git for Windows**: https://git-scm.com/download/win
3. Установить **Claude Code** (PowerShell):
   ```powershell
   irm https://claude.ai/install.ps1 | iex
   claude --version
   claude doctor
   ```
   Войти аккаунтом Claude Pro/Max.
4. Установить **iTunes** и **iCloud** с сайта apple.com (именно с сайта Apple, НЕ из Microsoft Store — иначе Sideloadly не видит iPhone).
5. Установить **Sideloadly**: https://sideloadly.io
6. (Для локального smoke-теста) Python 3.12+: https://www.python.org/downloads/ — галочка «Add to PATH».

### 1.2 GitHub
1. Аккаунт на github.com (если нет).
2. Открыть https://github.com/rayl15/OpenVision → **Fork** → оставить публичным.
3. В форке: Settings → Actions → General → разрешить Actions.
4. Склонировать:
   ```powershell
   cd D:\dev
   git clone https://github.com/<ваш_логин>/OpenVision.git
   cd OpenVision
   ```
5. Скопировать этот файл в корень как `PLAN.md`.

### 1.3 GigaChat (VPN выключить)
1. https://developers.sber.ru/studio → войти через Сбер ID.
2. Создать проект **GigaChat API** (для физлиц, Freemium).
3. Настройки API → **Получить ключ** → скопировать **Authorization Key** (показывается один раз). Сохранить в менеджер паролей.
4. Этот ключ **никогда** не вставлять в код, в чат с Claude Code, в коммиты. Он понадобится только: (а) в локальном smoke-тесте как переменная окружения, (б) в настройках приложения на iPhone.

### 1.4 Apple ID для подписи
1. Использовать имеющийся иностранный Apple ID (или завести отдельный бесплатный — лучше отдельный, чтобы не рисковать основным).
2. Включить двухфакторную аутентификацию.
3. Ограничения бесплатного Apple ID: подпись 7 дней, не более 3 своих приложений на устройстве, не более 10 App ID в неделю — не пересоздавать Bundle ID без нужды.

### 1.5 Meta
1. На iPhone, под иностранным Apple ID + VPN: установить **Meta AI** из App Store. Войти аккаунтом Meta.
2. Через VPN открыть **Meta Wearables Developer Center** (https://developers.meta.com/wearables). Попробовать создать приложение и получить **App ID** и **Client Token**.
   - Получилось → добавить в форке: Settings → Secrets and variables → Actions → New repository secret: `META_APP_ID`, `META_CLIENT_TOKEN`.
   - Не получилось (регион) → ничего не делать, работаем в Developer Mode; Claude Code в фазе 1 выяснит по официальным samples, какие значения ставятся для Developer Mode.
3. Когда придут очки: сопряжение в Meta AI → Settings → About → 5 раз тапнуть по номеру версии → включить **Developer Mode**.

### 1.6 iPhone
1. Настройки → Конфиденциальность и безопасность → **Режим разработчика** → включить → перезагрузка. Если пункта нет — он появится после первой установки через Sideloadly; тогда включить и переустановить.

---

## 2. Расписание

| Когда | Что | Кто |
|---|---|---|
| День 1, утро | Раздел 1 (кроме Developer Mode очков) | Иван |
| День 1, день | Фаза 1 (разведка) и Фаза 2 (зелёный CI на нетронутом форке) | Claude Code |
| День 1, вечер | Фаза 3a (smoke-тест GigaChat на Windows) — запуск Иваном со своим ключом | Claude Code + Иван |
| День 2, утро | Фаза 3b (бэкенд «Сбер» в приложении) | Claude Code |
| День 2, день | Фаза 4 (русский голос) и Фаза 5 (режим «Камера iPhone», тесты) | Claude Code |
| День 2, вечер | Фаза 6: скачать IPA → Sideloadly → тест на iPhone без очков | Иван |
| День 3 (очки) | Активация очков, Developer Mode, регистрация в приложении, полевой тест | Иван |

---

## 3. Задание для Claude Code

Запуск из папки форка:
```powershell
cd D:\dev\OpenVision
claude
```
Первое сообщение в Claude Code:

> Прочитай PLAN.md целиком. Выполняй раздел 3 по фазам строго по порядку. После каждой фазы: коммит, push, дождись зелёного GitHub Actions, коротко отчитайся и жди моего «дальше». Если реальность в репозитории расходится с планом — остановись и спроси, не импровизируй.

### Общие правила для Claude Code
- Язык общения и комментариев в новом коде — русский; идентификаторы — английские.
- Никаких секретов в репозитории, логах CI и коде. Ключи — только Keychain на устройстве, GitHub Secrets или переменные окружения локально.
- Не ломать и не удалять существующие бэкенды (OpenAI, Gemini, MLX, Apple). Только добавлять.
- Не обновлять версию Meta DAT SDK и других зависимостей без явной необходимости и моего согласия.
- Маленькие осмысленные коммиты, сообщения на русском.
- Сборки Swift локально невозможны (Windows) — единственная проверка компиляции это CI. Поэтому пиши код аккуратно под Swift 6 / Xcode 26, проверяй типы и импорты до push, читай логи CI при ошибке.
- Любой новый ключ Info.plist, entitlement или capability — перечисли в отчёте.

---

### Фаза 1. Разведка (без изменения кода)

Сделать:
1. Прочитать `README.md`, `SETUP.md`, `docs/architecture.md`, `project.yml`, `Config.xcconfig.example`, `Info.plist`, папки `Services/`, `Managers/`, `Views/Settings`.
2. Найти протокол/интерфейс, который реализуют бэкенды, и место, где выбирается активный бэкенд.
3. Найти, как устроены распознавание речи, озвучка и голосовая активация (wake word), какая локаль.
4. Определить закреплённую версию `meta-wearables-dat-ios` и её требования.
5. Изучить официальный репозиторий https://github.com/facebook/meta-wearables-dat-ios (README, `samples/`, документацию) и выяснить: какие значения `MWDAT` в Info.plist (`MetaAppID`, `ClientToken`, `TeamID`, `AppLinkURLScheme`) нужны в **Developer Mode без регистрации** в Wearables Developer Center; есть ли Mock Device Kit и как им пользоваться.
6. Выяснить, как OpenVision получает фото с очков (`capturePhoto` / кадр из стрима) и в каком виде оно доходит до бэкенда.

Результат: файл `NOTES.md` на русском — карта проекта, точки интеграции (файл + тип/функция), ответы на пп. 2–6, список рисков. Код не трогать.

Критерий готовности: `NOTES.md` закоммичен, я его прочитал и сказал «дальше».

---

### Фаза 2. CI до любых изменений

Сделать `.github/workflows/build.yml`:
- триггеры: `push` в `main`, `workflow_dispatch`, теги `v*`;
- `runs-on: macos-26`; выбрать последний стабильный Xcode 26.x через `sudo xcode-select` (путь проверить командой `ls /Applications | grep Xcode` в логе);
- `brew install xcodegen` → `xcodegen generate`;
- шаг, который **генерирует `Config.xcconfig` из GitHub Secrets** (`META_APP_ID`, `META_CLIENT_TOKEN`; если секретов нет — значения для Developer Mode, найденные в фазе 1; `PRODUCT_BUNDLE_IDENTIFIER = ru.ivan.openvision`; `DEVELOPMENT_TEAM` пустой);
- сборка `xcodebuild ... -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`;
- упаковка `Payload/OpenVision.app` → `OpenVision-unsigned.ipa`;
- `actions/upload-artifact@v4`, имя артефакта с коротким SHA коммита;
- для тегов `v*` — дополнительно GitHub Release с IPA;
- отдельный job `unit-tests` (симулятор iOS), пока может быть пустым — заполним в фазе 5.
- Секреты не выводить в лог (`::add-mask::`).

Критерий готовности: на **нетронутом** коде форка CI зелёный, IPA скачивается. Если нетронутый форк не собирается — чинить минимально и описать, что исправлено.

---

### Фаза 3a. Smoke-тест GigaChat на Windows

Сделать `tools/gigachat_smoke.py` (только стандартная библиотека + `requests`):
- ключ из переменной окружения `GIGACHAT_AUTH_KEY`;
- корневой сертификат НУЦ Минцифры: файл `certs/russian_trusted_root_ca.pem` в репозитории (это публичный сертификат, коммитить можно; скачать с https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt и проверить, что это PEM);
- шаги: OAuth (`POST https://ngw.devices.sberbank.ru:9443/api/v2/oauth`, `RqUID` = uuid4, `scope=GIGACHAT_API_PERS`) → вывести время жизни токена → `GET /api/v1/models` → загрузить `tools/test.jpg` через `POST /api/v1/files` → `chat/completions` с `GigaChat-2-Max` и `attachments` → вывести ответ → удалить загруженный файл эндпоинтом удаления файлов из официальной документации;
- ключ и токен в выводе не печатать.

Инструкция для меня в `tools/README.md`:
```powershell
pip install requests
$env:GIGACHAT_AUTH_KEY = "<ключ>"
python tools\gigachat_smoke.py
```

Критерий готовности: я запустил, получил описание тестовой картинки на русском. Точные поля ответа (`expires_at` в мс, `id` файла, структура `choices`) сверить с реальным ответом и зафиксировать в `NOTES.md` — Swift-код пишется по ним.

---

### Фаза 3b. Бэкенд «Сбер» в приложении

Файлы (имена — ориентир, подстроить под структуру из фазы 1):
- `Services/Sber/SberTrustDelegate.swift` — `URLSessionDelegate`, добавляет `certs/russian_trusted_root_ca.pem` из бандла как якорь (`SecTrustSetAnchorCertificates` + `SecTrustSetAnchorCertificatesOnly(false)` + `SecTrustEvaluateWithError`). Применять **только** к хостам `*.devices.sberbank.ru`, для остальных — стандартная обработка. ATS глобально не отключать.
- `Services/Sber/SberAuth.swift` — `actor`: хранит токен, обновляет за 60 с до `expires_at`, при 401 — одно принудительное обновление и повтор запроса.
- `Services/Sber/GigaChatClient.swift` — `uploadImage(jpeg)`, `deleteFile(id)`, `chat(messages, model, attachments)`; поддержка стриминга (SSE), если существующий протокол бэкендов его использует.
- `Services/Sber/SberService.swift` — реализация протокола бэкенда OpenVision.
- Keychain-хранилище Authorization Key (переиспользовать существующее в проекте, если есть).

Поведение:
- Все запросы к GigaChat идут последовательно (у физлиц 1 поток): очередь внутри `actor`, повторный запрос при 429 с паузой 1–2 с, максимум 2 повтора.
- 402 → понятное сообщение «Закончился лимит токенов GigaChat».
- Изображение перед отправкой: JPEG, качество 0.8, длинная сторона ≤ 1600 px, короткая ≥ 800 px, если исходник позволяет. После ответа — удалить файл из хранилища GigaChat.
- История диалога: последние N сообщений (по умолчанию 10), изображения — только в текущем запросе.
- Системный промпт (русский): «Ты голосовой ассистент в умных очках. Отвечай по-русски, коротко: 1–3 предложения, без списков и разметки, так как ответ будет озвучен. Если спрашивают о том, что на изображении — описывай конкретно и по делу.» Промпт редактируется в настройках.
- Настройки: поле ключа (секьюр), выбор модели для изображений (по умолчанию `GigaChat-2-Max`) и для текста (по умолчанию `GigaChat-2-Pro`), кнопка «Проверить подключение» (OAuth + `/models`, результат зелёным/красным), сделать «Сбер» бэкендом по умолчанию.
- Бандл: добавить `russian_trusted_root_ca.pem` в ресурсы через `project.yml`.

Критерий готовности: CI зелёный; юнит-тесты на разбор ответов OAuth/files/chat по реальным примерам из фазы 3a (JSON-фикстуры без секретов) проходят.

---

### Фаза 4. Русский голос (Apple), задел под Yandex

- Ввести протоколы `STTProvider` и `TTSProvider`; текущие Apple-реализации обернуть в них. Yandex не реализовывать — только пустой каркас `YandexSpeechKitProvider` с `TODO` и выбором в настройках, помеченным «скоро» (неактивным).
- STT: `SFSpeechRecognizer(locale: ru-RU)`, `requiresOnDeviceRecognition = true`, если `supportsOnDeviceRecognition`, иначе серверное распознавание Apple.
- TTS: `AVSpeechSynthesizer`, лучший доступный голос `ru-RU` (предпочитать enhanced/premium, если установлен); скорость настраивается.
- Аудиосессия: вывод в Bluetooth-гарнитуру очков, микрофон очков, когда подключены (`.playAndRecord`, опции для Bluetooth HFP/A2DP — выбрать по тому, как это уже сделано в OpenVision). Проверить, что озвучка не глушит распознавание (эхо): во время озвучки распознавание на паузе.
- Голосовая активация: фраза настраивается, по умолчанию «Окей, очки»; распознавание фразы на русском. Команды по умолчанию: «что это» / «что я вижу» / «прочитай» → сделать фото и отправить в vision; остальное → текстовый вопрос.

Критерий готовности: CI зелёный; в отчёте — какие ключи Info.plist задействованы (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` и т.д.), тексты разрешений на русском.

---

### Фаза 5. Режим без очков и тесты

- В настройках переключатель источника кадра: «Очки» / «Камера iPhone» / «Выбрать фото». Весь конвейер (голос → фото → GigaChat → озвучка) должен работать с камерой iPhone — это тест до прихода очков.
- Если в DAT SDK есть Mock Device Kit — подключить в Debug-конфигурации.
- Экран «Диагностика»: статус подключения очков, статус токена GigaChat (жив/истёк), последние 20 событий лога без секретов, время ответа последнего запроса.
- Заполнить job `unit-tests` в CI.

Критерий готовности: CI зелёный, оба job проходят.

---

### Фаза 6. Релиз и инструкция установки

- `README_RU.md`: установка IPA через Sideloadly, первый запуск, где ввести ключ GigaChat, как зарегистрировать очки в приложении, переподпись раз в 7 дней, частые ошибки.
- Поставить тег `v0.1.0` → GitHub Release с IPA.

---

## 4. Установка на iPhone (Иван, День 2 вечером)

1. GitHub → форк → Actions (или Releases) → скачать `OpenVision-unsigned.ipa`.
2. iPhone по кабелю к ПК, «Доверять этому компьютеру».
3. Sideloadly: перетащить IPA, ввести Apple ID для подписи, Start. При запросе 2FA — ввести код.
4. iPhone: Настройки → Основные → VPN и управление устройством → доверять профилю разработчика. Включить Режим разработчика, если ещё не включён.
5. Открыть приложение → Настройки → вставить Authorization Key GigaChat → «Проверить подключение».
6. Источник кадра «Камера iPhone» → сказать «Окей, очки, что это?» → должен прозвучать ответ.

## 5. День прихода очков

1. Meta AI (VPN) → сопряжение очков → Settings → About → 5 тапов по версии → Developer Mode.
2. OpenVision → Настройки → Очки → Зарегистрировать (откроется Meta AI, подтвердить доступ) → вернуться.
3. Источник кадра «Очки» → тест: «Окей, очки, что я вижу?», «Окей, очки, прочитай».
4. Если очки не подключаются — открыть «Диагностику», прислать лог в Claude Code.

## 6. Регулярное обслуживание

- Каждые 7 дней: снова установить тот же IPA через Sideloadly (данные и ключ сохраняются).
- Новые версии: push в `main` → CI → новый IPA → Sideloadly.
- Лимиты Freemium GigaChat: 25 млн токенов Max и 40 млн Pro на 12 месяцев; одна картинка ≈ до 1 800 токенов.

## 7. Потом (не сейчас)

- Yandex SpeechKit: реализовать `YandexSpeechKitProvider` (STT и TTS), ключ в Keychain.
- При исчерпании Freemium: платные токены GigaChat через cloud.ru.
- Платный Apple Developer — если надоест переподпись раз в 7 дней.
