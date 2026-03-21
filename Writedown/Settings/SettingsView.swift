import Combine
import KeyboardShortcuts
import SwiftUI

extension Notification.Name {
    static let autoSaveIntervalDidChange = Notification.Name("autoSaveIntervalDidChange")
}

extension String {
    func truncated(limit: Int = 25) -> String {
        if self.count > limit {
            let index = self.index(self.startIndex, offsetBy: limit - 3)
            return String(self[..<index]) + "..."
        }
        return self
    }
}

struct ContributionCell: View {
    let count: Int
    @Environment(\.colorScheme) var colorScheme

    var color: Color {
        switch count {
        case 0:
            return colorScheme == .dark
                ? Color(.systemGray)
                : Color(.systemGray).opacity(0.2)
        case 1...2:
            return colorScheme == .dark
                ? Color.green.opacity(0.3)
                : Color.green.opacity(0.2)
        case 3...4:
            return colorScheme == .dark
                ? Color.green.opacity(0.5)
                : Color.green.opacity(0.4)
        case 5...6:
            return colorScheme == .dark
                ? Color.green.opacity(0.7)
                : Color.green.opacity(0.6)
        default:
            return colorScheme == .dark
                ? Color.green
                : Color.green.opacity(0.8)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 10, height: 10)
    }
}

struct ContributionGraph: View {
    let contributions: [Date: Int]

    private let columns = Array(repeating: GridItem(.fixed(10), spacing: 4), count: 53)
    private let calendar = Calendar.current
    private var last365Days: [[(date: Date, count: Int)]] {
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -242, to: endDate)!

        let dates = calendar.generateDates(
            inside: DateInterval(start: startDate, end: endDate),
            matching: DateComponents(hour: 0, minute: 0, second: 0)
        ).map { date in
            (date, contributions[date] ?? 0)
        }

        var weeks: [[(Date, Int)]] = []
        var currentWeek: [(Date, Int)] = []

        for (date, count) in dates {
            let weekday = calendar.component(.weekday, from: date)
            let index = (weekday + 5) % 7

            while currentWeek.count < index {
                currentWeek.append((date, 0))
            }
            currentWeek.append((date, count))

            if currentWeek.count == 7 {
                weeks.append(currentWeek)
                currentWeek = []
            }
        }

        if !currentWeek.isEmpty {
            weeks.append(currentWeek)
        }

        return weeks
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(last365Days.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 4) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            ContributionCell(count: day.count)
                                .help(
                                    "\(day.count) notes on \(day.date.formatted(date: .long, time: .omitted))"
                                )
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.trailing, 20)
        }
        .frame(height: 94)
    }
}

extension Calendar {
    func generateDates(
        inside interval: DateInterval,
        matching components: DateComponents
    ) -> [Date] {
        var dates: [Date] = []
        dates.reserveCapacity(365)

        var date = interval.start

        while date <= interval.end {
            if let midnight = self.date(bySettingHour: 0, minute: 0, second: 0, of: date) {
                dates.append(midnight)
            }
            date = self.date(byAdding: .day, value: 1, to: date)!
        }

        return dates
    }
}

class GeneralSettingsViewModel: ObservableObject {
    @Published private(set) var noteCountByDay: [Date: Int] = [:]

    init() {
        loadNoteCountByDay()
    }

    private func loadNoteCountByDay() {
        let calendar = Calendar.current
        var countByDay: [Date: Int] = [:]

        let notes = LocalFileManager.shared.getAllNotes()

        for noteURL in notes {
            do {
                let attributes = try Foundation.FileManager.default.attributesOfItem(
                    atPath: noteURL.path)
                if let creationDate = attributes[.creationDate] as? Date,
                    let normalizedDate = calendar.date(
                        bySettingHour: 0, minute: 0, second: 0, of: creationDate)
                {
                    countByDay[normalizedDate, default: 0] += 1
                }
            } catch {
                print("Error getting file attributes: \(error)")
            }
        }

        noteCountByDay = countByDay
    }
}

struct SettingsView: View {
    enum SettingsTab: String, CaseIterable {
        case general = "通用"
        case integration = "笔记设置"
        case appearance = "外观"
        case hotkeys = "快捷键"
        case about = "关于"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .integration: return "note.text"
            case .appearance: return "paintbrush"
            case .hotkeys: return "keyboard"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selectedTab: SettingsTab? = .general
    @StateObject private var updateManager = UpdateManager.shared

    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

    var body: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                Color.clear
                    .edgesIgnoringSafeArea(.all)
            } else {
                VisualEffectBlur(material: .sidebar)
                    .edgesIgnoringSafeArea(.all)
            }

            NavigationSplitView {
                VStack(spacing: 0) {
                    List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .padding(.vertical, 4)
                    }
                    .listStyle(.sidebar)

                    if updateManager.newVersionAvailable {
                        StandardToastView(
                            icon: "arrow.down.circle.fill",
                            message: L("New Version Available"),
                            explanatoryText: L("Restart to install") + " \(updateManager.remoteVersion != nil ? "v\(updateManager.remoteVersion!)" : "")"
                        )
                        .padding(.horizontal, 4)
                        .onTapGesture {
                            updateManager.installUpdatePackage()
                        }
                    }
                }
                .frame(minWidth: 200)
            } detail: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .general:
                            GeneralSettingsView()
                        case .integration:
                            IntegrationSettingsView()
                        case .appearance:
                            AppearanceSettingsView()
                        case .hotkeys:
                            HotkeySettingsView()
                        case .about:
                            AboutSettingsView(
                                version: version,
                                buildNumber: buildNumber,
                                updater: AutoUpdater()
                            )
                        case .none:
                            EmptyView()
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .frame(width: 900, height: 580)
        .navigationSplitViewStyle(.automatic)
        .toolbar(.automatic)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @StateObject private var viewModel = GeneralSettingsViewModel()
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @AppStorage(AppStorageKeys.launchAtLogin) private var launchAtLogin = AppDefaults.launchAtLogin
    @AppStorage(AppStorageKeys.hasRequestedLaunchPermission) private var hasRequestedPermission = AppDefaults.hasRequestedLaunchPermission
    private let loginManager = LoginManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Account Section removed as login is no longer required
            
            // Preferences Section
            SettingsSectionHeader(title: L("Preferences"), icon: "gearshape")
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L("Launch at login"))
                        Spacer()
                        Toggle("", isOn: $launchAtLogin)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                            .onChange(of: launchAtLogin) { newValue in
                                handleLaunchAtLoginChange(newValue)
                            }
                    }

                    Divider()

                    HStack {
                        Text(L("Language"))
                        Spacer()
                        Picker("", selection: $localizationManager.currentLanguage) {
                            ForEach(LocalizationManager.supportedLanguages) { language in
                                Text(language.name).tag(language)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }
                .padding(12)
            }
        }
    }

    private func handleLaunchAtLoginChange(_ newValue: Bool) {
        if newValue {
            loginManager.requestLaunchPermission { granted in
                if granted {
                    loginManager.enableLaunchAtLogin()
                } else {
                    DispatchQueue.main.async {
                        launchAtLogin = false
                    }
                }
            }
        } else {
            loginManager.disableLaunchAtLogin()
        }
    }
}

// MARK: - Integration Settings (Note Settings)

struct IntegrationSettingsView: View {
    @AppStorage(AppStorageKeys.enableAIRename) private var enableAIRename: Bool = AppDefaults.enableAIRename
    @AppStorage(AppStorageKeys.enableAutoSaveClipboard) private var enableAutoSaveClipboard: Bool = AppDefaults.enableAutoSaveClipboard
    @AppStorage(AppStorageKeys.AIModel) private var AIModel: String = AppDefaults.AIModel
    @State private var miniMaxAPIKey: String = ""
    @State private var isEditingAPIKey: Bool = false
    @AppStorage(AppStorageKeys.editorFont) private var editorFont: String = AppDefaults.editorFont
    @AppStorage(AppStorageKeys.showWordCount) private var showWordCount: Bool = AppDefaults.showWordCount

    @State private var customPath: String = LocalFileManager.shared.currentNotesPath

    private let editorFonts = ["System", "Serif", "Mono", "Heiti"]

    private var allowedModels: [AIModel] {
        AIModelConfig.availableModels
    }

    private var hasMiniMaxAPIKey: Bool {
        !miniMaxAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Storage Section
            SettingsSectionHeader(title: L("Storage"), icon: "folder")
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(L("Location"), systemImage: "folder")
                        Spacer()
                        Text(customPath)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 300, alignment: .trailing)
                        
                        Button(L("Change...")) {
                            selectCustomDirectory()
                        }
                    }

                    Divider()

                    HStack {
                        Label(L("Auto-save interval"), systemImage: "timer")
                        Spacer()
                        AutoSaveIntervalSection()
                    }
                }
                .padding(12)
            }

            // Editor Section
            SettingsSectionHeader(title: L("Editor"), icon: "textformat")
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Font"))
                        .fontWeight(.medium)

                    HStack(spacing: 16) {
                        ForEach(editorFonts, id: \.self) { font in
                            FontOptionView(
                                letter: String(font.prefix(2)),
                                title: font,
                                isSelected: editorFont == font
                            ) {
                                editorFont = font
                            }
                        }
                        Spacer()
                    }
                    
                    Divider()
                    
                    HStack {
                        Text(L("Show Word Count"))
                        Spacer()
                        Toggle("", isOn: $showWordCount)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
                .padding(12)
            }

            // AI Section
            SettingsSectionHeader(title: "AI", icon: "brain")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if hasMiniMaxAPIKey && !isEditingAPIKey {
                        // Configured state — compact
                        HStack {
                            Text("API Key")
                            Spacer()
                            Text("sk-•••" + miniMaxAPIKey.suffix(4))
                                .foregroundColor(.secondary)
                                .font(.callout.monospaced())
                            Button(L("Change")) {
                                isEditingAPIKey = true
                            }
                            .controlSize(.small)
                        }

                        Divider()

                        HStack {
                            Text(L("Auto generate note titles"))
                            Spacer()
                            Toggle("", isOn: $enableAIRename)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        Divider()

                        HStack {
                            Text(L("Auto save important clipboard content"))
                            Spacer()
                            Toggle("", isOn: $enableAutoSaveClipboard)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .controlSize(.small)
                        }
                    } else {
                        // Input state — shown when no key or editing
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MiniMax API Key")

                            HStack(spacing: 8) {
                                TextField(L("Paste your API Key here"), text: $miniMaxAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        commitAPIKey()
                                    }

                                Button(L("Save")) {
                                    commitAPIKey()
                                }
                                .disabled(miniMaxAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                if hasMiniMaxAPIKey {
                                    Button(L("Cancel")) {
                                        miniMaxAPIKey = KeychainHelper.load(key: "com.writedown.minimax-api-key") ?? ""
                                        isEditingAPIKey = false
                                    }
                                }
                            }

                            Button {
                                if let url = URL(string: "https://platform.minimax.io/user-center/basic-information/interface-key") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(L("Get your API Key from MiniMax"))
                                        .font(.caption)
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption2)
                                }
                                .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
            }
            .onAppear {
                miniMaxAPIKey = KeychainHelper.load(key: "com.writedown.minimax-api-key") ?? ""
                validateAIConfiguration()
            }
            .onChange(of: enableAutoSaveClipboard) { newValue in
                if newValue {
                    MaybeLikeService.shared.startMonitoring()
                } else {
                    MaybeLikeService.shared.stopMonitoring()
                }
            }
        }
    }

    private func selectCustomDirectory() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false
        openPanel.title = L("Select Notes Directory")

        if openPanel.runModal() == .OK {
            if let selectedPath = openPanel.url {
                LocalFileManager.shared.setCustomDirectory(selectedPath)
                customPath = selectedPath.path
            }
        }
    }

    private func validateAIModel() {
        if let currentModel = UserDefaults.standard.string(forKey: AppStorageKeys.AIModel) {
            if !allowedModels.contains(where: { $0.modelId == currentModel }) {
                AIModel = allowedModels.first?.modelId ?? "MiniMax-M2.5"
            }
        } else {
            AIModel = allowedModels.first?.modelId ?? "MiniMax-M2.5"
        }
    }

    private func commitAPIKey() {
        let trimmed = miniMaxAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        miniMaxAPIKey = trimmed
        MiniMaxAPI.setAPIKey(trimmed)
        isEditingAPIKey = false

        if trimmed.isEmpty {
            enableAIRename = false
            enableAutoSaveClipboard = false
            MaybeLikeService.shared.stopMonitoring()
        }
    }

    private func validateAIConfiguration() {
        validateAIModel()
    }
}

// MARK: - Hotkey Settings

struct HotkeySettingsView: View {
    @AppStorage(AppStorageKeys.enableDoubleOption) private var enableDoubleOption = AppDefaults.enableDoubleOption

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Wake Up Section
            SettingsSectionHeader(title: L("Wake Up"), icon: "bolt")
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(L("Quick wake-up"), systemImage: "bolt.square")
                        Spacer()
                        KeyboardShortcuts.Recorder("", name: .quickWakeup)
                    }

                    HStack {
                        HStack {
                            Image(systemName: "option")
                                .foregroundColor(.secondary)
                            Text(L("Double press Option key"))
                        }
                        Spacer()
                        Toggle("", isOn: $enableDoubleOption)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                            .help(L("Double press Option key to toggle window"))
                    }

                    Divider()

                    HStack {
                        Label(L("Quick save"), systemImage: "square.and.arrow.down")
                        Spacer()
                        Text(L("Cmd + C (double click)"))
                            .foregroundColor(.secondary)
                    }

                    Divider()
                }
                .padding(12)
            }

            // Note Operations Section
            SettingsSectionHeader(title: L("Note Operations"), icon: "doc.text")
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(L("New Note"), systemImage: "plus")
                        Spacer()
                        KeyboardShortcutBadge(keys: ["Cmd", "Return"])
                    }

                    Divider()

                    HStack {
                        Label(L("Copy All"), systemImage: "doc.on.doc")
                        Spacer()
                        KeyboardShortcutBadge(keys: ["Cmd", "Shift", "C"])
                    }
                }
                .padding(12)
            }

            // Navigation Section
            SettingsSectionHeader(title: L("Navigation"), icon: "arrow.triangle.turn.up.right.diamond")
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(L("History"), systemImage: "clock")
                        Spacer()
                        KeyboardShortcutBadge(keys: ["Cmd", "Shift", "F"])
                    }
                }
                .padding(12)
            }
        }
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    let version: String?
    let buildNumber: String?
    let updater: AutoUpdater

    @Environment(\.colorScheme) var colorScheme
    @State private var isCheckingUpdate = false
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var updateFailed = false
    @State private var latestVersion: String?
    @State private var progressSubscription: AnyCancellable?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // App Identity
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    Image(colorScheme == .dark ? "brand-name-icon-dark" : "brand-name-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 48)

                    Text(String(format: L("Version %@ (Build %@)"), version ?? "Unknown", buildNumber ?? "Unknown"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical)

            // Updates Section
            SettingsSectionHeader(title: L("Updates"), icon: "arrow.clockwise")
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if isDownloading {
                        ProgressView(
                            String(format: L("Downloading... %d%"), Int(downloadProgress * 100)),
                            value: downloadProgress,
                            total: 1.0
                        )
                    } else {
                        HStack {
                            Text(L("Check for updates"))
                            Spacer()
                            Button(isCheckingUpdate ? L("Checking...") : L("Check Now")) {
                                checkForUpdates()
                            }
                            .disabled(isCheckingUpdate)
                        }

                        if updateFailed {
                            Divider()
                            HStack {
                                Label(L("Previous attempt failed"), systemImage: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Spacer()
                                Button(L("Retry")) {
                                    Task {
                                        do {
                                            try updater.deleteDownloadedUpdatePackage()
                                        } catch {
                                            print("Failed to delete downloaded package: \(error)")
                                        }
                                        updateFailed = false
                                        checkForUpdates()
                                    }
                                }
                                .controlSize(.small)
                            }
                        }

                        if let latest = latestVersion {
                            Divider()
                            HStack {
                                Text(L("Latest available"))
                                Spacer()
                                Text(latest)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(12)
            }

            // Support Section
            SettingsSectionHeader(title: L("Support"), icon: "questionmark.circle")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        if let url = URL(string: "https://figmatrackjs-changelog.vercel.app/") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Label(L("Release Notes"), systemImage: "doc.text")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Button {
                        sendFeedback()
                    } label: {
                        HStack {
                            Label(L("Send Feedback"), systemImage: "envelope")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
            }

            // Copyright
            HStack {
                Spacer()
                Text(L("© 2025 ProductLab. All rights reserved."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private func sendFeedback() {
        if let service = NSSharingService(named: .composeEmail) {
            service.recipients = ["team_productlab@outlook.com"]
            service.subject = L("Writedown Feedback")

            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

            let body = """
                App Version: \(appVersion)
                macOS Version: \(osVersion)

                Feedback:

                """

            service.perform(withItems: [body])
        }
    }

    private func checkForUpdates() {
        Task {
            isCheckingUpdate = true
            do {
                let updateInfo = try await updater.checkForUpdates()

                await MainActor.run {
                    let alert = NSAlert()
                    if let updateInfo = updateInfo {
                        guard let downloadURL = URL(string: updateInfo.downloadURL) else {
                            showErrorAlert(message: L("Update failed"), info: L("Invalid download link"))
                            return
                        }

                        alert.messageText = L("New version available")
                        alert.informativeText = String(format: L("Version %@ \n%@"), updateInfo.version, updateInfo.description)
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: L("Update"))
                        alert.addButton(withTitle: L("Later"))

                        let response = alert.runModal()

                        if response == .alertFirstButtonReturn {
                            Task {
                                await downloadAndInstallUpdate(from: downloadURL)
                            }
                        }
                    } else {
                        alert.messageText = L("Check for updates")
                        alert.informativeText = L("You're up to date!")
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            } catch {
                await MainActor.run {
                    updateFailed = true
                    showErrorAlert(message: L("Failed to check for updates"), info: error.localizedDescription)
                }
            }
            isCheckingUpdate = false
        }
    }

    private func downloadAndInstallUpdate(from url: URL) async {
        do {
            isDownloading = true
            downloadProgress = 0

            progressSubscription = updater.progressPublisher
                .receive(on: RunLoop.main)
                .sink { progress in
                    downloadProgress = progress
                }

            let updateFile = try await updater.downloadUpdate(from: url)
            progressSubscription?.cancel()

            try updater.installUpdate(from: updateFile)
            isDownloading = false
        } catch {
            progressSubscription?.cancel()
            isDownloading = false
            updateFailed = true
            showErrorAlert(message: L("Update failed"), info: error.localizedDescription)
        }
    }

    private func showErrorAlert(message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @AppStorage(AppStorageKeys.appearanceMode) private var appearanceMode: AppearanceMode = AppDefaults.appearanceMode

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(title: L("Theme"), icon: "paintbrush")
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Appearance"))
                        .fontWeight(.medium)

                    HStack(spacing: 20) {
                        AppearanceOptionView(
                            image: "system-example",
                            title: "System",
                            isSelected: appearanceMode == .system
                        ) {
                            appearanceMode = .system
                        }

                        AppearanceOptionView(
                            image: "light-example",
                            title: "Light",
                            isSelected: appearanceMode == .light
                        ) {
                            appearanceMode = .light
                        }

                        AppearanceOptionView(
                            image: "dark-example",
                            title: "Dark",
                            isSelected: appearanceMode == .dark
                        ) {
                            appearanceMode = .dark
                        }

                        Spacer()
                    }
                }
                .padding(12)
            }
        }
        .onChange(of: appearanceMode) { newValue in
            NSApp.windows.forEach { window in
                switch newValue {
                case .system:
                    window.appearance = nil
                case .light:
                    window.appearance = NSAppearance(named: .aqua)
                case .dark:
                    window.appearance = NSAppearance(named: .darkAqua)
                }
            }
        }
    }
}

// MARK: - Helper Components

struct SettingsSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundColor(.secondary)
    }
}

struct KeyboardShortcutBadge: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(shortcutSymbol(for: key))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .foregroundColor(.secondary)
    }

    private func shortcutSymbol(for key: String) -> String {
        switch key.lowercased() {
        case "cmd", "command": return "⌘"
        case "shift": return "⇧"
        case "option", "alt": return "⌥"
        case "control", "ctrl": return "⌃"
        case "return", "enter": return "↩"
        default: return key
        }
    }
}

struct AutoSaveIntervalSection: View {
    @AppStorage(AppStorageKeys.autoSaveInterval) private var autoSaveInterval: TimeInterval = AppDefaults.autoSaveInterval

    private let intervals: [(TimeInterval, String)] = [
        (10, "10s"),
        (30, "30s"),
        (60, "1min"),
    ]

    var body: some View {
        Picker("", selection: $autoSaveInterval) {
            ForEach(intervals, id: \.0) { interval in
                Text(interval.1).tag(interval.0)
            }
        }
        .labelsHidden()
        .frame(width: 80)
        .onChange(of: autoSaveInterval) {
            NotificationCenter.default.post(
                name: Notification.Name("autoSaveIntervalDidChange"),
                object: nil
            )
        }
    }
}

struct AppearanceOptionView: View {
    let image: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                Text(title)
                    .font(.caption)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct FontOptionView: View {
    let letter: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    private func getPreviewFont() -> Font {
        switch title {
        case "Mono":
            return .system(size: 20, design: .monospaced)
        case "Heiti":
            return .custom("Heiti SC", size: 20)
        case "Serif":
            return .custom("Songti SC", size: 20)
        default:
            return .custom("PingFang SC", size: 20)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(letter)
                    .font(getPreviewFont())
                    .frame(width: 48, height: 48)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                Text(title)
                    .font(.caption)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
}
