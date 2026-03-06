import SwiftUI
import Combine

@MainActor
class SwitcherViewModel: ObservableObject {
    
    @Published var searchText: String = ""
    @Published var selectedIndex: Int = 0
    @Published private(set) var windows: [WindowInfo] = []
    
    var filteredWindows: [WindowInfo] {
        if searchText.isEmpty { return windows }
        
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
    
    var totalCount: Int { windows.count }
    
    var selectedWindow: WindowInfo? {
        guard selectedIndex >= 0 && selectedIndex < filteredWindows.count else { return nil }
        return filteredWindows[selectedIndex]
    }
    
    private let windowService: WindowService
    private var cancellables = Set<AnyCancellable>()
    
    init(windowService: WindowService) {
        self.windowService = windowService
        
        // Reset selection when search text changes
        $searchText
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.selectedIndex = 0
            }
            .store(in: &cancellables)
    }
    
    func refreshWindows() {
        windows = windowService.getAllWindows()
        selectedIndex = 0
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
    
    func activateWindow(_ window: WindowInfo) {
        windowService.activateWindow(window)
    }
}
