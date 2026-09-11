// OpenVision - GigaChatSettingsView.swift
// Настройки бэкенда "Сбер" (GigaChat) — калька с OpenAISettingsView.swift.

import SwiftUI

struct GigaChatSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var authKey: String = ""
    @State private var visionModel: String = "GigaChat-2-Max"
    @State private var textModel: String = "GigaChat-2-Pro"
    @State private var systemPrompt: String = ""
    @State private var historyLimit: Int = 10

    @State private var isChecking = false
    @State private var checkResult: CheckResult?

    enum CheckResult {
        case success(modelCount: Int)
        case failure(String)
    }

    var body: some View {
        Form {
            // Authorization Key
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Authorization Key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("ключ из личного кабинета developers.sber.ru", text: $authKey)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Авторизация")
            } footer: {
                if authKey.isEmpty {
                    Label("Обязательно для режима Сбер (GigaChat)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.caption)
                } else {
                    Label("Ключ задан", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green).font(.caption)
                }
            }

            // Проверка подключения
            Section {
                Button {
                    checkConnection()
                } label: {
                    HStack {
                        if isChecking {
                            ProgressView().padding(.trailing, 4)
                        }
                        Text("Проверить подключение")
                    }
                }
                .disabled(authKey.isEmpty || isChecking)

                if let checkResult {
                    switch checkResult {
                    case .success(let modelCount):
                        Label("Подключение успешно (\(modelCount) моделей доступно)", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            }

            // Модели
            Section {
                TextField("Модель для изображений", text: $visionModel)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                TextField("Модель для текста", text: $textModel)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            } header: {
                Text("Модели")
            } footer: {
                Text("По умолчанию GigaChat-2-Max для фото и GigaChat-2-Pro для текста.")
            }

            // Системный промпт
            Section {
                TextEditor(text: $systemPrompt)
                    .frame(minHeight: 100)
            } header: {
                Text("Системный промпт")
            } footer: {
                Text("Отправляется перед каждым запросом. Держите короче — ответ озвучивается вслух.")
            }

            // История
            Section {
                Stepper("Сообщений в истории: \(historyLimit)", value: $historyLimit, in: 0...20)
            } header: {
                Text("История диалога")
            }

            // Помощь
            Section {
                Link(destination: URL(string: "https://developers.sber.ru/studio")!) {
                    HStack {
                        Text("Получить Authorization Key")
                        Spacer()
                        Image(systemName: "arrow.up.right.square").foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Помощь")
            } footer: {
                Text("GigaChat — облачный бэкенд Сбера для текста и изображений. Запросы идут последовательно (тариф Freemium — один поток).")
            }
        }
        .navigationTitle("Сбер (GigaChat)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let settings = settingsManager.settings
            authKey = settings.sberAuthKey
            visionModel = settings.sberVisionModel
            textModel = settings.sberTextModel
            systemPrompt = settings.sberSystemPrompt
            historyLimit = settings.sberHistoryLimit
        }
        .onDisappear { saveSettings() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { saveSettings(); dismiss() }
            }
        }
    }

    private func saveSettings() {
        settingsManager.settings.sberAuthKey = authKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVision = visionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsManager.settings.sberVisionModel = trimmedVision.isEmpty ? "GigaChat-2-Max" : trimmedVision
        let trimmedText = textModel.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsManager.settings.sberTextModel = trimmedText.isEmpty ? "GigaChat-2-Pro" : trimmedText
        settingsManager.settings.sberSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsManager.settings.sberHistoryLimit = historyLimit
        settingsManager.saveNow()
    }

    private func checkConnection() {
        let key = authKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isChecking = true
        checkResult = nil
        Task {
            do {
                let count = try await GigaChatClient.shared.checkConnection(authKey: key)
                await MainActor.run {
                    checkResult = .success(modelCount: count)
                    isChecking = false
                }
            } catch {
                await MainActor.run {
                    checkResult = .failure(error.localizedDescription)
                    isChecking = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        GigaChatSettingsView().environmentObject(SettingsManager.shared)
    }
}
