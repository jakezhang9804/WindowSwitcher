import SwiftUI
import Combine

@MainActor
class SwitcherViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var searchText: String = ""
    @Published var selectedIndex: Int = 0
    @Published private(set) var windows: [WindowInfo] = []
    
    // MARK: - Computed Properties
    
    var filteredWindows: [WindowInfo] {
        if searchText.isEmpty {
            return windows
        }
        
        let query = searchText.lowercased()
        return windows.filter { window in
            window.title.lowercased().contains(query) ||
            window.appName.lowercased().contains(query)
        }
    }
    
    var totalCount: Int {
        windows.count
    }
    
    var selectedWindow: WindowInfo? {
        guard selectedIndex >= 0 && selectedIndex < filteredWindows.count else {
            return nil
        }
        return filteredWindows[selectedIndex]
    }
    
    // MARK: - Dependencies
    
    private let windowService: WindowService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(windowService: WindowService) {
        self.windowService = windowService
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Reset selection when search text changes
        $searchText
            .sink { [weak self] _ in
                self?.selectedIndex = 0
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func refreshWindows() {
        windows = windowService.getAllWindows()
        selectedIndex = 0
    }
    
    func selectNext() {
        let maxIndex = filteredWindows.count - 1
        if selectedIndex < maxIndex {
            selectedIndex += 1
        }
    }
    
    func selectPrevious() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }
    
    func activateWindow(_ window: WindowInfo) {
        windowService.activateWindow(window)
    }
}
