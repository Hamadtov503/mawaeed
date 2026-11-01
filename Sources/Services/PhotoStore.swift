import UIKit
import LocalAuthentication
import SwiftUI

/// Photos of documents, receipts and warranty cards, kept as JPEGs in the app's Documents folder.
enum PhotoStore {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("photos")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    static func save(_ image: UIImage) -> String? {
        guard let data = resized(image, maxSide: 1800).jpegData(compressionQuality: 0.72) else { return nil }
        return write(data)
    }

    static func write(_ data: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        write(data, name: name)
        return name
    }

    static func write(_ data: Data, name: String) {
        try? data.write(to: url(name), options: .atomic)
    }

    static func data(_ name: String) -> Data? { try? Data(contentsOf: url(name)) }

    static func image(_ name: String) -> UIImage? { UIImage(contentsOfFile: url(name).path) }

    static func delete(_ name: String) { try? FileManager.default.removeItem(at: url(name)) }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// Optional Face ID / passcode lock.
final class AppLock: ObservableObject {
    static let shared = AppLock()
    @Published var isLocked: Bool
    private var authenticating = false

    private init() {
        isLocked = AppSettings.shared.lockEnabled
    }

    func lock() {
        if AppSettings.shared.lockEnabled { isLocked = true }
    }

    func unlock() {
        guard isLocked, !authenticating else { return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            isLocked = false
            return
        }
        authenticating = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "افتح مواعيدي") { ok, _ in
            DispatchQueue.main.async {
                self.authenticating = false
                if ok { self.isLocked = false }
            }
        }
    }

    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "رمز الجوال"
        }
    }
}
