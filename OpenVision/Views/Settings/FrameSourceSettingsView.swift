// OpenVision - FrameSourceSettingsView.swift
// Источник кадра для фото-команд: Очки / Камера iPhone / Выбрать фото (см. PLAN.md, Фаза 5).

import SwiftUI
import PhotosUI
import UIKit

struct FrameSourceSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var photoPickerItem: PhotosPickerItem?
    @State private var pickedPreview: UIImage?
    @State private var pickError: String?

    var body: some View {
        Form {
            Section {
                ForEach(FrameSourceType.allCases, id: \.self) { source in
                    Button {
                        select(source)
                    } label: {
                        HStack {
                            Image(systemName: source.icon)
                                .foregroundColor(Theme.accent)
                                .frame(width: 24)
                            Text(source.displayName)
                                .foregroundColor(.primary)
                            Spacer()
                            if settingsManager.settings.frameSource == source {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.accent)
                            }
                        }
                    }
                }
            } header: {
                Text("Источник кадра")
            } footer: {
                Text("«Очки» — основной сценарий. «Камера iPhone» и «Выбрать фото» нужны для теста голосового конвейера (голос → фото → ИИ → озвучка) до прихода очков.")
            }

            if settingsManager.settings.frameSource == .pickedPhoto {
                Section {
                    if let pickedPreview {
                        Image(uiImage: pickedPreview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Фото не выбрано")
                            .foregroundColor(.secondary)
                    }

                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        Label("Выбрать фото из библиотеки", systemImage: "photo.badge.plus")
                    }

                    if PickedPhotoStore.exists {
                        Button(role: .destructive) {
                            PickedPhotoStore.clear()
                            pickedPreview = nil
                        } label: {
                            Label("Удалить выбранное фото", systemImage: "trash")
                        }
                    }

                    if let pickError {
                        Text(pickError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Выбранное фото")
                } footer: {
                    Text("Это фото будет использоваться для каждой команды («что это», «что я вижу») вместо реального кадра.")
                }
            }

            if settingsManager.settings.frameSource == .iPhoneCamera {
                Section {
                    Text("Разрешите доступ к камере при первом запросе. Кадр снимается без предпросмотра, сразу по голосовой команде.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Источник кадра")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadPreview() }
        .onChange(of: photoPickerItem) { _, newItem in
            Task { await handlePicked(newItem) }
        }
    }

    private func select(_ source: FrameSourceType) {
        settingsManager.settings.frameSource = source
        if source != .iPhoneCamera {
            PhoneCameraService.shared.stopSession()
        }
    }

    private func loadPreview() {
        guard let data = PickedPhotoStore.load() else { return }
        pickedPreview = UIImage(data: data)
    }

    private func handlePicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        pickError = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                pickError = "Не удалось загрузить фото."
                return
            }
            // Перекодируем в JPEG — исходник может быть HEIC.
            guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
                pickError = "Не удалось обработать фото."
                return
            }
            PickedPhotoStore.save(jpeg)
            pickedPreview = image
        } catch {
            pickError = "Ошибка загрузки: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        FrameSourceSettingsView().environmentObject(SettingsManager.shared)
    }
}
