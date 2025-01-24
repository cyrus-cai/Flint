import Combine
import SwiftUI

extension Notification.Name {
    static let autoSaveIntervalDidChange = Notification.Name("autoSaveIntervalDidChange")
}

struct ContributionCell: View {
    let count: Int

    var color: Color {
        switch count {
        case 0: return Color(.systemGray)
        case 1...2: return Color.green.opacity(0.3)
        case 3...4: return Color.green.opacity(0.5)
        case 5...6: return Color.green.opacity(0.7)
        default: return Color.green
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
        case integration = "Integration"
        case hotkeys = "Hotkeys"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .integration: return "link"
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
        Form {
            VStack(alignment: .leading, spacing: 16) {

                Section("Account") {
                    HStack {
                        Label("Account", systemImage: "envelope")
                        Spacer()
                        Text("Not Logging in")
                            .foregroundColor(.gray)
                    }

                    HStack {
                        Label("Launch at login", systemImage: "power")
                        Spacer()
                        Toggle("", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { newValue in
                                if newValue {
                                    // First set the toggle to true
                                    launchAtLogin = true

                                    // Then request permission
                                    loginManager.requestLaunchPermission { granted in
                                        if granted {
                                            // If granted, enable launch at login
                                            loginManager.enableLaunchAtLogin()
                                        } else {
                                            // If not granted, set toggle back to false
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
                }

                Section("Plan") {
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

                Section("Settings") {
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

                Section("Activity") {
                    ContributionGraph(contributions: viewModel.noteCountByDay)
                        .padding(.vertical)
                }
            }
        }.formStyle(.grouped)
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
                HStack(spacing: 8) {
                    Button("Configure Obsidian folder") {
                        selectCustomDirectory()
                    }

                    // Add current path display
                    if FileManager.shared.isPathConfigured {
                        Text(customPath)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    // Button(role: .destructive) {
                    //     if let defaultURL = Foundation.FileManager.default.urls(
                    //         for: .documentDirectory, in: .userDomainMask
                    //     ).first {
                    //         FileManager.shared.setCustomDirectory(defaultURL)
                    //         customPath = defaultURL.path
                    //     }
                    // } label: {
                    //     Label("Reset", systemImage: "arrow.counterclockwise")
                    // }
                }
                .padding(.leading, 20)
            }

            //            HStack {
            //                Image("feishu-icon")
            //                    .resizable()
            //                    .aspectRatio(contentMode: .fit)
            //                    .frame(width: 16, height: 16)
            //                Text("Feishu(One-way synchronization)")
            //                Spacer()
            //                HStack(spacing: 8) {
            //                    if UserDefaults.standard.string(forKey: "FeishuAccessToken") != nil,
            //                        let expirationDate = UserDefaults.standard.object(
            //                            forKey: "FeishuTokenExpiration") as? Date,
            //                        expirationDate > Date()
            //                    {
            //                        // Green dot indicator
            //                        Circle()
            //                            .fill(Color.green)
            //                            .frame(width: 6, height: 6)
            //
            //                        Text("Authorized")
            //                            .foregroundColor(.secondary)
            //                    }
            //
            //                    Button("Re-authorize Feishu") {
            //                        if let authURL = FeishuAuthManager.generateAuthorizationURL() {
            //                            NSWorkspace.shared.open(authURL)
            //                        }
            //                    }
            //                    .buttonStyle(.borderedProminent)
            //                }
            //            }

            //            HStack {
            //                Image("notion-icon")
            //                    .resizable()
            //                    .aspectRatio(contentMode: .fit)
            //                    .frame(width: 16, height: 16)
            //                Text("Notion")
            //                Spacer()
            //                Text("Coming soon")
            //                    .foregroundColor(.gray)
            //            }
            //            .opacity(0.5)
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
                    Text("Today used:\(counter.todayCount)/\(AppConfig.QuickWakeup.dailyLimit)")
                        .opacity(0.5)
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
