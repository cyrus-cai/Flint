import SwiftUI

struct SettingsView: View {
    @State private var autoCorrect = false
    @State private var launchAtLogin = false
    @State private var openInApp = false
    @StateObject private var counter = HotkeyCounter.shared
    
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
                    Button("检查更新...") {
                        print("检查更新按钮被点击")
                    }
                    Text("当前版本:0.1.1 (2024112401a)")
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
