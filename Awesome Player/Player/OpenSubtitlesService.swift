/// OpenSubtitles REST client.
///
/// OpenSubtitles is the canonical free subtitle database; their REST v1 API
/// requires (a) an API key registered at opensubtitles.com and (b) a user
/// login for the download endpoint. The search endpoint can be hit
/// unauthenticated but rate-limits aggressively.
///
/// Auth flow:
///   POST /login → token (cached in memory for the session)
///   Authorization: Bearer <token> on subsequent requests
///
/// The API key + password live in the user's login Keychain (a generic
/// password keyed by service name); username is stored in UserDefaults
/// since it's not sensitive and is needed to look up the password's
/// account field. Earlier versions stored everything in UserDefaults
/// plaintext, which any other app on the machine could read.
///
/// API docs: https://opensubtitles.stoplight.io/docs/opensubtitles-api/
import Foundation
import Security

enum OpenSubtitlesService {
    private static let baseURL = "https://api.opensubtitles.com/api/v1"
    private static var cachedToken: String?

    struct SubtitleResult {
        let fileID: Int
        let language: String
        let release: String
        let downloadCount: Int
    }

    enum ServiceError: Error, LocalizedError {
        case missingAPIKey
        case missingCredentials
        case loginFailed(String)
        case searchFailed(String)
        case downloadFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return L("OpenSubtitles API key is not set. Add it in Preferences → Subtitles.")
            case .missingCredentials: return L("OpenSubtitles username/password is not set.")
            case .loginFailed(let msg): return String(format: L("Login failed: %@"), msg)
            case .searchFailed(let msg): return String(format: L("Search failed: %@"), msg)
            case .downloadFailed(let msg): return String(format: L("Download failed: %@"), msg)
            }
        }
    }

    // MARK: - Public surface

    static func search(query: String, languages: [String] = ["en"], completion: @escaping (Result<[SubtitleResult], Error>) -> Void) {
        guard let apiKey = storedAPIKey() else {
            completion(.failure(ServiceError.missingAPIKey))
            return
        }
        var components = URLComponents(string: "\(baseURL)/subtitles")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "languages", value: languages.joined(separator: ",")),
        ]
        var req = URLRequest(url: components.url!, timeoutInterval: 15)
        req.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        req.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error {
                completion(.failure(ServiceError.searchFailed(error.localizedDescription))); return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["data"] as? [[String: Any]] else {
                completion(.failure(ServiceError.searchFailed("Unexpected response"))); return
            }
            let results: [SubtitleResult] = items.compactMap { item in
                guard let attrs = item["attributes"] as? [String: Any],
                      let files = attrs["files"] as? [[String: Any]],
                      let fileID = files.first?["file_id"] as? Int else { return nil }
                let lang = (attrs["language"] as? String) ?? "?"
                let release = (attrs["release"] as? String) ?? "?"
                let dc = (attrs["download_count"] as? Int) ?? 0
                return SubtitleResult(fileID: fileID, language: lang, release: release, downloadCount: dc)
            }
            completion(.success(results))
        }.resume()
    }

    /// Downloads the subtitle to a temporary file and returns its URL. Caller
    /// is responsible for moving / loading the file.
    static func download(fileID: Int, completion: @escaping (Result<URL, Error>) -> Void) {
        ensureLoggedIn { loginResult in
            switch loginResult {
            case .failure(let err): completion(.failure(err))
            case .success(let token):
                requestDownloadLink(fileID: fileID, token: token) { linkResult in
                    switch linkResult {
                    case .failure(let err): completion(.failure(err))
                    case .success(let link):
                        downloadFile(from: link, completion: completion)
                    }
                }
            }
        }
    }

    // MARK: - Credentials storage (Keychain-backed)

    /// All Keychain items live under this service string. The account field
    /// disambiguates the API key vs. the user password.
    private static let keychainService = "com.awesomeplayer.opensubs"
    private static let apiKeyAccount = "apiKey"
    private static let passwordAccount = "userPassword"

    static func storedAPIKey() -> String? {
        keychainRead(account: apiKeyAccount)
    }

    static func setAPIKey(_ key: String) {
        keychainWrite(account: apiKeyAccount, value: key)
        cachedToken = nil
    }

    static func storedUsername() -> String? {
        // Username isn't sensitive; UserDefaults is fine and lets the
        // Preferences pane's NSTextField bind directly.
        UserDefaults.standard.string(forKey: "opensubs.username").flatMap { $0.isEmpty ? nil : $0 }
    }

    static func storedPassword() -> String? {
        keychainRead(account: passwordAccount)
    }

    static func setCredentials(username: String, password: String) {
        UserDefaults.standard.set(username, forKey: "opensubs.username")
        keychainWrite(account: passwordAccount, value: password)
        cachedToken = nil
    }

    // MARK: - Keychain helpers

    private static func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    private static func keychainRead(account: String) -> String? {
        var query = keychainQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }

    private static func keychainWrite(account: String, value: String) {
        let data = value.data(using: .utf8) ?? Data()
        if value.isEmpty {
            SecItemDelete(keychainQuery(account: account) as CFDictionary)
            return
        }
        // Upsert: try update first, fall back to add if no existing item.
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(keychainQuery(account: account) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = keychainQuery(account: account)
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    // MARK: - Internals

    private static func userAgent() -> String {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        return "AwesomePlayer v\(version)"
    }

    private static func ensureLoggedIn(completion: @escaping (Result<String, Error>) -> Void) {
        if let cached = cachedToken {
            completion(.success(cached)); return
        }
        guard let apiKey = storedAPIKey() else {
            completion(.failure(ServiceError.missingAPIKey)); return
        }
        guard let user = storedUsername(), let pass = storedPassword() else {
            completion(.failure(ServiceError.missingCredentials)); return
        }

        var req = URLRequest(url: URL(string: "\(baseURL)/login")!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        req.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["username": user, "password": pass]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error {
                completion(.failure(ServiceError.loginFailed(error.localizedDescription))); return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String else {
                let msg = String(data: data ?? Data(), encoding: .utf8) ?? "Unknown error"
                completion(.failure(ServiceError.loginFailed(msg))); return
            }
            cachedToken = token
            completion(.success(token))
        }.resume()
    }

    private static func requestDownloadLink(fileID: Int, token: String, completion: @escaping (Result<URL, Error>) -> Void) {
        var req = URLRequest(url: URL(string: "\(baseURL)/download")!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue(storedAPIKey() ?? "", forHTTPHeaderField: "Api-Key")
        req.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["file_id": fileID]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error {
                completion(.failure(ServiceError.downloadFailed(error.localizedDescription))); return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let link = json["link"] as? String,
                  let url = URL(string: link) else {
                completion(.failure(ServiceError.downloadFailed("Could not parse download link"))); return
            }
            completion(.success(url))
        }.resume()
    }

    private static func downloadFile(from url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            if let error = error {
                completion(.failure(ServiceError.downloadFailed(error.localizedDescription))); return
            }
            guard let tempURL = tempURL else {
                completion(.failure(ServiceError.downloadFailed("No file received"))); return
            }
            // Move to a stable temp location with a sensible extension. The
            // header sometimes provides filename via Content-Disposition; if
            // not, default to .srt (the most common format).
            var ext = "srt"
            if let suggested = (response as? HTTPURLResponse)?.suggestedFilename, let dot = suggested.lastIndex(of: ".") {
                ext = String(suggested[suggested.index(after: dot)...])
            }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("opensubs-\(UUID().uuidString).\(ext)")
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
                completion(.success(dest))
            } catch {
                completion(.failure(ServiceError.downloadFailed(error.localizedDescription)))
            }
        }.resume()
    }
}
