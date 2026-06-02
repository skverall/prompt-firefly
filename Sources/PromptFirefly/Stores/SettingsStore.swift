import Foundation

struct RewriteSettings {
    let apiKey: String
    let baseURL: String
    let model: String
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum DefaultsKey {
        static let baseURL = "deepseek.baseURL"
        static let model = "deepseek.model"
        static let projectFolder = "project.folder"
    }

    @Published var apiKey: String
    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: DefaultsKey.baseURL) }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: DefaultsKey.model) }
    }
    @Published var projectFolder: String {
        didSet { UserDefaults.standard.set(projectFolder, forKey: DefaultsKey.projectFolder) }
    }

    private init() {
        apiKey = (try? KeychainStore.readAPIKey()) ?? ""
        baseURL = UserDefaults.standard.string(forKey: DefaultsKey.baseURL) ?? "https://api.deepseek.com"
        model = UserDefaults.standard.string(forKey: DefaultsKey.model) ?? "deepseek-v4-flash"
        projectFolder = UserDefaults.standard.string(forKey: DefaultsKey.projectFolder) ?? ""
    }

    func saveAPIKey() throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try KeychainStore.deleteAPIKey()
        } else {
            try KeychainStore.saveAPIKey(trimmed)
            guard try KeychainStore.readAPIKey() == trimmed else {
                throw KeychainError.verificationFailed
            }
        }
        apiKey = trimmed
    }

    func snapshot(apiKey: String) -> RewriteSettings {
        RewriteSettings(
            apiKey: apiKey,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
