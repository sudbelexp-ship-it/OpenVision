// OpenVision - PickedPhotoStore.swift
// Хранилище одного статичного фото для источника кадра «Выбрать фото» (см. PLAN.md, Фаза 5) —
// тест голосового конвейера на заранее выбранной картинке, без камеры и без очков вообще.

import Foundation

enum PickedPhotoStore {
    private static let filename = "picked_photo.jpg"

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }

    static func save(_ data: Data) {
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }
}
