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
    private let repoSlug = "yuzhang9804/WindowSwitcher"

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

    // MARK: - Private

    private var timer: Timer?

    private init() {}

    // MARK: - Public API

    /// Start automatic update checking (call once at app launch)
    func startAutomaticChecks() {
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
        }
    }

    /// Open the release page in the default browser
    func openReleasePage() {
        if let url = releaseURL {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open the download URL (DMG/ZIP) in the default browser
    func openDownload() {
        if let url = downloadURL ?? releaseURL {
            NSWorkspace.shared.open(url)
        }
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
            releaseNotes = release.body
            downloadURL = release.assets.first(where: {
                $0.name.hasSuffix(".dmg") || $0.name.hasSuffix(".zip")
            }).flatMap { URL(string: $0.browserDownloadURL) }

            // Compare versions
            let skippedVersion = UserDefaults.standard.string(forKey: skippedVersionKey)
            if isVersion(remoteVersion, newerThan: currentVersion) && remoteVersion != skippedVersion {
                isUpdateAvailable = true
                NSLog("[UpdateService] New version available: \(remoteVersion) (current: \(currentVersion))")
            } else {
                isUpdateAvailable = false
                NSLog("[UpdateService] Up to date (current: \(currentVersion), remote: \(remoteVersion))")
            }
        } catch {
            lastError = error.localizedDescription
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

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    /// Simple semantic version comparison: "1.2.0" > "1.1.0"
    private func isVersion(_ a: String, newerThan b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }

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
        case .invalidURL: return "Invalid GitHub API URL"
        case .invalidResponse: return "Invalid server response"
        case .noReleases: return "No releases found"
        case .httpError(let code): return "HTTP error \(code)"
        }
    }
}
