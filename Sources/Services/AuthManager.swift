import Foundation
import Combine
import AuthenticationServices
import CryptoKit
import Security
import UIKit

/// Hosted Google/Apple OAuth through Supabase Auth. Only the public anon/publishable
/// key belongs in the app. Provider secrets remain in the server dashboard.
final class AuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthManager()
    static let callback = "com.hamad.mawaeed://auth/callback"
    @Published private(set) var email: String?
    @Published private(set) var busy = false
    @Published var errorMessage: String?
    @Published private(set) var signedIn = false
    private var session: Session?
    private var webSession: ASWebAuthenticationSession?
    private let keychainService = "com.hamad.mawaeed.auth"

    private struct User: Codable { let id: String; let email: String? }
    private struct Session: Codable {
        let access_token: String
        let refresh_token: String
        let user: User
    }

    private var baseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MawaeedAuthURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
    private var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "MawaeedAuthPublicKey") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var configured: Bool { baseURL != nil && !apiKey.isEmpty && !apiKey.hasPrefix("$(") }

    private override init() {
        super.init()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: keychainService,
                                   kSecAttrAccount as String: "session", kSecReturnData as String: true]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let saved = try? JSONDecoder().decode(Session.self, from: data) {
            session = saved
            // A stored identity is verified with the server before it becomes signed in.
        }
    }

    func restoreSession() {
        guard configured, !busy, !signedIn, let saved = session else { return }
        busy = true
        exchange(grant: "refresh_token", body: ["refresh_token": saved.refresh_token], restoring: true)
    }

    func signIn(provider: String) {
        guard !busy, let base = baseURL, configured, ["google", "apple"].contains(provider) else { return }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            errorMessage = "تعذّر بدء تسجيل الدخول. حاول مرة أخرى."; return
        }
        let verifier = Data(bytes).base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var parts = URLComponents(url: base.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "provider", value: provider),
                            URLQueryItem(name: "redirect_to", value: Self.callback),
                            URLQueryItem(name: "code_challenge", value: challenge),
                            URLQueryItem(name: "code_challenge_method", value: "s256")]
        guard let url = parts.url else { return }
        busy = true; errorMessage = nil
        let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: "com.hamad.mawaeed") { [weak self] callback, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.webSession = nil
                if let error = error {
                    self.busy = false
                    if (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        self.errorMessage = "تعذّر تسجيل الدخول. حاول مرة أخرى."
                    }
                    return
                }
                guard let callback = callback, callback.scheme == "com.hamad.mawaeed",
                      callback.host == "auth", callback.path == "/callback",
                      let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
                      let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                    self.busy = false
                    self.errorMessage = "لم يكتمل تسجيل الدخول. تأكد من إعداد مزود الحساب ورابط العودة."
                    return
                }
                self.exchange(grant: "pkce", body: ["auth_code": code, "code_verifier": verifier])
            }
        }
        auth.presentationContextProvider = self
        auth.prefersEphemeralWebBrowserSession = true
        webSession = auth
        if !auth.start() { webSession = nil; busy = false; errorMessage = "تعذّر فتح صفحة تسجيل الدخول." }
    }

    private func exchange(grant: String, body: [String: String], restoring: Bool = false) {
        guard let base = baseURL else { busy = false; return }
        var parts = URLComponents(url: base.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "grant_type", value: grant)]
        var request = URLRequest(url: parts.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.httpBody = try? JSONEncoder().encode(body)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.busy = false
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard error == nil, (200..<300).contains(status), let data = data,
                      let result = try? JSONDecoder().decode(Session.self, from: data) else {
                    if restoring && (status == 400 || status == 401) { self.clearSession() }
                    self.errorMessage = "تعذّر التحقق من الحساب. تأكد من الاتصال وإعدادات الدخول ثم حاول مرة أخرى."
                    return
                }
                guard self.saveSession(result) else {
                    self.errorMessage = "تعذّر حفظ جلسة الدخول بأمان. حاول مرة أخرى."; return
                }
                self.session = result; self.email = result.user.email; self.signedIn = true
            }
        }.resume()
    }

    private func saveSession(_ session: Session) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: keychainService, kSecAttrAccount as String: "session"]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    func signOut() {
        clearSession()
        UserDefaults.standard.set(false, forKey: "welcomePassed")
    }

    private func clearSession() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: keychainService, kSecAttrAccount as String: "session"] as CFDictionary)
        session = nil; email = nil; signedIn = false
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }.flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

