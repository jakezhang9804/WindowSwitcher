public protocol AppCatalogProviding {
    func fetchInstalledApps() -> [InstalledApp]
}
