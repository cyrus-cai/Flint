import Combine
import KeyboardShortcuts
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
        case appearance = "Appearance"
        case hotkeys = "Hotkeys"
        case about = "About"

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
    @State private var newVersionAvailable: Bool = false

    @AppStorage("AIModel") private var AIModel: String =
        AIModelConfig.availableModels.first { !$0.isProOnly }?.modelId ?? "Doubao-lite-32k"

    // Feishu related settings
    //    @AppStorage("FeishuSyncEnabled") private var feishuSyncEnabled = false
    //    @State private var feishuAccessToken = ""
    //    @State private var showFeishuTokenAlert = false

    let updater = AutoUpdater()
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

    @AppStorage("isPro") private var isPro: Bool = false
    // This computed property filters available models depending on the user's Pro status.
    private var allowedModels: [AIModel] {
        AIModelConfig.availableModels.filter { model in
            isPro || (!model.isProOnly)
        }
    }

    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

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

    private func updateAppearance(_ mode: AppearanceMode) {
        if let window = NSApp.windows.first {
            switch mode {
            case .system:
                window.appearance = nil
            case .light:
                window.appearance = NSAppearance(named: .aqua)
            case .dark:
                window.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            // 左侧边栏：列表展示所有标签，底部显示更新提示（若有更新）
            VStack(spacing: 0) {
                List(SettingsTab.allCases, id: \.self, selection: $selectedTab) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .padding(.vertical, 4)
                }
                .listStyle(SidebarListStyle())

                // 底部更新提示
                if newVersionAvailable {
                    Divider()
                    Text("New Version Avaliable")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        } detail: {
            // 右侧内容区域，根据选项显示不同界面
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsView(isPro: $isPro)
                    case .integration:
                        IntegrationSettingsView(
                            integrateWithObsidian: $integrateWithObsidian,
                            customPath: $customPath,
                            showPathAlert: $showPathAlert,
                            selectCustomDirectory: selectCustomDirectory
                        )
                    case .appearance:
                        AppearanceSettingsView()
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
                    case .none:
                        EmptyView()
                    }
                }
                .padding()
            }
        }
        .frame(width: 800, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .navigationSplitViewStyle(.automatic)
        .toolbar(.automatic)
        .onAppear {
            // 每次打开设置时自动检查更新
            Task {
                do {
                    let updateInfo = try await updater.checkForUpdates()
                    // 如果返回 updateInfo 不为空，说明有新版本
                    newVersionAvailable = (updateInfo != nil)
                } catch {
                    print("Failed to check for updates: \(error)")
                    newVersionAvailable = false
                }
            }

            // 可保留其它 onAppear 逻辑，例如刷新用户状态等
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserDidLogin"))) {
            _ in
            isPro = UserDefaults.standard.bool(forKey: "isPro")
        }
    }
}
// MARK: - Subviews

struct GeneralSettingsView: View {
    @StateObject private var viewModel = GeneralSettingsViewModel()
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userEmail") private var userEmail: String = ""
    @AppStorage("userAvatar") private var userAvatar: String = ""
    @AppStorage("hasRequestedLaunchPermission") private var hasRequestedPermission = false
    private let loginManager = LoginManager.shared
    @Binding var isPro: Bool
    @State private var isCheckingStatus = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox("Account") {
                    VStack(spacing: 12) {
                        HStack {
                            if !userEmail.isEmpty {
                                AsyncImage(url: URL(string: userAvatar)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 24, height: 24)
                                        .clipShape(Circle())
                                } placeholder: {
                                    Image(systemName: "person.crop.circle")
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }

                                VStack(alignment: .leading) {
                                    if !userName.isEmpty {
                                        Text(userName)
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    Text(userEmail)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button(action: {
                                    let defaults = UserDefaults.standard
                                    defaults.removeObject(forKey: "userName")
                                    defaults.removeObject(forKey: "userEmail")
                                    defaults.removeObject(forKey: "userAvatar")
                                    defaults.removeObject(forKey: "isPro")
                                    defaults.synchronize()

                                    userName = ""
                                    userEmail = ""
                                    userAvatar = ""

                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("UserDidLogout"),
                                        object: nil
                                    )
                                }) {
                                    Text("Sign Out")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            } else {
                                HStack {
                                    Button(action: {
                                        if let url = URL(
                                            string:
                                                "https://www.writedown.space/login")
                                        {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }) {
                                        Label("Account", systemImage: "person.crop.circle")
                                            .font(.system(size: 13, weight: .medium))
                                        // .foregroundColor(.blue)

                                        Spacer()

                                        Text("Log in")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 4)
                                            .background(
                                                LinearGradient(
                                                    colors: [
                                                        Color(.systemBlue), Color(.systemIndigo),
                                                    ],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                    Spacer()
                                }
                            }
                        }

                        Divider()

                        HStack {
                            Label("Plan", systemImage: "star.circle")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(isPro ? "Pro" : "")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(isPro ? .white : .secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    isPro
                                        ? LinearGradient(
                                            colors: [Color(.systemPurple), Color(.systemPink)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ).cornerRadius(6) : nil
                                )

                            if !isPro {
                                Button(action: {
                                    Task {
                                        do {
                                            let request = StripeCheckout.CheckoutRequest(
                                                planId: "pro",
                                                email: UserDefaults.standard.string(
                                                    forKey: "userEmail")
                                            )

                                            let origin = Bundle.main.bundleIdentifier ?? "writedown"

                                            let response =
                                                await StripeCheckout.createCheckoutSession(
                                                    request: request,
                                                    origin:
                                                        "https://www.writedown.space/stripePayment"
                                                )

                                            if let urlString = response.url,
                                                let url = URL(string: urlString)
                                            {
                                                NSWorkspace.shared.open(url)
                                            } else if let error = response.error {
                                                print("Payment Error: \(error.message)")
                                            }
                                        }
                                    }
                                }) {
                                    Text("Upgrade to Pro")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 4)
                                        .background(
                                            LinearGradient(
                                                colors: [Color(.systemPurple), Color(.systemPink)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .frame(alignment: .trailing)
                                // Add refresh button
                                if !userEmail.isEmpty {
                                    Button(action: {
                                        checkProStatus()
                                    }) {
                                        if isCheckingStatus {
                                            ProgressView()
                                                .scaleEffect(0.4)
                                                .frame(width: 14, height: 14)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                                .imageScale(.small)
                                        }
                                    }
                                    .disabled(isCheckingStatus)
                                    .help("Check subscription status")
                                }
                            }
                        }

                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox("Preferences") {
                    VStack(spacing: 12) {
                        HStack {
                            Label("Start at login", systemImage: "power")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Toggle("", isOn: $launchAtLogin)
                                .onChange(of: launchAtLogin) { newValue in
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
                                .toggleStyle(.switch)
                        }

                        Divider()

                        HStack {
                            Label("Language", systemImage: "globe")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("English")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // GroupBox("Activity Overview") {
                //     ContributionGraph(contributions: viewModel.noteCountByDay)
                //         .padding(.vertical, 12)
                //         .padding(.horizontal, 8)
                // }
                // .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            // 主动刷新用户状态
            userName = UserDefaults.standard.string(forKey: "userName") ?? ""
            userEmail = UserDefaults.standard.string(forKey: "userEmail") ?? ""
            userAvatar = UserDefaults.standard.string(forKey: "userAvatar") ?? ""
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserDidLogin"))) {
            _ in
            print("🔄 Settings view received login notification")
            // 强制刷新用户状态
            userName = UserDefaults.standard.string(forKey: "userName") ?? ""
            userEmail = UserDefaults.standard.string(forKey: "userEmail") ?? ""
            userAvatar = UserDefaults.standard.string(forKey: "userAvatar") ?? ""
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

    private func checkProStatus() {
        guard let email = UserDefaults.standard.string(forKey: "userEmail") else {
            return
        }

        isCheckingStatus = true

        Task {
            do {
                let isPro = try await ProStatusChecker.shared.checkProStatus(email: email)
                await MainActor.run {
                    UserDefaults.standard.set(isPro, forKey: "isPro")
                    self.isPro = isPro
                    isCheckingStatus = false
                }
            } catch {
                print("Failed to check pro status: \(error)")
                await MainActor.run {
                    isCheckingStatus = false
                }
            }
        }
    }
}

struct ModernGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading) {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
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
    @AppStorage("AIModel") private var AIModel: String =
        AIModelConfig.availableModels.first { !$0.isProOnly }?.modelId ?? "Doubao-lite-32k"
    let selectCustomDirectory: () -> Void

    private func openInFinder() {
        guard let notesDirectory = FileManager.shared.notesDirectory else {
            print("Could not access notes directory")
            return
        }

        NSWorkspace.shared.selectFile(
            nil,
            inFileViewerRootedAtPath: notesDirectory.path
        )
    }

    @AppStorage("isPro") private var isPro: Bool = false
    // This computed property filters available models depending on the user's Pro status.
    private var allowedModels: [AIModel] {
        AIModelConfig.availableModels.filter { model in
            isPro || (!model.isProOnly)
        }
    }

    @AppStorage("notionIntegration") private var notionIntegration = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Storage Location
                GroupBox("Save") {
                    VStack(spacing: 12) {
                        HStack(spacing: 0) {
                            Label("Storage Location", systemImage: "folder")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()

                            HStack(spacing: 0) {

                                Text(customPath)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 8)

                                Button("Change") {
                                    selectCustomDirectory()
                                }
                                .font(.system(size: 13))
                                .controlSize(.small)
                            }
                            // .padding(.trailing, 4)
                        }

                        Divider()

                        HStack {
                            Label("Auto-save", systemImage: "timer")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            AutoSaveIntervalSection()
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
                            Picker("", selection: $AIModel) {
                                ForEach(allowedModels) { model in
                                    Text(model.displayName)
                                        .tag(model.modelId)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
                .onAppear {
                    // 每次显示 AI Settings 时，验证当前选择的模型是否在允许的范围内
                    if let currentModel = UserDefaults.standard.string(forKey: "AIModel") {
                        if !allowedModels.contains(where: { $0.modelId == currentModel }) {
                            // 如果当前值不在允许的模型中，则自动重置为允许列表中的第一个
                            AIModel = allowedModels.first?.modelId ?? "ep-20250208231403-7dmtb"
                        }
                    } else {
                        // 如果数据库中没有存储模型，则直接设置为允许列表中的第一个
                        AIModel = allowedModels.first?.modelId ?? "ep-20250208231403-7dmtb"
                    }
                    print("刷新模型选择器视图: 当前 AIModel 为 \(AIModel)")
                }

                // External Settings
                GroupBox("External Connections") {
                    VStack(spacing: 12) {
                        HStack {
                            Label("Notion", systemImage: "square.and.pencil")
                                .font(.system(size: 13, weight: .medium))
                            Text("beta")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.6))
                                .cornerRadius(4)
                            Spacer()
                            Toggle("", isOn: $notionIntegration)
                                .toggleStyle(.switch)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(.horizontal, 16)
        }
    }
}

struct HotkeySettingsView: View {
    @ObservedObject var counter: HotkeyCounter
    @AppStorage("isPro") private var isPro: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Wake Up Group
                GroupBox("Wake Up") {
                    VStack(spacing: 12) {
                        HStack {
                            Label("Quick wake-up", systemImage: "bolt.square")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            KeyboardShortcuts.Recorder("", name: .quickWakeup)
                        }

                        Divider()

                        HStack {
                            Label("Quick save", systemImage: "square.and.arrow.down")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("⌘ + C (double click)")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        if isPro {
                            Text("Unlimited quick wake-ups (Pro)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        } else {
                            HStack {
                                Text(
                                    "Today used: \(counter.todayCount)/\(AppConfig.QuickWakeup.dailyLimit)"
                                )
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                Button(action: {
                                    Task {
                                        do {
                                            let request = StripeCheckout.CheckoutRequest(
                                                planId: "pro",
                                                email: UserDefaults.standard.string(
                                                    forKey: "userEmail")
                                            )

                                            let response =
                                                await StripeCheckout.createCheckoutSession(
                                                    request: request,
                                                    origin:
                                                        "https://www.writedown.space/stripePayment"
                                                )

                                            if let urlString = response.url,
                                                let url = URL(string: urlString)
                                            {
                                                NSWorkspace.shared.open(url)
                                            }
                                        }
                                    }
                                }) {
                                    Text("Upgrade to Pro")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .background(
                                            LinearGradient(
                                                colors: [Color(.systemPurple), Color(.systemPink)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .cornerRadius(8)
                                        .shadow(color: Color(.systemPurple).opacity(0.3), radius: 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Note Operations Group
                GroupBox("Note Operations") {
                    VStack(spacing: 12) {
                        HStack {
                            Label("New Note", systemImage: "plus")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("⌘ + ⏎ / ⌘ + N / ⌘ + K")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        HStack {
                            Label("Copy All", systemImage: "doc.on.doc")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("⌘ + ⇧ + C")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Navigation Group
                GroupBox("Navigation") {
                    VStack(spacing: 12) {
                        HStack {
                            Label("History", systemImage: "clock")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("⌘ + ⇧ + F")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        HStack {
                            Label("Previous Note", systemImage: "chevron.left")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("⌘ + [")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Divider()

                        HStack {
                            Label("Next Note", systemImage: "chevron.right")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("⌘ + ]")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(.horizontal, 16)
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

                    // Add Release Notes button
                    Button("Release Notes") {
                        if let url = URL(
                            string:
                                "https://xiikii.notion.site/Release-Note-18e84c8dbdaa807ba02ee18cd3895149?pvs=4"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .padding(.top, 4)

                    // Add Send Feedback button
                    Button("Send Feedback") {
                        if let service = NSSharingService(named: .composeEmail) {
                            service.recipients = ["team_productlab@outlook.com"]
                            service.subject = "Writedown Feedback"

                            // Get app version
                            let appVersion =
                                Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                                ?? "Unknown"

                            // Get macOS version
                            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

                            // Compose email body with both versions
                            let body = """
                                App Version: \(appVersion)
                                macOS Version: \(osVersion)

                                Feedback:

                                """

                            service.perform(withItems: [body])
                        }
                    }
                    .padding(.top, 4)
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
    @AppStorage("autoSaveInterval") private var autoSaveInterval: TimeInterval = 15

    private let intervals = [
        (10, "10s"),
        (15, "15s"),
        (30, "30s"),
        (60, "1min"),
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

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

struct AppearanceSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox("Theme") {
                    VStack(alignment: .leading, spacing: 12) {  // Changed alignment to .leading
                        Label("Appearance", systemImage: "paintbrush")
                            .font(.system(size: 13, weight: .medium))

                        HStack(spacing: 24) { // Increased spacing from 16 to 24
                            // System appearance option
                            AppearanceOptionView(
                                image: "system-example",
                                title: "System",
                                isSelected: appearanceMode == .system
                            ) {
                                appearanceMode = .system
                            }

                            // Light appearance option
                            AppearanceOptionView(
                                image: "light-example",
                                title: "Light",
                                isSelected: appearanceMode == .light
                            ) {
                                appearanceMode = .light
                            }

                            // Dark appearance option
                            AppearanceOptionView(
                                image: "dark-example",
                                title: "Dark",
                                isSelected: appearanceMode == .dark
                            ) {
                                appearanceMode = .dark
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity)  // Added to ensure HStack takes full width
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(.horizontal, 16)
        }
        .onChange(of: appearanceMode) { newValue in
            // 更新所有窗口的外观
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
                    .frame(height: 100)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
                    )

                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    SettingsView()
}

// func createSettingsWindow() {
//     let settingsWindow = NSWindow(
//         contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
//         styleMask: [.titled, .closable, .fullSizeContentView],  // Add fullSizeContentView
//         backing: .buffered,
//         defer: false
//     )

//     settingsWindow.titlebarAppearsTransparent = true
//     settingsWindow.titleVisibility = .hidden
//     settingsWindow.center()

//     let contentView = SettingsView()
//     let hostingView = NSHostingView(rootView: contentView)
//     settingsWindow.contentView = hostingView

//     settingsWindow.makeKeyAndOrderFront(nil)
// }
