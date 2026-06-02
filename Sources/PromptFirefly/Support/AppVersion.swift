import Foundation

enum AppVersion {
    private static let fallbackVersion = "0.11.3"
    private static let fallbackBuild = "113"

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackVersion
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? fallbackBuild
    }

    static var badgeText: String {
        "v\(marketingVersion)"
    }

    static var displayText: String {
        "Version \(marketingVersion)"
    }
}
