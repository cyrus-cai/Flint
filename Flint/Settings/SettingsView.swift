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
        case editor = "编辑器"
        case ai = "AI"
        case hotkeys = "快捷键"
        case about = "关于"
    }

    @State private var selectedTab: SettingsTab? = .general
    @StateObject private var updateManager = UpdateManager.shared

    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

    @Environment(\.colorScheme) private var colorScheme

    private var settingsBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.14, blue: 0.12)
            : Color(red: 1.0, green: 0.973, blue: 0.906) // #FFF8E7
    }

    var body: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                settingsBackgroundColor
                    .edgesIgnoringSafeArea(.all)
            } else {
                settingsBackgroundColor
                    .edgesIgnoringSafeArea(.all)
            }

            NavigationSplitView {
                VStack(spacing: 0) {
                    List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                        Text(tab.rawValue)
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
                        case .editor:
                            EditorSettingsView()
                        case .ai:
                            AISettingsView()
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
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
                .background(settingsBackgroundColor)
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

// MARK: - Editor Settings

struct EditorSettingsView: View {
    @AppStorage(AppStorageKeys.editorFont) private var editorFont: String = AppDefaults.editorFont
    @AppStorage(AppStorageKeys.showWordCount) private var showWordCount: Bool = AppDefaults.showWordCount
    @AppStorage(AppStorageKeys.appearanceMode) private var appearanceMode: AppearanceMode = AppDefaults.appearanceMode
    @AppStorage(AppStorageKeys.windowTransparent) private var windowTransparent: Bool = AppDefaults.windowTransparent

    @State private var customPath: String = LocalFileManager.shared.currentNotesPath

    private let editorFonts = ["System", "Serif", "Mono", "Heiti"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Theme Section
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

                    Divider()

                    Toggle(L("Liquid Glass style"), isOn: $windowTransparent)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(12)
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

            // Font Section
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

            // Storage Section
            SettingsSectionHeader(title: L("Storage"), icon: "folder")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L("Location"))
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
                        Text(L("Auto-save interval"))
                        Spacer()
                        AutoSaveIntervalSection()
                    }
                }
                .padding(12)
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
}

// MARK: - AI Settings

struct AISettingsView: View {
    @AppStorage(AppStorageKeys.AIProvider) private var selectedProviderRaw: String = AppDefaults.AIProviderDefault
    @State private var selectedModelId: String = ""
    @State private var apiKey: String = ""
    @State private var isEditingAPIKey: Bool = false
    /// Whether a key is confirmed persisted in Keychain (not just typed in the field).
    @State private var hasPersistedAPIKey: Bool = false
    @State private var enableAIRename: Bool = false
    @State private var enableAutoSaveClipboard: Bool = false
    @State private var mcpRegistered: Bool = false

    private var provider: AIProvider {
        AIProvider(rawValue: selectedProviderRaw) ?? .minimax
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(title: "AI", icon: "brain")

            // Provider, Model, API Key
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    // Provider picker
                    HStack {
                        Text(L("Provider"))
                        Spacer()
                        Picker("", selection: $selectedProviderRaw) {
                            ForEach(AIProvider.allCases) { p in
                                Text(p.displayName).tag(p.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }

                    Divider()

                    // Model picker
                    HStack {
                        Text(L("Model"))
                        Spacer()
                        Picker("", selection: $selectedModelId) {
                            ForEach(provider.models) { model in
                                Text(model.displayName).tag(model.modelId)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    Divider()

                    // API Key
                    if hasPersistedAPIKey && !isEditingAPIKey {
                        HStack {
                            Text("API Key")
                            Spacer()
                            Text("sk-•••" + apiKey.suffix(4))
                                .foregroundColor(.secondary)
                                .font(.callout.monospaced())
                            Button(L("Change")) {
                                isEditingAPIKey = true
                            }
                            .controlSize(.small)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key")

                            HStack(spacing: 8) {
                                TextField(L("Paste your API Key here"), text: $apiKey)
                                    .textFieldStyle(.roundedBorder)

                                Button(L("Save")) {
                                    commitAPIKey()
                                }
                                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                if isEditingAPIKey {
                                    Button(L("Cancel")) {
                                        apiKey = MiniMaxAPI.loadAPIKey(for: provider)
                                        isEditingAPIKey = false
                                    }
                                }
                            }

                            Button {
                                if let url = URL(string: provider.websiteURL) {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(L("Get your API Key"))
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

            // Feature toggles
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L("Auto generate note titles"))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { enableAIRename },
                            set: { newValue in
                                enableAIRename = newValue
                                UserDefaults.standard.set(newValue, forKey: provider.enableAIRenameKey)
                                // Sync to global key for external readers
                                UserDefaults.standard.set(newValue, forKey: AppStorageKeys.enableAIRename)
                            }
                        ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                            .disabled(!hasPersistedAPIKey)
                    }

                    Divider()

                    HStack {
                        Text(L("Auto save important clipboard content"))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { enableAutoSaveClipboard },
                            set: { newValue in
                                enableAutoSaveClipboard = newValue
                                UserDefaults.standard.set(newValue, forKey: provider.enableAutoSaveClipboardKey)
                                // Sync to global key for external readers
                                UserDefaults.standard.set(newValue, forKey: AppStorageKeys.enableAutoSaveClipboard)
                                if newValue {
                                    MaybeLikeService.shared.startMonitoring()
                                } else {
                                    MaybeLikeService.shared.stopMonitoring()
                                }
                            }
                        ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                            .disabled(!hasPersistedAPIKey)
                    }
                }
                .padding(12)
            }

            // MCP Server
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("MCP Server")
                            Text("Claude Code")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Circle()
                            .fill(mcpRegistered ? Color.green : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                        if mcpRegistered {
                            Button(L("Unregister")) {
                                unregisterMCPServer()
                            }
                            .controlSize(.small)
                        } else {
                            Button(L("Register")) {
                                registerMCPServer()
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding(12)
            }
        }
        .onAppear {
            loadProviderState()
            mcpRegistered = isMCPServerRegistered()
        }
        .onChange(of: selectedProviderRaw) { _ in
            // Provider switched: load its key and model, post notification
            loadProviderState()
            isEditingAPIKey = false
            NotificationCenter.default.post(name: .aiProviderDidChange, object: nil)
        }
        .onChange(of: selectedModelId) { newValue in
            // Persist model selection for current provider
            UserDefaults.standard.set(newValue, forKey: provider.modelStorageKey)
        }
    }

    private func loadProviderState() {
        apiKey = MiniMaxAPI.loadAPIKey(for: provider)
        hasPersistedAPIKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Load persisted model for this provider, or fall back to default
        let storedModel = UserDefaults.standard.string(forKey: provider.modelStorageKey)
        if let storedModel, provider.models.contains(where: { $0.modelId == storedModel }) {
            selectedModelId = storedModel
        } else {
            selectedModelId = provider.defaultModelId
            UserDefaults.standard.set(selectedModelId, forKey: provider.modelStorageKey)
        }

        // Migrate legacy global toggles to per-provider (one-time)
        let ud = UserDefaults.standard
        let migrationKey = "didMigratePerProviderToggles"
        if !ud.bool(forKey: migrationKey) {
            let globalRename = ud.bool(forKey: AppStorageKeys.enableAIRename)
            let globalClipboard = ud.bool(forKey: AppStorageKeys.enableAutoSaveClipboard)
            if globalRename || globalClipboard {
                // Apply old global setting to whichever provider was active
                let activeProvider = AIProvider(rawValue: ud.string(forKey: AppStorageKeys.AIProvider) ?? "") ?? .minimax
                ud.set(globalRename, forKey: activeProvider.enableAIRenameKey)
                ud.set(globalClipboard, forKey: activeProvider.enableAutoSaveClipboardKey)
            }
            ud.set(true, forKey: migrationKey)
        }

        // Load per-provider feature toggles
        enableAIRename = ud.bool(forKey: provider.enableAIRenameKey)
        enableAutoSaveClipboard = ud.bool(forKey: provider.enableAutoSaveClipboardKey)

        // Sync global keys so external readers see the current provider's settings
        UserDefaults.standard.set(enableAIRename, forKey: AppStorageKeys.enableAIRename)
        UserDefaults.standard.set(enableAutoSaveClipboard, forKey: AppStorageKeys.enableAutoSaveClipboard)

        if enableAutoSaveClipboard && hasPersistedAPIKey {
            MaybeLikeService.shared.startMonitoring()
        } else {
            MaybeLikeService.shared.stopMonitoring()
        }
    }

    private func commitAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = trimmed

        guard MiniMaxAPI.setAPIKey(trimmed, for: provider) else { return }

        // Verify the key was actually persisted to Keychain before updating UI
        let persisted = MiniMaxAPI.loadAPIKey(for: provider)
        guard persisted == trimmed else { return }

        hasPersistedAPIKey = !trimmed.isEmpty
        isEditingAPIKey = false

        if trimmed.isEmpty {
            enableAIRename = false
            enableAutoSaveClipboard = false
            UserDefaults.standard.set(false, forKey: provider.enableAIRenameKey)
            UserDefaults.standard.set(false, forKey: provider.enableAutoSaveClipboardKey)
            UserDefaults.standard.set(false, forKey: AppStorageKeys.enableAIRename)
            UserDefaults.standard.set(false, forKey: AppStorageKeys.enableAutoSaveClipboard)
            MaybeLikeService.shared.stopMonitoring()
        }
    }

    // MARK: - MCP Server Registration

    /// Claude Code reads user-scope MCP servers from ~/.claude.json
    private static let claudeConfigPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude.json"
    }()

    private static var mcpServerScript: String {
        let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("FlintMCP")
            .appendingPathComponent("server.mjs").path
        return bundled ?? "/Applications/Flint.app/Contents/Resources/FlintMCP/server.mjs"
    }

    private func isMCPServerRegistered() -> Bool {
        guard let data = FileManager.default.contents(atPath: Self.claudeConfigPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else {
            return false
        }
        return servers["flint-notes"] != nil
    }

    /// Find node binary — GUI apps have a minimal PATH, so check common locations.
    private static func findNode() -> String? {
        let candidates = [
            "/opt/homebrew/bin/node",       // Apple Silicon Homebrew
            "/usr/local/bin/node",          // Intel Homebrew / official installer
            nvmNodePath(),                  // NVM
            "/usr/bin/node",                // Xcode CLT / system
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Resolve the node binary from NVM by picking the latest installed version.
    private static func nvmNodePath() -> String? {
        let nvmDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".nvm/versions/node")
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir.path) else {
            return nil
        }
        // Sort version dirs descending so the latest comes first
        guard let latest = versions.filter({ $0.hasPrefix("v") }).sorted(by: >).first else {
            return nil
        }
        let path = nvmDir.appendingPathComponent(latest).appendingPathComponent("bin/node").path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private func registerMCPServer() {
        guard let nodePath = Self.findNode() else {
            showMCPError("Node.js is required but not found.\nInstall it from https://nodejs.org or run:\nbrew install node")
            return
        }

        do {
            let fm = FileManager.default
            let configPath = Self.claudeConfigPath
            let configURL = URL(fileURLWithPath: configPath)

            // Read existing config or start with empty object
            var json: [String: Any] = [:]
            if let data = fm.contents(atPath: configPath) {
                let parsed = try JSONSerialization.jsonObject(with: data)
                guard let obj = parsed as? [String: Any] else {
                    showMCPError("~/.claude.json exists but is not a JSON object. Please fix it manually.")
                    return
                }
                json = obj
            }

            // Pre-bundled single file — use absolute node path for reliability
            var servers = json["mcpServers"] as? [String: Any] ?? [:]
            servers["flint-notes"] = [
                "command": nodePath,
                "args": [Self.mcpServerScript],
            ] as [String: Any]
            json["mcpServers"] = servers

            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configURL)

            // Verify the write stuck
            if isMCPServerRegistered() {
                mcpRegistered = true
            } else {
                showMCPError("Registration appeared to succeed but verification failed.")
            }
        } catch {
            showMCPError("Failed to register: \(error.localizedDescription)")
        }
    }

    private func unregisterMCPServer() {
        do {
            let fm = FileManager.default
            let configPath = Self.claudeConfigPath
            let configURL = URL(fileURLWithPath: configPath)

            guard let data = fm.contents(atPath: configPath),
                  var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                mcpRegistered = false
                return
            }

            if var servers = json["mcpServers"] as? [String: Any] {
                servers.removeValue(forKey: "flint-notes")
                json["mcpServers"] = servers
            }

            let newData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try newData.write(to: configURL)
            mcpRegistered = false
        } catch {
            showMCPError("Failed to unregister: \(error.localizedDescription)")
        }
    }

    private func showMCPError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "MCP Registration Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
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
                        Text(L("Quick wake-up"))
                        Spacer()
                        KeyboardShortcuts.Recorder("", name: .quickWakeup)
                    }

                    HStack {
                        Text(L("Double press Option key"))
                        Spacer()
                        Toggle("", isOn: $enableDoubleOption)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                            .help(L("Double press Option key to toggle window"))
                    }

                    Divider()

                    HStack {
                        Text(L("Quick save"))
                        Spacer()
                        Text(L("Cmd + C (double click)"))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
            }

            // Note Operations Section
            SettingsSectionHeader(title: L("Note Operations"), icon: "doc.text")
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L("New Note"))
                        Spacer()
                        KeyboardShortcutBadge(keys: ["Cmd", "Return"])
                    }

                    Divider()

                    HStack {
                        Text(L("Copy All"))
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
                        Text(L("History"))
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
                                Text(L("Previous attempt failed"))
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
                            Text(L("Release Notes"))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Button {
                        WindowManager.shared.replayOnboarding()
                    } label: {
                        HStack {
                            Text(L("Replay Onboarding"))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()

                    Button {
                        sendFeedback()
                    } label: {
                        HStack {
                            Text(L("Send Feedback"))
                            Spacer()
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
                Text(L("© 2026 Flint. All rights reserved."))
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
            service.subject = L("Flint Feedback")

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

// MARK: - Helper Components

struct SettingsSectionHeader: View {
    let title: String
    var icon: String = ""

    var body: some View {
        Text(title)
            .font(.custom("Georgia", size: 16).weight(.semibold))
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
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .foregroundColor(.accentColor)
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
