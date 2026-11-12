import AppKit
import Combine
import ServiceManagement
import Sparkle

enum Pref {
    static let showNetworkName = "showNetworkName"
    static let dimOfflineIcon = "dimOfflineIcon"
    static let showHoverDetails = "showHoverDetails"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showNetworkName: false,
            dimOfflineIcon: true,
            showHoverDetails: true,
        ])
    }
}

enum AppInfo {
    static let name = "EtherDot"
    static let author = "Tiago Figueiredo"
    static var repositoryURL: URL {
        let configured = Bundle.main.object(forInfoDictionaryKey: "EDRepositoryURL") as? String
        return URL(string: configured ?? "https://github.com/tfig-dev/EtherDot")!
    }
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

/// Sparkle wrapper. Updates come from the appcast attached to the latest GitHub Release.
@MainActor
final class Updater: ObservableObject {
    @Published private(set) var canCheck = false
    @Published private(set) var lastCheck: Date?

    private let controller: SPUStandardUpdaterController?
    private var observers: Set<AnyCancellable> = []

    /// False when running outside the app bundle (e.g. `swift run`), where there is no feed.
    var isAvailable: Bool { controller != nil }

    init() {
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheck = $0 }
            .store(in: &observers)
        controller.updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.lastCheck = $0 }
            .store(in: &observers)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
    }

    var automaticallyDownloads: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { controller?.updater.automaticallyDownloadsUpdates = newValue; objectWillChange.send() }
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}

/// "Launch at Login" through SMAppService (macOS 13+): no helper app needed.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published var errorMessage: String?

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func set(_ on: Bool) {
        errorMessage = nil
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
        if needsApproval { SystemSettings.openLoginItems() }
    }

    func toggle() { set(!enabled) }
}
