import Combine
import SwiftUI

extension Notification.Name {
    static let autoSaveIntervalDidChange = Notification.Name("autoSaveIntervalDidChange")
}

struct SettingsView: View {
    enum SettingsTab: String, CaseIterable {
        case account = "Account"
        case integration = "Integration"
        case hotkeys = "Hotkeys"
        case general = "General"
        case about = "About"

        var icon: String {
            switch self {
            case .account: return "person.circle"
            case .integration: return "link"
            case .hotkeys: return "keyboard"
            case .general: return "gear"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selectedTab: SettingsTab = .account
    @State private var progressSubscription: AnyCancellable?
    @State private var autoCorrect = false
    @State private var launchAtLogin = false
    @State private var openInApp = false
    @StateObject private var counter = HotkeyCounter.shared
    @State private var isCheckingUpdate = false
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var latestVersion: String?
    @State private var integrateWithObsidian = true
    @State private var noIntegration = true
    @State private var obsidianVaultPath: String = ""
    @State private var customPath: String = FileManager.shared.currentNotesPath
    @State private var showPathPicker = false
    @State private var showPathAlert = false

    let updater = AutoUpdater()
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

    private func configureObsidianVault() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Select Obsidian Vault"

        if openPanel.runModal() == .OK {
            obsidianVaultPath = openPanel.url?.path ?? ""
        }
    }

    private func selectCustomDirectory() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Select Notes Directory"

        if openPanel.runModal() == .OK {
            if let selectedPath = openPanel.url {
                // Migrate files before setting new directory
//                FileManager.shared.migrateFilesFromDefaultLocation(to: selectedPath)

                // Set new directory
                FileManager.shared.setCustomDirectory(selectedPath)
                customPath = selectedPath.path
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
            }
            .listStyle(.sidebar)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .account:
                        AccountSettingsView()
                    case .integration:
                        IntegrationSettingsView(
                            integrateWithObsidian: $integrateWithObsidian,
                            customPath: $customPath,
                            showPathAlert: $showPathAlert,
                            selectCustomDirectory: selectCustomDirectory
                        )
                    case .hotkeys:
                        HotkeySettingsView(counter: counter)
                    case .general:
                        GeneralSettingsView()
                    case .about:
                        AboutSettingsView(
                            version: version,
                            buildNumber: buildNumber,
                            isCheckingUpdate: $isCheckingUpdate,
                            isDownloading: $isDownloading,
                            downloadProgress: $downloadProgress,
                            latestVersion: latestVersion,
                            updater: updater,
                            progressSubscription: $progressSubscription
                        )
                    }
                }
                .padding()
            }
        }
        .alert("Configure Obsidian Folder", isPresented: $showPathAlert) {
            Button("Select") {
                selectCustomDirectory()
            }
        } message: {
            Text("Float defaultly integrate with obsidian. Pick a folder in Obsidian dictionary.")
        }
        .navigationSplitViewStyle(.automatic)
        .toolbar(.automatic)
    }
}

// MARK: - Subviews

struct AccountSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Account", systemImage: "envelope")
                Spacer()
                Text("Not Logging in")
                    .foregroundColor(.gray)
            }

            HStack {
                Label("Plan", systemImage: "plus.square")
                Spacer()
                Text("Free")
                    .foregroundColor(.gray)
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)
            }
        }
    }
}

struct IntegrationSettingsView: View {
    @Binding var integrateWithObsidian: Bool
    @Binding var customPath: String
    @Binding var showPathAlert: Bool
    let selectCustomDirectory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image("obsidian-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                Text("Obsidian")
                Spacer()
            }

            if integrateWithObsidian {
                if !FileManager.shared.isPathConfigured {
                    Text("Please select a storage location")
                        .foregroundColor(.red)
                        .padding(.leading, 20)
                        .onAppear {
                            showPathAlert = true
                        }
                }

                VStack(alignment: .leading) {
                    // HStack {
                    //     Text("Configure your Obsidian folder:")
                    //         .foregroundColor(.secondary)
                    //     Text(customPath)
                    //         .lineLimit(1)
                    //         .truncationMode(.middle)
                    // }

                    Button("Configure Obsidian folder") {
                        selectCustomDirectory()
                    }
                }
                .padding(.leading, 20)
            }

            HStack {
                Image("notion-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                Text("Notion")
                Spacer()
                Text("Coming soon")
                    .foregroundColor(.gray)
            }
            .opacity(0.5)
        }
    }
}

struct HotkeySettingsView: View {
    @ObservedObject var counter: HotkeyCounter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack {
                HStack {
                    Label("Quick wake-up", systemImage: "bolt.square")
                    Spacer()
                    Text("⌥ + C")
                        .foregroundColor(.gray)
                }
                HStack {
                    Spacer()
                    Text("Today used:\(counter.todayCount)/25").opacity(0.5)
                    Button("Unlimited in Hyper +") {
                        // Handle upgrade action
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)
                }
            }

            HStack {
                Label("History", systemImage: "clock")
                Spacer()
                Text("⌘ + H / ⌘ + F")
                    .foregroundColor(.gray)
            }

            HStack {
                Label("New Note", systemImage: "plus")
                Spacer()
                Text(" ⌘ + ⏎ / ⌘ + N / ⌘ + K")
                    .foregroundColor(.gray)
            }
        }
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Language", systemImage: "globe")
                Spacer()
                Text("English")
                    .foregroundColor(.gray)
            }

            HStack {
                Label("Auto-save Interval", systemImage: "timer")
                Spacer()
                AutoSaveIntervalSection()
            }
        }
    }
}

struct AboutSettingsView: View {
    let version: String?
    let buildNumber: String?
    @Binding var isCheckingUpdate: Bool
    @Binding var isDownloading: Bool
    @Binding var downloadProgress: Double
    let latestVersion: String?
    let updater: AutoUpdater
    @Binding var progressSubscription: AnyCancellable?

    var body: some View {
        VStack {
            if isDownloading {
                ProgressView(
                    "Downloading...\(Int(downloadProgress * 100))%",
                    value: downloadProgress,
                    total: 1.0
                )
                .progressViewStyle(.linear)
                .frame(width: 200)
                .padding()
            } else {
                Button(isCheckingUpdate ? "Checking..." : "Check for updates") {
                    checkForUpdates()
                }
                .disabled(isCheckingUpdate)
            }

            if let latest = latestVersion {
                Text("Latest version: \(latest)")
                    .opacity(0.25)
            }
            Text("Current version: \(version ?? "") build\(buildNumber ?? "")")
                .opacity(0.25)
        }
    }

    private func checkForUpdates() {
        Task {
            isCheckingUpdate = true
            print("checking update")
            do {
                let updateInfo = try await updater.checkForUpdates()

                await MainActor.run {
                    let alert = NSAlert()
                    if let updateInfo = updateInfo {
                        guard let downloadURL = URL(string: updateInfo.downloadURL) else {
                            print("Invalid download URL: \(updateInfo.downloadURL)")
                            let errorAlert = NSAlert()
                            errorAlert.messageText = "Update failed"
                            errorAlert.informativeText = "Invalid download link"
                            errorAlert.alertStyle = .critical
                            errorAlert.addButton(withTitle: "OK")
                            errorAlert.runModal()
                            return
                        }

                        alert.messageText = "New version available"
                        alert.informativeText = """
                            Version \(updateInfo.version)
                            \(updateInfo.description)
                            """
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "Update")
                        alert.addButton(withTitle: "Later")

                        let response = alert.runModal()

                        if response == .alertFirstButtonReturn {
                            Task {
                                do {
                                    isDownloading = true
                                    downloadProgress = 0

                                    // Start download and monitor progress
                                    progressSubscription = updater.progressPublisher
                                        .receive(on: RunLoop.main)
                                        .sink { progress in
                                            downloadProgress = progress
                                        }

                                    let updateFile = try await updater.downloadUpdate(from: downloadURL)
                                    progressSubscription?.cancel()

                                    try updater.installUpdate(from: updateFile)
                                    isDownloading = false
                                } catch {
                                    progressSubscription?.cancel()
                                    isDownloading = false
                                    let errorAlert = NSAlert()
                                    errorAlert.messageText = "Update failed"
                                    errorAlert.informativeText = error.localizedDescription
                                    errorAlert.alertStyle = .critical
                                    errorAlert.addButton(withTitle: "OK")
                                    errorAlert.runModal()
                                }
                            }
                        }
                    } else {
                        alert.messageText = "Check for updates"
                        alert.informativeText = "You're up to date!"
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Failed to check for updates"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
            isCheckingUpdate = false
        }
    }
}

struct AutoSaveIntervalSection: View {
    @AppStorage("autoSaveInterval") private var autoSaveInterval: TimeInterval = 10

    private let intervals = [
        (2, "2s"),
        (5, "5s"),
        (10, "10s"),
        (20, "20s")
    ]

    var body: some View {
        Picker("", selection: $autoSaveInterval) {
            ForEach(intervals, id: \.0) { interval in
                Text(interval.1).tag(TimeInterval(interval.0))
            }
        }
        .frame(width: 70)
        .onChange(of: autoSaveInterval) {
            NotificationCenter.default.post(
                name: Notification.Name("autoSaveIntervalDidChange"),
                object: nil
            )
        }
    }
}

#Preview {
    SettingsView()
}
