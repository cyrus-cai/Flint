import Combine
import SwiftUI

struct SettingsView: View {
    @State private var progressSubscription: AnyCancellable?
    @State private var autoCorrect = false
    @State private var launchAtLogin = false
    @State private var openInApp = false
    @StateObject private var counter = HotkeyCounter.shared
    @State private var isCheckingUpdate = false
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var latestVersion: String?
    let updater = AutoUpdater()
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    @State private var IntegrateWithObsidian = true

    var body: some View {
        List {
            Section("Account") {
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

                HStack {
                    Label("Data", systemImage: "externaldrive")
                    Spacer()
                    Text("All data is stored locally")
                        .foregroundColor(.gray)
                }
            }

            Section("Hotkey") {
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
                            // 处理升级操作
                        }.buttonStyle(.borderedProminent)
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

            Section("Default Integrate with") {
                HStack {
                    Image("obsidian-icon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                    Text("Obsidian")
                    Spacer()
                    Text("Applied")
                        .foregroundColor(.gray)
                    Toggle("", isOn: $IntegrateWithObsidian)
                        .toggleStyle(.switch)
                }

                // HStack {
                //     Image("no-integration-icon")
                //         .resizable()
                //         .aspectRatio(contentMode: .fit)
                //         .frame(width: 16, height: 16)
                //     Text("No Integration")
                //     Spacer()
                //     Text("Not Recommended")
                //         .foregroundColor(.gray)
                // }

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

            Section("General") {
                HStack {
                    Label("Language", systemImage: "globe")
                    Spacer()
                    Text("English")
                        .foregroundColor(.gray)
                }
            }

            HStack {
                Spacer()
                VStack {
                    if isDownloading {
                        ProgressView(
                            "Downloading...\(Int(downloadProgress * 100))%",
                            value: downloadProgress, total: 1.0
                        )
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                        .padding()
                    } else {
                        Button(isCheckingUpdate ? "Checking..." : "Check for updates") {
                            Task {
                                isCheckingUpdate = true
                                print("checking update")
                                do {
                                    let updateInfo = try await updater.checkForUpdates()

                                    await MainActor.run {
                                        let alert = NSAlert()
                                        if let updateInfo = updateInfo {
                                            guard
                                                let downloadURL = URL(
                                                    string: updateInfo.downloadURL)
                                            else {
                                                print(
                                                    "Invalid download URL: \(updateInfo.downloadURL)"
                                                )
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

                                                        // 开始下载并监听进度
                                                        progressSubscription = updater
                                                            .progressPublisher
                                                            .receive(on: RunLoop.main)
                                                            .sink { progress in
                                                                downloadProgress = progress
                                                            }

                                                        let updateFile =
                                                            try await updater.downloadUpdate(
                                                                from: downloadURL)
                                                        progressSubscription?.cancel()

                                                        //                                                        try await updater.installUpdate(from: updateFile)
                                                        try updater.installUpdate(from: updateFile)
                                                        isDownloading = false
                                                    } catch {
                                                        progressSubscription?.cancel()
                                                        isDownloading = false
                                                        let errorAlert = NSAlert()
                                                        errorAlert.messageText = "Update failed"
                                                        errorAlert.informativeText =
                                                            error.localizedDescription
                                                        errorAlert.alertStyle = .critical
                                                        errorAlert.addButton(withTitle: "OK")
                                                        errorAlert.runModal()
                                                    }
                                                }
                                            }
                                        } else {
                                            alert.messageText = "Check for updates"
                                            alert.informativeText = "You’re up to date!"
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
                        .disabled(isCheckingUpdate)
                    }

                    if let latest = latestVersion {
                        Text("Latest version: \(latest)")
                            .opacity(0.25)
                    }
                    Text("Current version: \(version ?? "") build\(buildNumber ?? "")")
                        .opacity(0.25)
                }
                Spacer()
            }
        }
        .listStyle(.sidebar)
        //        .frame(width: 560)
    }
}

#Preview {
    SettingsView()
}
