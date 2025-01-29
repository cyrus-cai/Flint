import Combine
import SwiftUI

extension Notification.Name {
    static let autoSaveIntervalDidChange = Notification.Name("autoSaveIntervalDidChange")
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

    // Change to 53 columns (approximately 1 year of weeks)
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

        // Group dates into weeks (7 days each)
        var weeks: [[(Date, Int)]] = []
        var currentWeek: [(Date, Int)] = []

        for (date, count) in dates {
            let weekday = calendar.component(.weekday, from: date)
            // Adjust index to match your desired start day (1 = Sunday, 2 = Monday, etc.)
            let index = (weekday + 5) % 7  // This makes Monday first day

            while currentWeek.count < index {
                currentWeek.append((date, 0))  // Fill in missing days
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
            // Add some padding at the end to ensure the last column is fully visible
            .padding(.trailing, 20)
        }
        // Set a fixed frame height to prevent vertical scrolling
        .frame(height: 94)
    }
}

// Helper extension for Calendar
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

        // 获取所有笔记
        let notes = FileManager.shared.getAllNotes()

        // 按日期分组计数
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
        case general = "General"
        case integration = "Note Settings"
        case hotkeys = "Hotkeys"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .integration: return "note.text"
            case .hotkeys: return "keyboard"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selectedTab: SettingsTab = .general
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

    // Feishu related settings
    //    @AppStorage("FeishuSyncEnabled") private var feishuSyncEnabled = false
    //    @State private var feishuAccessToken = ""
    //    @State private var showFeishuTokenAlert = false

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
            UserDefaults.standard.set(obsidianVaultPath, forKey: "obsidianVaultPath")
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
                    case .general:
                        GeneralSettingsView()
                    case .integration:
                        IntegrationSettingsView(
                            integrateWithObsidian: $integrateWithObsidian,
                            customPath: $customPath,
                            showPathAlert: $showPathAlert,
                            selectCustomDirectory: selectCustomDirectory
                        )
                    case .hotkeys:
                        HotkeySettingsView(counter: counter)
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
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    "Float defaultly integrates with Obsidian. Pick a folder in your Obsidian vault."
                )
            }
        }
        .frame(width: 800, height: 500)
        .navigationSplitViewStyle(.automatic)
        .toolbar(.automatic)
    }
}

// MARK: - Subviews

struct GeneralSettingsView: View {
    @StateObject private var viewModel = GeneralSettingsViewModel()
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("hasRequestedLaunchPermission") private var hasRequestedPermission = false
    private let loginManager = LoginManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox("Account Settings") {
                    VStack(spacing: 12) {
                        HStack {
                            Label("Account Status", systemImage: "person.crop.circle")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("Not Logged In")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        HStack {
                            Label("Launch at Login", systemImage: "power")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Toggle("", isOn: $launchAtLogin)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox("Subscription") {
                    HStack {
                        Label("Current Plan", systemImage: "star.circle")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("Free Tier")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.purple)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                Capsule()
                                    .fill(Color.purple.opacity(0.1))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox("Preferences") {
                    VStack(spacing: 12) {
                        HStack {
                            Label("Language", systemImage: "globe")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("English")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        HStack {
                            Label("Auto-save", systemImage: "timer")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            AutoSaveIntervalSection()
                                .frame(width: 90)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox("Activity Overview") {
                    ContributionGraph(contributions: viewModel.noteCountByDay)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(16)
        }
    }

    private func handleLaunchAtLoginChange(_ newValue: Bool) {
        if newValue {
            launchAtLogin = true
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

struct ModernGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading) {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .textCase(.uppercase)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)

            configuration.content
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
        .padding(.vertical, 8)
    }
}

struct IntegrationSettingsView: View {
    @Binding var integrateWithObsidian: Bool
    @Binding var customPath: String
    @Binding var showPathAlert: Bool
    @AppStorage("aiModel") private var aiModel = "Doubao-1.5-pro"
    let selectCustomDirectory: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Storage Location
                GroupBox("Storage Location") {
                    VStack(spacing: 12) {
                        HStack {
                            Label("Storage Location", systemImage: "folder")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Button("Change Location") {
                                selectCustomDirectory()
                            }
                            .font(.system(size: 13))
                            .controlSize(.small)
                        }

                        if FileManager.shared.isPathConfigured {
                            Text(customPath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.primary.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.purple.opacity(0.1), lineWidth: 1)
                                        )
                                )
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // AI Settings
                GroupBox("AI Settings") {
                    VStack(spacing: 12) {
                        HStack {
                            Label("Model", systemImage: "brain")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Picker("", selection: $aiModel) {
                                Text("Doubao").tag("Doubao")
                            }
                            .frame(width: 120)
                            .pickerStyle(.menu)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(16)
        }
    }
}

struct HotkeySettingsView: View {
    @ObservedObject var counter: HotkeyCounter

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox("Quick Actions") {
                    VStack(spacing: 12) {
                        HStack {
                            Label("Quick wake-up", systemImage: "bolt.square")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("⌥ + C")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        HStack {
                            Text(
                                "Today used: \(counter.todayCount)/\(AppConfig.QuickWakeup.dailyLimit)"
                            )
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            Spacer()
                            Button("Unlimited in Hyper +") {
                                // Handle upgrade action
                            }
                            .font(.system(size: 12, weight: .medium))
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox("Navigation") {
                    VStack(spacing: 12) {
                        HStack {
                            Label("History", systemImage: "clock")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("⌘ + H / ⌘ + F")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        HStack {
                            Label("New Note", systemImage: "plus")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("⌘ + ⏎ / ⌘ + N / ⌘ + K")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(16)
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
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            // Brand Icon and Name
            Image(colorScheme == .dark ? "brand-name-icon-dark" : "brand-name-icon")
                .resizable()
                .scaledToFit()
                .frame(height: 48)
                .padding(.top)

            // Update Section
            VStack(spacing: 8) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                                    let updateFile = try await updater.downloadUpdate(
                                        from: downloadURL)
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
        (20, "20s"),
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
