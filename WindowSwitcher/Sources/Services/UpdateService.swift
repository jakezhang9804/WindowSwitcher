import Foundation
import AppKit

/// Service that checks for new releases on GitHub and notifies the user.
///
/// Update check timing (modeled after Sparkle / common macOS patterns):
/// - On app launch (after a 10-second delay to avoid slowing startup)
/// - Every 4 hours while the app is running
/// - Manually via Settings → About → Check for Updates
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    // MARK: - Configuration

    /// GitHub repository in "owner/repo" format
    private let repoSlug = "jakezhang9804/WindowSwitcher"

    /// UserDefaults keys
    private let lastCheckKey = "UpdateService.lastCheckDate"
    private let skippedVersionKey = "UpdateService.skippedVersion"

    /// Minimum interval between automatic checks (4 hours)
    private let checkInterval: TimeInterval = 4 * 60 * 60

    // MARK: - Published State

    @Published var latestVersion: String?
    @Published var releaseURL: URL?
    @Published var downloadURL: URL?
    @Published var releaseNotes: String?
    @Published var isUpdateAvailable: Bool = false
    @Published var isChecking: Bool = false
    @Published var lastError: String?
    @Published private(set) var hasCompletedCheck = false
    @Published private(set) var hasSkippedLatestVersion = false

    // MARK: - Private

    private var timer: Timer?

    private init() {}

    // MARK: - Public API

    /// Start automatic update checking (call once at app launch)
    func startAutomaticChecks() {
        // Idempotent — never leave a previous timer running
        stopAutomaticChecks()

        // Initial check after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            Task { @MainActor in
                await self?.checkIfNeeded()
            }
        }

        // Periodic check every 4 hours
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkIfNeeded()
            }
        }
    }

    /// Stop automatic checking
    func stopAutomaticChecks() {
        timer?.invalidate()
        timer = nil
    }

    /// Manually trigger an update check (always checks, ignores interval)
    func checkForUpdates() async {
        await performCheck()
    }

    /// Mark the current latest version as skipped
    func skipCurrentUpdate() {
        if let version = latestVersion {
            UserDefaults.standard.set(version, forKey: skippedVersionKey)
            isUpdateAvailable = false
            hasSkippedLatestVersion = true
        }
    }

    /// Open the release page in the default browser
    func openReleasePage() {
        if let url = releaseURL, isTrustedHost(url) {
            if !NSWorkspace.shared.open(url) { lastError = L10n.couldNotOpenUpdateLink }
        } else {
            lastError = L10n.invalidUpdateLink
        }
    }

    /// Open the download URL (DMG/ZIP) in the default browser
    func openDownload() {
        if let url = downloadURL ?? releaseURL, isTrustedHost(url) {
            if !NSWorkspace.shared.open(url) { lastError = L10n.couldNotOpenUpdateLink }
        } else {
            lastError = L10n.invalidUpdateLink
        }
    }

    /// Defense-in-depth: only ever open URLs on GitHub's own hosts, even though
    /// they come from the hardcoded repo's API response
    private func isTrustedHost(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else { return false }
        return host == "github.com"
            || host.hasSuffix(".github.com")
            || host.hasSuffix(".githubusercontent.com")
    }

    // MARK: - Private Methods

    /// Check only if enough time has passed since last check
    private func checkIfNeeded() async {
        let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        let elapsed = Date().timeIntervalSince(lastCheck)

        if elapsed >= checkInterval {
            await performCheck()
        }
    }

    /// Perform the actual GitHub API check
    private func performCheck() async {
        guard !isChecking else { return }
        isChecking = true
        lastError = nil

        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)

            let remoteVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            latestVersion = remoteVersion
            releaseURL = URL(string: release.htmlURL)
            releaseNotes = release.body.map { String($0.prefix(1_200)) }
            let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
            let zip = release.assets.first { $0.name.lowercased().hasSuffix(".zip") }
            downloadURL = (dmg ?? zip).flatMap { URL(string: $0.browserDownloadURL) }
            hasCompletedCheck = true

            // Compare versions
            let skippedVersion = UserDefaults.standard.string(forKey: skippedVersionKey)
            let isNewer = isVersion(remoteVersion, newerThan: currentVersion)
            hasSkippedLatestVersion = isNewer && remoteVersion == skippedVersion
            if isNewer && !hasSkippedLatestVersion {
                isUpdateAvailable = true
                NSLog("[UpdateService] New version available: \(remoteVersion) (current: \(currentVersion))")
            } else {
                isUpdateAvailable = false
                NSLog("[UpdateService] Up to date (current: \(currentVersion), remote: \(remoteVersion))")
            }
        } catch {
            lastError = error.localizedDescription
            hasCompletedCheck = false
            NSLog("[UpdateService] Check failed: \(error.localizedDescription)")
        }
    }

    /// Fetch the latest release from GitHub API
    private func fetchLatestRelease() async throws -> GitHubRelease {
        let urlString = "https://api.github.com/repos/\(repoSlug)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw UpdateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw UpdateError.noReleases
        }

        guard httpResponse.statusCode == 200 else {
            throw UpdateError.httpError(httpResponse.statusCode)
        }

        guard data.count <= 2_000_000 else {
            throw UpdateError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    /// Parse a version into numeric components, tolerating suffixes like
    /// "1.2.0-beta" → [1,2,0] or "1.2.3+build" → [1,2,3] (leading digits per part)
    private func versionComponents(_ s: String) -> [Int] {
        s.split(separator: ".").map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }

    /// Simple semantic version comparison: "1.2.0" > "1.1.0"
    private func isVersion(_ a: String, newerThan b: String) -> Bool {
        let aParts = versionComponents(a)
        let bParts = versionComponents(b)

        let maxLen = max(aParts.count, bParts.count)
        for i in 0..<maxLen {
            let aVal = i < aParts.count ? aParts[i] : 0
            let bVal = i < bParts.count ? bParts[i] : 0
            if aVal > bVal { return true }
            if aVal < bVal { return false }
        }
        return false
    }
}

// MARK: - GitHub API Models

private struct GitHubRelease: Codable {
    let tagName: String
    let htmlUrl: String
    let body: String?
    let assets: [GitHubAsset]

    var htmlURL: String { htmlUrl }
}

private struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String

    var browserDownloadURL: String { browserDownloadUrl }
}

// MARK: - Errors

private enum UpdateError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noReleases
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return L10n.invalidUpdateURL
        case .invalidResponse: return L10n.invalidServerResponse
        case .noReleases: return L10n.noReleasesFound
        case .httpError(let code): return L10n.updateHTTPError(code)
        }
    }
}
