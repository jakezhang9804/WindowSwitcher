import SwiftUI
import Combine
import AppSwitcherKit

@MainActor
class SwitcherViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var searchText: String = ""
    @Published var selectedIndex: Int = 0
    @Published private(set) var windows: [WindowInfo] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var settings: SwitcherSettings = .init()

    // MARK: - Computed Properties

    var filteredWindows: [WindowInfo] {
        if searchText.isEmpty {
            return windows
        }

        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let queryWords = query.split(separator: " ").map(String.init)

        return windows.filter { window in
            let titleLower = window.title.lowercased()
            let appNameLower = window.appName.lowercased()

            return queryWords.allSatisfy { word in
                titleLower.contains(word) || appNameLower.contains(word)
            }
        }
    }

    var totalCount: Int {
        windows.count
    }

    var filteredCount: Int {
        filteredWindows.count
    }

    var selectedWindow: WindowInfo? {
        guard selectedIndex >= 0 && selectedIndex < filteredWindows.count else {
            return nil
        }
        return filteredWindows[selectedIndex]
    }

    var hasResults: Bool {
        !filteredWindows.isEmpty
    }

    // MARK: - Dependencies

    private let windowService: WindowService
    private let settingsStore: any SwitcherSettingsStoring
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        windowService: WindowService,
        settingsStore: any SwitcherSettingsStoring = UserDefaultsSwitcherSettingsStore()
    ) {
        self.windowService = windowService
        self.settingsStore = settingsStore
        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        $searchText
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.selectedIndex = 0
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    func refreshWindows() {
        isLoading = true
        settings = settingsStore.load()

        let allWindows = windowService.getAllWindows()
        windows = allWindows.filter { window in
            settings.allows(bundleID: window.appBundleIdentifier)
        }

        selectedIndex = 0
        isLoading = false
    }

    func selectNext() {
        let maxIndex = filteredWindows.count - 1
        if maxIndex >= 0 {
            selectedIndex = min(selectedIndex + 1, maxIndex)
        }
    }

    func selectPrevious() {
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func selectFirst() {
        selectedIndex = 0
    }

    func selectLast() {
        let maxIndex = filteredWindows.count - 1
        if maxIndex >= 0 {
            selectedIndex = maxIndex
        }
    }

    func selectAtIndex(_ index: Int) {
        guard index >= 0 && index < filteredWindows.count else { return }
        selectedIndex = index
    }

    func activateWindow(_ window: WindowInfo) {
        windowService.activateWindow(window)
    }

    func activateSelectedWindow() {
        if let window = selectedWindow {
            activateWindow(window)
        }
    }

    func activateWindowForPanelTrigger(_ rawInput: String) -> Bool {
        guard let normalizedKey = AppBindingRules.normalizeTriggerKey(rawInput),
              let bundleID = settings.bundleID(for: normalizedKey),
              let targetWindow = windows.first(where: { $0.appBundleIdentifier == bundleID }) else {
            return false
        }

        activateWindow(targetWindow)
        return true
    }

    func clearSearch() {
        searchText = ""
    }
}
