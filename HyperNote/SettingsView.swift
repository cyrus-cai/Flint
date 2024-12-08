import SwiftUI
import Combine

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
    
    var body: some View {
        List {
            Section("账户") {
                HStack {
                    Label("电子邮件", systemImage: "envelope")
                    Spacer()
                    Text("未登录")
                        .foregroundColor(.gray)
                }
                
                HStack {
                    Label("订阅", systemImage: "plus.square")
                    Spacer()
                    Text("Free 套餐")
                        .foregroundColor(.gray)
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .controlSize(.small)
                }
                
                HStack {
                    Label("数据管理", systemImage: "externaldrive")
                    Spacer()
                    Text("所有数据存储于本地")
                        .foregroundColor(.gray)
                }
            }
            
            Section("快捷键") {
                VStack{
                    HStack {
                        Label("快捷唤醒", systemImage: "bolt.square")
                        Spacer()
                        Text("⌥ + C")
                            .foregroundColor(.gray)
                    }
                    HStack {
                        Spacer()
                        Text("今日已使用:\(counter.todayCount)/50次").opacity(0.5)
                        Button("Unlimited in Hyper +") {
                            // 处理升级操作
                        } .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.small)
                    }
                   
                }
                HStack {
                    Label("历史记录", systemImage: "clock")
                    Spacer()
                    Text("⌘ + H / ⌘ + F")
                        .foregroundColor(.gray)
                }
                HStack {
                    Label("新建笔记", systemImage: "plus")
                    Spacer()
                    Text("⌘ + N / ⌘ + K")
                        .foregroundColor(.gray)
                }
            }
            
            Section("通用") {
                HStack {
                    Label("应用语言", systemImage: "globe")
                    Spacer()
                    Text("中文")
                        .foregroundColor(.gray)
                }
            }
            
            HStack {
                Spacer()
                VStack {
                    if isDownloading {
                        ProgressView("下载中...\(Int(downloadProgress * 100))%", value: downloadProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                            .padding()
                    } else {
                        Button(isCheckingUpdate ? "检查中..." : "检查更新") {
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
                                                errorAlert.messageText = "更新失败"
                                                errorAlert.informativeText = "下载链接无效"
                                                errorAlert.alertStyle = .critical
                                                errorAlert.addButton(withTitle: "确定")
                                                errorAlert.runModal()
                                                return
                                            }
                                            alert.messageText = "发现新版本"
                                            alert.informativeText = """
                                                新版本 \(updateInfo.version) 已发布
                                                 \(updateInfo.description)
                                                是否现在更新？
                                                """
                                            alert.alertStyle = .informational
                                            alert.addButton(withTitle: "更新")
                                            alert.addButton(withTitle: "稍后")
                                            
                                            let response = alert.runModal()
                                            
                                            if response == .alertFirstButtonReturn {
                                                Task {
                                                    do {
                                                        isDownloading = true
                                                        downloadProgress = 0
                                                        
                                                        // 开始下载并监听进度
                                                        progressSubscription = updater.progressPublisher
                                                            .receive(on: RunLoop.main)
                                                            .sink { progress in
                                                                downloadProgress = progress
                                                            }
                                                            
                                                        let updateFile = try await updater.downloadUpdate(from: downloadURL)
                                                        progressSubscription?.cancel()
                                                        
//                                                        try await updater.installUpdate(from: updateFile)
                                                        try updater.installUpdate(from: updateFile)
                                                        isDownloading = false
                                                    } catch {
                                                        progressSubscription?.cancel()
                                                        isDownloading = false
                                                        let errorAlert = NSAlert()
                                                        errorAlert.messageText = "更新失败"
                                                        errorAlert.informativeText = error.localizedDescription
                                                        errorAlert.alertStyle = .critical
                                                        errorAlert.addButton(withTitle: "确定")
                                                        errorAlert.runModal()
                                                    }
                                                }
                                            }
                                        } else {
                                            alert.messageText = "检查更新"
                                            alert.informativeText = "当前已是最新版本"
                                            alert.alertStyle = .informational
                                            alert.addButton(withTitle: "确定")
                                            alert.runModal()
                                        }
                                    }
                                } catch {
                                    await MainActor.run {
                                        let alert = NSAlert()
                                        alert.messageText = "检查更新失败"
                                        alert.informativeText = error.localizedDescription
                                        alert.alertStyle = .critical
                                        alert.addButton(withTitle: "确定")
                                        alert.runModal()
                                    }
                                }
                                isCheckingUpdate = false
                            }
                        }
                        .disabled(isCheckingUpdate)
                    }
                    
                    if let latest = latestVersion {
                        Text("最新版本: \(latest)")
                            .opacity(0.25)
                    }
                    Text("当前版本: \(version ?? "") build\(buildNumber ?? "")")
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
