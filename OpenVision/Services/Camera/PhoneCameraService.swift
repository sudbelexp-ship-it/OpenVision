// OpenVision - PhoneCameraService.swift
// Захват одного кадра с задней камеры iPhone — источник «Камера iPhone» (см. PLAN.md, Фаза 5):
// тот же голосовой конвейер, что и с очками, но без реального железа — для теста до его прихода.
//
// Сессия не показывает превью — захват полностью безэкранный (голосовая команда → кадр), как и
// у очков. Сессия стартует лениво при первом снимке и остаётся запущенной, чтобы повторные
// команды не платили заново за настройку экспозиции/фокуса.

import AVFoundation
import Foundation

@MainActor
final class PhoneCameraService: NSObject, ObservableObject {

    static let shared = PhoneCameraService()

    @Published private(set) var isSessionRunning = false

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var pendingContinuation: CheckedContinuation<Data?, Never>?

    private override init() {
        super.init()
    }

    /// Снять один кадр. `nil`, если нет разрешения на камеру или устройство недоступно
    /// (например, симулятор).
    func capturePhoto() async -> Data? {
        guard await ensureAuthorized() else {
            NSLog("[PhoneCamera] Нет разрешения на использование камеры")
            return nil
        }
        guard configureIfNeeded() else {
            NSLog("[PhoneCamera] Не удалось настроить камеру (устройство недоступно)")
            return nil
        }
        startIfNeeded()

        // Даём датчику короткое время на автоэкспозицию/автофокус перед первым кадром сессии —
        // без превью пользователь не видит, что происходит "прогрев", так что делаем его коротким.
        try? await Task.sleep(nanoseconds: 400_000_000)

        return await withCheckedContinuation { continuation in
            self.pendingContinuation = continuation
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Остановить сессию (например, при переключении источника кадра на «Очки» в настройках).
    func stopSession() {
        guard session.isRunning else { return }
        session.stopRunning()
        isSessionRunning = false
    }

    // MARK: - Authorization

    private func ensureAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    // MARK: - Session setup

    @discardableResult
    private func configureIfNeeded() -> Bool {
        guard !isConfigured else { return true }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return false
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else { return false }
        session.addOutput(photoOutput)

        isConfigured = true
        return true
    }

    private func startIfNeeded() {
        guard !session.isRunning else { return }
        // startRunning() блокирует поток — Apple прямо требует не вызывать его на главном потоке.
        let session = self.session
        Task.detached {
            session.startRunning()
        }
        isSessionRunning = true
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension PhoneCameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        if let error {
            NSLog("[PhoneCamera] Ошибка захвата: %@", error.localizedDescription)
        }
        Task { @MainActor in
            self.pendingContinuation?.resume(returning: data)
            self.pendingContinuation = nil
        }
    }
}
