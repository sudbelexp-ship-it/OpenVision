// OpenVision - OpenVisionApp.swift
// App entry point with URL scheme handling for Meta AI registration

import SwiftUI
import MWDATCore
#if DEBUG
import MWDATMockDevice
#endif

@main
struct OpenVisionApp: App {
    // MARK: - SDK bootstrap (см. ниже, почему это отдельное свойство, а не строка в init())

    /// `Wearables.configure()` должен отработать ДО первого обращения к `Wearables.shared` —
    /// а `GlassesManager.init()` обращается к нему в инициализаторе своего хранимого свойства
    /// (`private let wearables = Wearables.shared`). `@StateObject`-свойства этой структуры
    /// инициализируются В ПОРЯДКЕ ОБЪЯВЛЕНИЯ ДО тела `init()` — так что вызов `configure()` из
    /// init() опаздывает: `glassesManager` ниже уже успевает создать `GlassesManager.shared` и
    /// упасть с "Call configure() before attempting to access Wearables!". Это баг, который был
    /// в проекте изначально — просто до сих пор никто не запускал собранное приложение
    /// (`xcodebuild build` его не запускает; обнаружено при первом реальном прогоне юнит-тестов
    /// на симуляторе в Фазе 5, тесты хостятся внутри самого приложения). Побочный эффект
    /// static-свойства, объявленного выше `glassesManager`, — единственный надёжный способ
    /// гарантировать порядок без переписывания GlassesManager.
    private static let wearablesConfigured: Bool = {
        do {
            try Wearables.configure()
            print("[OpenVisionApp] Wearables SDK configured")
            return true
        } catch {
            print("[OpenVisionApp] Failed to configure Wearables SDK: \(error)")
            return false
        }
    }()

    // MARK: - State Objects

    @StateObject private var settingsManager = SettingsManager.shared
    @StateObject private var glassesManager: GlassesManager = {
        _ = OpenVisionApp.wearablesConfigured   // форсируем конфигурацию SDK перед доступом к Wearables.shared
        return GlassesManager.shared
    }()
    @StateObject private var conversationManager = ConversationManager.shared

    // MARK: - App Storage

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // MARK: - Initialization

    init() {
        // Show timer/alarm notifications even when the app is in the foreground.
        NotificationForegroundPresenter.shared.register()
        // Create the location manager on the main thread + warm the cache for contextual notes.
        LocationHelper.shared.prewarm()

        // Move the model store OUT of Caches before anything touches the hub. iOS may purge
        // Caches under storage pressure, which silently deleted downloaded model weights (the app
        // then re-downloaded ~GBs at "connecting…" time). Must run before any HubClient exists.
        GemmaLocalService.bootstrapModelStore()

        // Mock Device Kit — тест регистрации/стрима без реальных очков в Debug-сборках (см.
        // PLAN.md, Фаза 5). Включает debug-оверлей SDK (иконка "ladybug"), которым пользователь
        // сам управляет: создаёт mock-устройство, включает питание/don, выбирает источник видео.
        // Product MWDATMockDevice подтверждён в Package.swift пакета meta-wearables-dat-ios
        // именно на закреплённой версии 0.9.0 — не гадание по документации. Wearables SDK к этому
        // моменту уже настроен (см. wearablesConfigured выше — гарантированно раньше этой строки).
        #if DEBUG
        MockDeviceKit.shared.enable()
        print("[OpenVisionApp] MockDeviceKit enabled (Debug)")
        #endif

        print("[OpenVisionApp] Initialized")
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                        .environmentObject(settingsManager)
                        .environmentObject(glassesManager)
                        .environmentObject(conversationManager)
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                // Telemetry settings persist, but the sink lives in memory — without this a
                // relaunch (or a jetsam kill during a model switch) silently stopped pushing.
                MetricsCollector.shared.restoreAtLaunch()
            }
            .onOpenURL { url in
                handleURL(url)
            }
        }
    }

    // MARK: - URL Handling

    /// Handle URL callback from Meta AI app for glasses registration
    private func handleURL(_ url: URL) {
        print("[OpenVisionApp] Received URL: \(url)")

        Task {
            do {
                _ = try await Wearables.shared.handleUrl(url)
                print("[OpenVisionApp] URL handled successfully")
            } catch {
                print("[OpenVisionApp] Error handling URL: \(error)")
            }
        }
    }
}
