import SwiftUI

struct SettingsView: View {
    @State private var autoCorrect = false
    @State private var launchAtLogin = false
    @State private var openInApp = false
    @StateObject private var counter = HotkeyCounter.shared
    @State private var isCheckingUpdate = false
    @State private var latestVersion: String?
    let updater = AutoUpdater()
    
//    func openFileDictionary() {
//        let notesURL = FileManager.shared.notesDirectory
//        NSWorkspace.shared.open(notesURL)
//    }
    
    var body: some View {
        List {
            Section("账户") {
                HStack {
                    Label("电子邮件", systemImage: "envelope")
                    //                        .foregroundColor(.purple)
                    Spacer()
                    Text("未登录")
                        .foregroundColor(.gray)
                }
                
                HStack {
                    Label("订阅", systemImage: "plus.square")
                    //                        .foregroundColor(.purple)
                    Spacer()
                    Text("Free 套餐")
                        .foregroundColor(.gray)
                    //                    Button("升级至 Hyper +") {
                    //                        // 处理升级操作
                    //                    }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .controlSize(.small)
                }
                
                HStack {
                    Label("数据管理", systemImage: "externaldrive")
                    //                        .foregroundColor(.purple)
                    Spacer()
                    Text("所有数据存储于本地")
                        .foregroundColor(.gray)
                    //                    Button("查看") {
                    //                        Task {
                    //                            openFileDictionary()
                    //                        }
                    //                    }
                }
            }
            
            Section("启动") {
                VStack{
                    HStack {
                        Label("快捷唤醒", systemImage: "bolt.square")
                        Spacer()
                        Text("Option + C")
                    }
                    HStack {
                        Spacer()
                        Text("今日已使用:\(counter.todayCount)/50次").opacity(0.5)
                        //                        .foregroundColor(.purple)
                        Button("Unlimited in Hyper +") {
                            // 处理升级操作
                        } .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.small)
                    }
                }
                //                HStack {
                //                    Label("登录时启动", systemImage: "arrow.right.circle")
                ////                        .foregroundColor(.purple)
                //                    Spacer()
                //                    Toggle("", isOn: $launchAtLogin)
                //                        .toggleStyle(.switch)
                //                }
            }
            
            Section("通用") {
                HStack {
                    Label("应用语言", systemImage: "globe")
                    //                        .foregroundColor(.purple)
                    Spacer()
                    Text("中文")
                        .foregroundColor(.gray)
                }
            }
            
            HStack {
                Spacer()
                VStack {
                    Button(isCheckingUpdate ? "检查中..." : "检查更新") {
                        Task {
                            isCheckingUpdate = true
                            print("checking update")
//                            do {
//                                let updateInfo = try await updater.checkForUpdates()
//                                
//                                // 确保在主线程显示弹窗
//                                await MainActor.run {
//                                    let alert = NSAlert()
//                                    if let updateInfo = updateInfo {
//                                        alert.messageText = "发现新版本"
//                                        alert.informativeText = """
//                                            新版本 \(updateInfo.version) 已发布
//                                            是否现在更新？
//                                            """
//                                        alert.alertStyle = .informational
//                                        alert.addButton(withTitle: "更新")
//                                        alert.addButton(withTitle: "稍后")
//                                        
//                                        if alert.runModal() == .alertFirstButtonReturn {
//                                            // 用户选择更新
//                                            // Uncomment and add download URL when ready
//                                             let updateFile = try await updater.downloadUpdate(from: updateInfo.downloadURL)
//                                             try updater.installUpdate(from: updateFile)
//                                        }
//                                    } else {
//                                        alert.messageText = "检查更新"
//                                        alert.informativeText = "当前已是最新版本"
//                                        alert.alertStyle = .informational
//                                        alert.addButton(withTitle: "确定")
//                                        alert.runModal()
//                                    }
//                                }
//                            } catch {
//                                // 错误处理也移到主线程
//                                await MainActor.run {
//                                    let alert = NSAlert(error: error)
//                                    alert.runModal()
//                                }
//                            }
                            do {
                                let updateInfo = try await updater.checkForUpdates()
                                
                                // Move to the main thread for UI operations
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
                                            是否现在更新？
                                            """
                                        alert.alertStyle = .informational
                                        alert.addButton(withTitle: "更新")
                                        alert.addButton(withTitle: "稍后")
                                        
                                        // Handle the modal response synchronously
                                        let response = alert.runModal()
                                        
                                        // Start a new async task for the update process
                                        if response == .alertFirstButtonReturn {
                                            Task {
                                                do {
                                                    let updateFile = try await updater.downloadUpdate(from: downloadURL)
                                                    try await updater.installUpdate(from: updateFile)
                                                } catch {
                                                    // Handle any errors during update
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
                                // Handle errors from checkForUpdates
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
                    
                    if let latest = latestVersion {
                        Text("最新版本: \(latest)")
                            .opacity(0.25)
                    }
                    Text("当前版本: 0.1.1 (2024112401a)")
                        .opacity(0.25)
                }
                Spacer()
            }
        }
        .listStyle(.sidebar)
        .frame(width: 500)
    }
}

#Preview {
    SettingsView()
}
