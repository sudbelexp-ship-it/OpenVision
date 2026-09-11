// OpenVision - DiagnosticsView.swift
// Экран «Диагностика» (см. PLAN.md, Фаза 5): статус очков, статус токена GigaChat, последние
// события и время ответа последнего запроса — без секретов и без текста реплик пользователя.

import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var glassesManager: GlassesManager
    @EnvironmentObject var settingsManager: SettingsManager
    @ObservedObject private var metrics = MetricsCollector.shared

    @State private var sberStatus: SberAuth.DiagnosticsStatus?

    var body: some View {
        Form {
            Section {
                statusRow("Регистрация", ok: glassesManager.isRegistered,
                          value: glassesManager.isRegistered ? "Зарегистрированы" : "Не зарегистрированы")
                statusRow("Устройства", ok: glassesManager.connectedDeviceCount > 0,
                          value: "\(glassesManager.connectedDeviceCount)")
                if let device = glassesManager.connectedDevice {
                    HStack {
                        Text("Активное устройство")
                        Spacer()
                        Text(device).foregroundColor(.secondary)
                    }
                }
                statusRow("Стрим", ok: glassesManager.isStreaming,
                          value: glassesManager.isStreaming ? "Активен" : "Не активен")
            } header: {
                Text("Очки")
            }

            Section {
                if settingsManager.settings.isSberConfigured {
                    if let sberStatus {
                        statusRow("Токен GigaChat", ok: sberStatus.isAlive,
                                  value: sberStatus.isAlive
                                    ? "Жив ещё \(sberStatus.secondsRemaining ?? 0) с"
                                    : "Истёк или ещё не получен")
                    } else {
                        HStack {
                            Text("Токен GigaChat")
                            Spacer()
                            ProgressView()
                        }
                    }
                } else {
                    Text("GigaChat не настроен (нет Authorization Key)")
                        .foregroundColor(.orange)
                }
            } header: {
                Text("GigaChat")
            } footer: {
                Text("Обновляется при открытии этого экрана. Сам токен и ключ здесь никогда не показываются.")
            }

            Section {
                if let last = metrics.recentTurns.first {
                    if let latency = last.perceivedLatency {
                        HStack {
                            Text("Время ответа последнего запроса")
                            Spacer()
                            Text(String(format: "%.1f с", latency)).foregroundColor(.secondary)
                        }
                    } else if let ttft = last.timeToFirstToken {
                        HStack {
                            Text("Время до первого токена")
                            Spacer()
                            Text(String(format: "%.1f с", ttft)).foregroundColor(.secondary)
                        }
                    } else {
                        Text("Последний запрос ещё не завершён").foregroundColor(.secondary)
                    }
                } else {
                    Text("Запросов пока не было").foregroundColor(.secondary)
                }
            } header: {
                Text("Последний запрос")
            }

            Section {
                if metrics.recentTurns.isEmpty {
                    Text("Событий пока нет").foregroundColor(.secondary)
                } else {
                    ForEach(metrics.recentTurns.prefix(20)) { turn in
                        turnRow(turn)
                    }
                }
            } header: {
                Text("Последние события (до 20)")
            } footer: {
                Text("Только тайминги, бэкенд и модель — без текста команд и ответов.")
            }
        }
        .navigationTitle("Диагностика")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshSberStatus() }
        .refreshable { await refreshSberStatus() }
    }

    @ViewBuilder
    private func statusRow(_ label: String, ok: Bool, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.secondary)
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(ok ? .green : .orange)
        }
    }

    @ViewBuilder
    private func turnRow(_ turn: TurnTimeline) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(turn.backend ?? "—")
                    .font(.subheadline)
                Spacer()
                Text(turn.startedAt, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                if let latency = turn.perceivedLatency {
                    Text(String(format: "%.1fс", latency)).font(.caption).foregroundColor(.secondary)
                }
                if turn.abandoned {
                    Text("прервано").font(.caption).foregroundColor(.orange)
                }
                if turn.interrupted {
                    Text("перебито").font(.caption).foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func refreshSberStatus() async {
        sberStatus = await SberAuth.shared.diagnosticsStatus()
    }
}

#Preview {
    NavigationStack {
        DiagnosticsView()
            .environmentObject(GlassesManager.shared)
            .environmentObject(SettingsManager.shared)
    }
}
