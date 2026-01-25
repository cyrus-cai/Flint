# SwiftTerm 完整替代方案

> **项目**: HyperNote - 使用 SwiftTerm 替代现有简易终端实现
> **日期**: 2026-01-25
> **参考**: [SwiftTerm GitHub](https://github.com/migueldeicaza/SwiftTerm)

---

## 目录

1. [现状分析](#现状分析)
2. [SwiftTerm 技术概览](#swiftterm-技术概览)
3. [架构设计方案](#架构设计方案)
4. [详细实现步骤](#详细实现步骤)
5. [代码示例](#代码示例)
6. [迁移注意事项](#迁移注意事项)
7. [优势对比](#优势对比)
8. [风险评估](#风险评估)

---

## 现状分析

### 当前终端实现架构

HyperNote 目前使用**自定义的轻量级终端输出系统**：

#### 核心组件

1. **ClaudeCodeService.swift** - 服务层
   - 管理 `claude` CLI 进程生命周期
   - 解析 `--output-format stream-json` 输出
   - 维护输出行缓冲区（最多 1000 行）
   - 通过 `Pipe` 读取 stdout/stderr

2. **ClaudeCodeOutputView.swift** - 独立窗口视图
   - 使用 `ScrollView` + `VStack` 显示输出
   - 手动实现颜色编码（8 种 StreamType）
   - 手动文本选择和复制功能

3. **EmbeddedClaudeCodePanel** - 嵌入式面板
   - 更紧凑的界面
   - 与独立窗口共享相同数据源

#### 当前实现的限制

| 限制 | 影响 |
|-----|------|
| ✗ 无真正的终端仿真 | 不支持 ANSI 转义序列、光标控制 |
| ✗ 无 VT100/Xterm 兼容性 | 无法正确显示复杂终端应用 |
| ✗ 手动文本渲染 | 性能较差，无法处理大量输出 |
| ✗ 缺少交互能力 | 无法发送键盘输入到进程 |
| ✗ 无滚动缓冲区管理 | 只能显示最近 1000 行 |
| ✗ 无图形协议支持 | 无法显示 Sixel、iTerm2 内联图片 |

---

## SwiftTerm 技术概览

### 核心特性

SwiftTerm 是由 Miguel de Icaza（Xamarin 创始人）开发的专业级终端仿真库：

- **完整的 VT100/Xterm 仿真** - 支持所有标准转义序列
- **Unicode & Emoji 支持** - 完整的 Unicode 渲染和组合字符
- **颜色支持** - ANSI、256 色、TrueColor 模式
- **文本属性** - 粗体、斜体、下划线、删除线
- **图形协议** - Sixel、iTerm2、Kitty 图片显示
- **鼠标事件** - 完整的鼠标交互支持
- **线程安全** - 支持并发操作
- **生产级** - 被 Secure Shellfish、La Terminal、CodeEdit 采用

### 平台支持

- ✅ macOS (AppKit/NSView)
- ✅ iOS/iPadOS (UIKit/UIView)
- ✅ visionOS
- ✅ 无头模式（服务器端）

### 架构组成

```
┌─────────────────────────────────────┐
│      TerminalView (NSView)          │
│  ┌───────────────────────────────┐  │
│  │   Terminal (核心引擎)         │  │
│  │  - VT100/Xterm 仿真           │  │
│  │  - 屏幕缓冲区管理             │  │
│  │  - ANSI 转义序列解析          │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
           ↕ (Delegate)
┌─────────────────────────────────────┐
│   TerminalViewDelegate              │
│   - send(data:) 发送数据            │
│   - sizeChanged() 尺寸变化          │
│   - scrolled() 滚动事件             │
└─────────────────────────────────────┘
           ↕
┌─────────────────────────────────────┐
│   LocalProcess (可选)               │
│   - Unix 伪终端 (pty)               │
│   - 进程生命周期管理                │
└─────────────────────────────────────┘
```

---

## 架构设计方案

### 方案选择

有两种集成方式：

#### 方案 A：完全替代（推荐）

**描述**: 使用 `TerminalView` 直接作为输出显示，实现 `TerminalViewDelegate` 协议连接到 `claude` CLI 进程。

**优点**:
- ✅ 获得完整的终端仿真能力
- ✅ 自动处理 ANSI 转义序列
- ✅ 支持交互式输入
- ✅ 性能优异（原生渲染）
- ✅ 代码量减少（移除手动解析逻辑）

**缺点**:
- ⚠️ 需要较大重构
- ⚠️ 失去对每行输出的精细控制（StreamType 分类）
- ⚠️ 学习曲线

#### 方案 B：混合模式

**描述**: 保留现有的 JSON 解析，但使用 `TerminalView` 作为纯显示组件，通过 `feed(text:)` 方法发送格式化文本。

**优点**:
- ✅ 渐进式迁移
- ✅ 保留现有业务逻辑
- ✅ 可以继续使用 StreamType 分类

**缺点**:
- ⚠️ 无法充分利用 SwiftTerm 的仿真能力
- ⚠️ 仍需手动处理颜色编码

---

### 推荐方案：方案 A（完全替代）

基于以下考虑：

1. **Claude Code 已支持终端模式**: `--output-format stream-json` 之外，还可以直接输出到终端
2. **未来扩展性**: 可能支持其他 CLI 工具，真正的终端更通用
3. **用户体验**: 完整的终端仿真提供更好的交互体验
4. **代码简化**: 移除大量手动解析和渲染代码

---

## 详细实现步骤

### 阶段 1: 环境准备（1-2 小时）

#### 1.1 添加 SwiftTerm 依赖

**操作**: 在 Xcode 中添加 Swift Package

```
File -> Add Package Dependencies...
URL: https://github.com/migueldeicaza/SwiftTerm
Version: 最新稳定版
```

或编辑 `Package.resolved`:

```json
{
  "identity" : "swiftterm",
  "kind" : "remoteSourceControl",
  "location" : "https://github.com/migueldeicaza/SwiftTerm",
  "state" : {
    "branch" : "main",
    "revision" : "最新commit"
  }
}
```

#### 1.2 沙盒权限配置

**重要**: SwiftTerm 使用伪终端 (pty)，需要禁用沙盒或添加特定权限。

**Writedown.entitlements** 修改：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- 现有权限 -->

    <!-- 添加终端权限 -->
    <key>com.apple.security.app-sandbox</key>
    <false/>  <!-- 完全禁用沙盒 -->

    <!-- 或者保留沙盒并添加特定权限 -->
    <key>com.apple.security.device.serial</key>
    <true/>
    <key>com.apple.security.device.usb</key>
    <true/>
</dict>
</plist>
```

**注意**: 禁用沙盒会影响 App Store 分发，考虑使用临时权限异常。

---

### 阶段 2: 创建终端服务层（3-4 小时）

#### 2.1 创建 `SwiftTermService.swift`

**位置**: `/Users/xiikii/Coding/HyperNote/Writedown/Services/SwiftTermService.swift`

```swift
import Foundation
import SwiftTerm

@MainActor
class SwiftTermService: ObservableObject {
    static let shared = SwiftTermService()

    // MARK: - Published Properties

    @Published private(set) var isRunning = false
    @Published private(set) var sessionInfo: SessionInfo?

    // MARK: - Private Properties

    private var currentProcess: Process?
    private var terminalDelegate: ClaudeTerminalDelegate?

    // MARK: - Types

    struct SessionInfo {
        let sessionId: String
        let model: String
        let cwd: String
    }

    private init() {}

    // MARK: - Public Methods

    /// 执行 Claude Code 并返回 TerminalView
    func createTerminalView(
        noteContent: String?,
        noteTitle: String?,
        workingDirectory: URL
    ) -> ClaudeTerminalView {
        let terminalView = ClaudeTerminalView()

        // 配置终端外观
        terminalView.nativeBackgroundColor = NSColor(hex: "#1E1E1E") ?? .black
        terminalView.nativeForegroundColor = .white
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // 创建并设置 delegate
        let delegate = ClaudeTerminalDelegate(terminalView: terminalView)
        terminalView.terminalDelegate = delegate
        self.terminalDelegate = delegate

        // 启动进程
        Task {
            await startClaudeProcess(
                terminalView: terminalView,
                noteContent: noteContent,
                noteTitle: noteTitle,
                workingDirectory: workingDirectory
            )
        }

        return terminalView
    }

    /// 取消当前执行
    func cancel() {
        guard let process = currentProcess, process.isRunning else { return }
        process.terminate()
        currentProcess = nil
        isRunning = false
    }

    // MARK: - Private Methods

    private func startClaudeProcess(
        terminalView: ClaudeTerminalView,
        noteContent: String?,
        noteTitle: String?,
        workingDirectory: URL
    ) async {
        guard let cliPath = resolveClaudeCodePath() else {
            await feedErrorMessage(to: terminalView, message: "Claude Code CLI not found")
            return
        }

        guard let content = noteContent, !content.isEmpty else {
            await feedErrorMessage(to: terminalView, message: "No note content provided")
            return
        }

        isRunning = true

        // 创建进程
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.currentDirectoryURL = workingDirectory

        // 配置环境
        var env = ProcessInfo.processInfo.environment
        if let title = noteTitle {
            env["HYPERNOTE_TITLE"] = title
        }
        process.environment = env

        // 使用原生终端输出（不使用 stream-json）
        process.arguments = [
            "-p", content,
            "--verbose"
        ]

        // 配置伪终端（pty）
        let masterFd = terminalView.getTerminal().pty.master
        let slaveFd = terminalView.getTerminal().pty.slave

        process.standardInput = FileHandle(fileDescriptor: slaveFd)
        process.standardOutput = FileHandle(fileDescriptor: slaveFd)
        process.standardError = FileHandle(fileDescriptor: slaveFd)

        currentProcess = process

        do {
            try process.run()

            // 异步读取输出
            Task.detached(priority: .userInitiated) { [weak self] in
                let fileHandle = FileHandle(fileDescriptor: masterFd)
                for try await data in fileHandle.bytes {
                    await terminalView.feed(byteArray: ArraySlice([data]))
                }

                await self?.handleProcessCompletion(process)
            }

        } catch {
            await feedErrorMessage(to: terminalView, message: "Failed to launch: \(error.localizedDescription)")
            isRunning = false
        }
    }

    private func handleProcessCompletion(_ process: Process) async {
        let exitCode = process.terminationStatus
        isRunning = false
        currentProcess = nil

        // 可以发送通知或更新状态
        if exitCode != 0 {
            print("Claude Code exited with code: \(exitCode)")
        }
    }

    private func feedErrorMessage(to terminalView: ClaudeTerminalView, message: String) async {
        let errorText = "\u{001B}[31m❌ \(message)\u{001B}[0m\r\n"
        terminalView.feed(text: errorText)
    }

    private func resolveClaudeCodePath() -> String? {
        // 复用现有的路径解析逻辑
        let commonPaths = [
            NSString(string: "~/.claude/local/bin/claude").expandingTildeInPath,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            NSString(string: "~/.local/bin/claude").expandingTildeInPath,
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }
}
```

#### 2.2 创建自定义 TerminalView 包装

**位置**: `/Users/xiikii/Coding/HyperNote/Writedown/ClaudeCode/ClaudeTerminalView.swift`

```swift
import SwiftTerm
import AppKit

class ClaudeTerminalView: TerminalView {

    weak var terminalDelegate: ClaudeTerminalDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTerminal()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTerminal()
    }

    private func setupTerminal() {
        // 配置终端尺寸
        let terminal = getTerminal()
        terminal.resize(cols: 120, rows: 40)

        // 设置选择支持
        allowMouseReporting = true

        // 配置滚动
        scrollView?.hasVerticalScroller = true
        scrollView?.autohidesScrollers = true
    }

    /// 便捷方法：发送 ANSI 格式化文本
    func feedColored(text: String, color: ANSIColor) {
        let ansiText = "\(color.code)\(text)\u{001B}[0m"
        feed(text: ansiText)
    }
}

// MARK: - ANSI 颜色助手

enum ANSIColor {
    case red, green, yellow, blue, magenta, cyan, white, gray

    var code: String {
        switch self {
        case .red:     return "\u{001B}[31m"
        case .green:   return "\u{001B}[32m"
        case .yellow:  return "\u{001B}[33m"
        case .blue:    return "\u{001B}[34m"
        case .magenta: return "\u{001B}[35m"
        case .cyan:    return "\u{001B}[36m"
        case .white:   return "\u{001B}[37m"
        case .gray:    return "\u{001B}[90m"
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
```

#### 2.3 实现 TerminalViewDelegate

**位置**: `/Users/xiikii/Coding/HyperNote/Writedown/ClaudeCode/ClaudeTerminalDelegate.swift`

```swift
import SwiftTerm
import Foundation

class ClaudeTerminalDelegate: TerminalViewDelegate {

    weak var terminalView: ClaudeTerminalView?

    init(terminalView: ClaudeTerminalView) {
        self.terminalView = terminalView
    }

    // MARK: - TerminalViewDelegate

    /// 发送数据到运行的程序（键盘输入）
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        // 将数据发送到进程的 stdin
        // 如果使用 LocalProcess，它会自动处理
        // 如果手动管理 Process，需要写入 standardInput

        print("Sending data to process: \(String(bytes: data, encoding: .utf8) ?? "<binary>")")
    }

    /// 终端尺寸变化
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        print("Terminal resized to \(newCols)x\(newRows)")

        // 如果需要，通知进程窗口尺寸变化（SIGWINCH）
        // ioctl(pty_master, TIOCSWINSZ, ...)
    }

    /// 滚动位置变化
    func scrolled(source: TerminalView, position: Double) {
        // 可以用于实现自定义滚动指示器
    }

    /// 设置终端标题
    func setTerminalTitle(source: TerminalView, title: String) {
        print("Terminal title: \(title)")
    }

    /// 当前目录更新（如果 shell 支持 OSC 7）
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        if let dir = directory {
            print("Current directory: \(dir)")
        }
    }

    /// 铃声/提示音
    func bell(source: TerminalView) {
        NSSound.beep()
    }

    /// 剪贴板操作
    func clipboard(source: TerminalView) -> Data? {
        return NSPasteboard.general.data(forType: .string)
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        if let text = String(data: content, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    /// 行范围变化（用于优化渲染）
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        // SwiftTerm 内部使用，通常不需要处理
    }
}
```

---

### 阶段 3: 创建 SwiftUI 视图包装（2-3 小时）

#### 3.1 创建 SwiftUI 包装器

**位置**: `/Users/xiikii/Coding/HyperNote/Writedown/ClaudeCode/SwiftTerminalView.swift`

```swift
import SwiftUI
import SwiftTerm

struct SwiftTerminalView: NSViewRepresentable {

    let noteContent: String?
    let noteTitle: String?
    let workingDirectory: URL

    @StateObject private var service = SwiftTermService.shared

    func makeNSView(context: Context) -> ClaudeTerminalView {
        let terminalView = service.createTerminalView(
            noteContent: noteContent,
            noteTitle: noteTitle,
            workingDirectory: workingDirectory
        )

        return terminalView
    }

    func updateNSView(_ nsView: ClaudeTerminalView, context: Context) {
        // 如果需要响应 SwiftUI 状态变化，在这里更新
    }

    static func dismantleNSView(_ nsView: ClaudeTerminalView, coordinator: ()) {
        // 清理资源
        SwiftTermService.shared.cancel()
    }
}

// MARK: - 预览

struct SwiftTerminalView_Previews: PreviewProvider {
    static var previews: some View {
        SwiftTerminalView(
            noteContent: "Hello Claude",
            noteTitle: "Test Note",
            workingDirectory: URL(fileURLWithPath: NSHomeDirectory())
        )
        .frame(width: 800, height: 600)
    }
}
```

#### 3.2 更新 ClaudeCodeOutputView

**修改**: `/Users/xiikii/Coding/HyperNote/Writedown/ClaudeCode/ClaudeCodeOutputView.swift`

```swift
import SwiftUI

struct ClaudeCodeOutputView: View {

    let noteContent: String?
    let noteTitle: String?
    let workingDirectory: URL

    @Environment(\.presentationMode) var presentationMode
    @StateObject private var service = SwiftTermService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            // Terminal View（替换原有的 ScrollView + OutputLines）
            SwiftTerminalView(
                noteContent: noteContent,
                noteTitle: noteTitle,
                workingDirectory: workingDirectory
            )

            // Footer
            footerBar
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .foregroundColor(.blue)

            Text("Claude Code Terminal")
                .font(.headline)

            Spacer()

            if service.isRunning {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            }

            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var footerBar: some View {
        HStack {
            if let session = service.sessionInfo {
                Text("Model: \(session.model)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Cancel") {
                service.cancel()
            }
            .disabled(!service.isRunning)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
```

---

### 阶段 4: 集成到现有系统（2-3 小时）

#### 4.1 更新 ContentView

**修改**: `/Users/xiikii/Coding/HyperNote/Writedown/Note/ContentView.swift`

在 `EmbeddedClaudeCodePanel` 中替换输出显示：

```swift
// 原有代码（使用 ScrollView + VStack）
ScrollView {
    LazyVStack(alignment: .leading, spacing: 4) {
        ForEach(service.outputLines) { line in
            CompactOutputLineView(line: line)
        }
    }
}

// 替换为
SwiftTerminalView(
    noteContent: document.text,
    noteTitle: document.title,
    workingDirectory: URL(fileURLWithPath: NSHomeDirectory())
)
.frame(height: 300)
```

#### 4.2 移除冗余代码

**可删除的文件/代码**:

1. `ClaudeCodeService.swift` 中的大部分解析逻辑：
   - `processStreamJsonLine()`
   - `handleSystemMessage()`, `handleAssistantMessage()` 等
   - `appendOrAddText()`
   - `OutputLine` 和 `StreamType` 定义（如果不再需要）

2. `CompactOutputLineView` - 不再需要手动行渲染

**保留的部分**:

- CLI 路径解析逻辑 (`resolveClaudeCodePath()`)
- 权限管理（如果仍需要）
- 执行状态枚举（可简化）

---

### 阶段 5: 高级特性实现（3-5 小时）

#### 5.1 支持交互式输入

```swift
extension ClaudeTerminalView {

    /// 处理键盘输入
    override func keyDown(with event: NSEvent) {
        guard let characters = event.characters else {
            super.keyDown(with: event)
            return
        }

        // 转换为字节并发送
        if let data = characters.data(using: .utf8) {
            let bytes = [UInt8](data)
            send(data: ArraySlice(bytes))
        }

        // 处理特殊键
        if event.modifierFlags.contains(.control) {
            handleControlKey(event)
        }
    }

    private func handleControlKey(_ event: NSEvent) {
        guard let char = event.charactersIgnoringModifiers?.first else { return }

        // Ctrl+C -> 发送 SIGINT (0x03)
        if char == "c" {
            send(data: [0x03])
        }
        // Ctrl+D -> EOF (0x04)
        else if char == "d" {
            send(data: [0x04])
        }
    }
}
```

#### 5.2 权限请求集成

如果 Claude Code 仍需要权限确认，可以监听特定输出模式：

```swift
extension ClaudeTerminalDelegate {

    /// 监听终端输出以检测权限请求
    func dataReceived(source: TerminalView, data: ArraySlice<UInt8>) {
        guard let text = String(bytes: data, encoding: .utf8) else { return }

        // 检测权限请求模式（如果 Claude Code 有特定输出格式）
        if text.contains("Permission required") {
            DispatchQueue.main.async {
                self.showPermissionDialog(text: text)
            }
        }
    }

    private func showPermissionDialog(text: String) {
        let alert = NSAlert()
        alert.messageText = "Claude Code Permission Request"
        alert.informativeText = text
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")

        let response = alert.runModal()

        // 根据用户选择发送响应（如果 Claude Code 支持）
        if response == .alertFirstButtonReturn {
            terminalView?.feed(text: "yes\n")
        } else {
            terminalView?.feed(text: "no\n")
        }
    }
}
```

#### 5.3 会话管理和录制

```swift
class SwiftTermService {

    private var sessionRecorder: TerminalRecorder?

    func startRecording(to url: URL) {
        sessionRecorder = TerminalRecorder(outputURL: url)
    }

    func stopRecording() {
        sessionRecorder?.finalize()
        sessionRecorder = nil
    }
}

class TerminalRecorder {
    private let outputURL: URL
    private var events: [(timestamp: TimeInterval, data: Data)] = []
    private let startTime = Date()

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func record(data: Data) {
        let elapsed = Date().timeIntervalSince(startTime)
        events.append((elapsed, data))
    }

    func finalize() {
        // 保存为 asciinema 格式
        let jsonEncoder = JSONEncoder()
        // ... 编码逻辑
    }
}
```

---

### 阶段 6: 外观定制（1-2 小时）

#### 6.1 主题配置

```swift
extension ClaudeTerminalView {

    func applyTheme(_ theme: TerminalTheme) {
        nativeBackgroundColor = theme.background
        nativeForegroundColor = theme.foreground
        caretColor = theme.cursor

        // 设置 ANSI 颜色调色板
        let ansiColors: [NSColor] = [
            theme.black,
            theme.red,
            theme.green,
            theme.yellow,
            theme.blue,
            theme.magenta,
            theme.cyan,
            theme.white,
            // 亮色版本
            theme.brightBlack,
            theme.brightRed,
            theme.brightGreen,
            theme.brightYellow,
            theme.brightBlue,
            theme.brightMagenta,
            theme.brightCyan,
            theme.brightWhite
        ]

        installColors(ansiColors.map { Color($0) })
    }
}

struct TerminalTheme {
    let name: String
    let background: NSColor
    let foreground: NSColor
    let cursor: NSColor

    // ANSI 基础色
    let black: NSColor
    let red: NSColor
    let green: NSColor
    let yellow: NSColor
    let blue: NSColor
    let magenta: NSColor
    let cyan: NSColor
    let white: NSColor

    // ANSI 亮色
    let brightBlack: NSColor
    let brightRed: NSColor
    let brightGreen: NSColor
    let brightYellow: NSColor
    let brightBlue: NSColor
    let brightMagenta: NSColor
    let brightCyan: NSColor
    let brightWhite: NSColor

    // 预设主题
    static let dracula = TerminalTheme(
        name: "Dracula",
        background: NSColor(hex: "#282a36")!,
        foreground: NSColor(hex: "#f8f8f2")!,
        cursor: NSColor(hex: "#f8f8f2")!,
        black: NSColor(hex: "#21222c")!,
        red: NSColor(hex: "#ff5555")!,
        green: NSColor(hex: "#50fa7b")!,
        yellow: NSColor(hex: "#f1fa8c")!,
        blue: NSColor(hex: "#bd93f9")!,
        magenta: NSColor(hex: "#ff79c6")!,
        cyan: NSColor(hex: "#8be9fd")!,
        white: NSColor(hex: "#f8f8f2")!,
        brightBlack: NSColor(hex: "#6272a4")!,
        brightRed: NSColor(hex: "#ff6e6e")!,
        brightGreen: NSColor(hex: "#69ff94")!,
        brightYellow: NSColor(hex: "#ffffa5")!,
        brightBlue: NSColor(hex: "#d6acff")!,
        brightMagenta: NSColor(hex: "#ff92df")!,
        brightCyan: NSColor(hex: "#a4ffff")!,
        brightWhite: NSColor(hex: "#ffffff")!
    )

    static let vscode = TerminalTheme(
        name: "VS Code Dark",
        background: NSColor(hex: "#1e1e1e")!,
        foreground: NSColor(hex: "#cccccc")!,
        cursor: NSColor(hex: "#aeafad")!,
        black: NSColor(hex: "#000000")!,
        red: NSColor(hex: "#cd3131")!,
        green: NSColor(hex: "#0dbc79")!,
        yellow: NSColor(hex: "#e5e510")!,
        blue: NSColor(hex: "#2472c8")!,
        magenta: NSColor(hex: "#bc3fbc")!,
        cyan: NSColor(hex: "#11a8cd")!,
        white: NSColor(hex: "#e5e5e5")!,
        brightBlack: NSColor(hex: "#666666")!,
        brightRed: NSColor(hex: "#f14c4c")!,
        brightGreen: NSColor(hex: "#23d18b")!,
        brightYellow: NSColor(hex: "#f5f543")!,
        brightBlue: NSColor(hex: "#3b8eea")!,
        brightMagenta: NSColor(hex: "#d670d6")!,
        brightCyan: NSColor(hex: "#29b8db")!,
        brightWhite: NSColor(hex: "#ffffff")!
    )
}
```

#### 6.2 字体配置

```swift
extension ClaudeTerminalView {

    func applyFontSettings(fontName: String, size: CGFloat) {
        if let font = NSFont(name: fontName, size: size) {
            self.font = font
            resetFont()
        }
    }

    // 预设编程字体
    static let recommendedFonts = [
        "JetBrainsMono-Regular",
        "FiraCode-Regular",
        "MesloLGS-NF-Regular",
        "Menlo-Regular",
        "Monaco"
    ]
}
```

---

### 阶段 7: 测试和优化（2-3 小时）

#### 7.1 单元测试

```swift
import XCTest
@testable import Writedown

class SwiftTermServiceTests: XCTestCase {

    var service: SwiftTermService!

    override func setUpWithError() throws {
        service = SwiftTermService.shared
    }

    func testCLIPathResolution() {
        let path = service.resolveClaudeCodePath()
        XCTAssertNotNil(path, "Should find Claude Code CLI")
    }

    func testTerminalCreation() {
        let terminal = service.createTerminalView(
            noteContent: "test",
            noteTitle: "Test",
            workingDirectory: URL(fileURLWithPath: NSHomeDirectory())
        )

        XCTAssertNotNil(terminal)
        XCTAssertFalse(service.isRunning)
    }
}
```

#### 7.2 性能优化

**内存管理**:

```swift
class ClaudeTerminalView {

    deinit {
        // 清理资源
        getTerminal().softReset()
        terminalDelegate = nil
    }
}
```

**滚动缓冲区限制**:

```swift
extension ClaudeTerminalView {

    func configureScrollback(lines: Int = 10000) {
        let terminal = getTerminal()
        // SwiftTerm 自动管理滚动缓冲区
        // 可以通过 terminal.buffer 访问
    }
}
```

---

## 代码示例

### 完整使用示例

```swift
import SwiftUI

struct MainView: View {
    @State private var showTerminal = false
    @State private var noteContent = "帮我分析这个项目"

    var body: some View {
        VStack {
            TextEditor(text: $noteContent)
                .frame(height: 200)

            Button("Run Claude Code") {
                showTerminal = true
            }
        }
        .sheet(isPresented: $showTerminal) {
            ClaudeCodeOutputView(
                noteContent: noteContent,
                noteTitle: "My Note",
                workingDirectory: URL(fileURLWithPath: NSHomeDirectory())
            )
            .frame(width: 900, height: 700)
        }
    }
}
```

---

## 迁移注意事项

### 破坏性变更

1. **输出行模型变更**
   - 原有的 `OutputLine` 和 `StreamType` 枚举将被移除
   - 依赖这些模型的 UI 组件需要重构

2. **API 变更**
   - `ClaudeCodeService.execute()` → `SwiftTermService.createTerminalView()`
   - 不再有 `@Published outputLines`，改为直接显示终端

3. **权限处理变更**
   - 原有的 `PermissionRequest` 机制可能需要重新设计
   - 考虑使用终端内交互或弹窗

### 向后兼容策略

**阶段性迁移**:

1. 保留 `ClaudeCodeService` 作为旧版实现
2. 新增 `SwiftTermService` 作为新版实现
3. 提供用户设置选项在两者之间切换
4. 逐步弃用旧版

```swift
@AppStorage("useSwiftTerm") private var useSwiftTerm = false

var terminalView: some View {
    if useSwiftTerm {
        SwiftTerminalView(...)
    } else {
        LegacyOutputView(...)
    }
}
```

### 数据迁移

如果有保存的输出日志：

```swift
struct OutputLogMigrator {

    func convertToANSI(outputLines: [OutputLine]) -> String {
        var ansiText = ""

        for line in outputLines {
            let color = colorForStreamType(line.type)
            ansiText += "\(color.code)\(line.content)\u{001B}[0m\r\n"
        }

        return ansiText
    }

    private func colorForStreamType(_ type: StreamType) -> ANSIColor {
        switch type {
        case .stdout, .assistant: return .white
        case .stderr: return .yellow
        case .error: return .red
        case .thinking: return .cyan
        case .toolUse: return .magenta
        case .toolResult: return .green
        case .system: return .blue
        }
    }
}
```

---

## 优势对比

### 功能对比表

| 功能 | 现有实现 | SwiftTerm 实现 |
|-----|---------|---------------|
| ANSI 颜色支持 | ❌ 手动模拟 | ✅ 原生支持 |
| VT100/Xterm 兼容 | ❌ | ✅ 完整兼容 |
| 光标控制 | ❌ | ✅ 支持 |
| 滚动缓冲区 | ⚠️ 最多 1000 行 | ✅ 可配置（默认 10000+） |
| 文本选择 | ⚠️ 手动实现 | ✅ 原生支持 |
| 复制粘贴 | ⚠️ 基础功能 | ✅ 完整支持 |
| 交互式输入 | ❌ 单向输出 | ✅ 完整双向交互 |
| 图片显示 | ❌ | ✅ Sixel/iTerm2/Kitty |
| 鼠标支持 | ❌ | ✅ 完整鼠标事件 |
| 性能 | ⚠️ SwiftUI 限制 | ✅ 原生渲染，高性能 |
| Unicode/Emoji | ⚠️ 基础支持 | ✅ 完整支持 |
| 组合字符 | ❌ | ✅ 支持 |
| 双向文本 | ❌ | ✅ 支持 RTL |
| 终端录制 | ❌ | ✅ Asciinema 格式 |

### 性能对比

**渲染性能**:
- 现有实现：SwiftUI `LazyVStack` - 大量输出时性能下降
- SwiftTerm：原生 Core Text 渲染 - 稳定 60fps

**内存占用**:
- 现有实现：每行创建 SwiftUI View - 内存随行数线性增长
- SwiftTerm：缓冲区重用 - 内存占用恒定

---

## 风险评估

### 高风险项

1. **沙盒限制** ⚠️
   - **风险**: 禁用沙盒可能影响 App Store 审核
   - **缓解**:
     - 提供非沙盒版本（直接分发）
     - 使用临时权限异常
     - 申请特殊权限

2. **学习曲线** ⚠️
   - **风险**: 团队不熟悉 SwiftTerm API
   - **缓解**:
     - 详细文档和示例
     - 逐步迁移策略
     - 保留旧版作为备用

3. **CLI 兼容性** ⚠️
   - **风险**: `claude` CLI 可能不支持完整终端模式
   - **缓解**:
     - 测试所有 CLI 模式
     - 必要时保留 `stream-json` 解析
     - 提供降级机制

### 中风险项

1. **依赖维护** ⚠️
   - **风险**: SwiftTerm 可能停止维护
   - **缓解**:
     - Fork 仓库作为备份
     - 活跃的社区和商业使用案例

2. **性能问题** ⚠️
   - **风险**: 大量快速输出可能卡顿
   - **缓解**:
     - 配置合理的滚动缓冲区
     - 实现输出节流

### 低风险项

1. **UI 一致性** ✅
   - SwiftTerm 提供完整的外观定制 API

2. **向后兼容** ✅
   - 可以保留旧实现共存

---

## 总结和建议

### 推荐实施路径

**阶段 1: 概念验证（1 周）**
- 添加 SwiftTerm 依赖
- 创建最小可行原型
- 测试与 `claude` CLI 的兼容性

**阶段 2: 核心实现（2 周）**
- 完整实现 `SwiftTermService`
- 创建 SwiftUI 包装器
- 替换主要输出视图

**阶段 3: 功能增强（1 周）**
- 添加主题支持
- 实现交互式输入
- 权限管理集成

**阶段 4: 测试和优化（1 周）**
- 单元测试
- 性能测试
- 用户测试

**总计**: 约 5 周完整实施

### 关键决策点

1. **是否完全替代？**
   - ✅ 建议：完全替代，获得最大收益
   - ⚠️ 备选：混合模式，渐进迁移

2. **沙盒问题如何处理？**
   - ✅ 建议：提供两个版本（App Store 版 + 直接分发版）
   - ⚠️ 备选：申请特殊权限

3. **保留哪些现有功能？**
   - 保留：CLI 路径检测、执行状态管理
   - 移除：手动 JSON 解析、自定义渲染逻辑

### 最终建议

**强烈推荐使用 SwiftTerm**，理由：

1. ✅ **专业级终端仿真** - 完整的 VT100/Xterm 支持
2. ✅ **生产验证** - 多个商业应用采用
3. ✅ **性能优异** - 原生渲染远超 SwiftUI
4. ✅ **功能丰富** - 图片、鼠标、录制等高级特性
5. ✅ **代码简化** - 移除大量手动解析代码
6. ✅ **未来扩展** - 支持更多 CLI 工具集成

**唯一需要权衡的是沙盒限制**，但这可以通过提供直接分发版本解决。

---

## 附录

### 相关资源

- [SwiftTerm GitHub](https://github.com/migueldeicaza/SwiftTerm)
- [SwiftTerm Documentation](https://migueldeicaza.github.io/SwiftTermDocs/documentation/swiftterm/)
- [LocalProcessTerminalView Reference](https://migueldeicaza.github.io/SwiftTerm/Classes/LocalProcessTerminalView.html)
- [SwiftTerm Example](https://github.com/ajhekman/SwiftTerm-Example)
- [Discussion: Capturing Shell Output](https://github.com/migueldeicaza/SwiftTerm/discussions/308)

### 联系方式

如有技术问题，可以：
- 在 SwiftTerm GitHub 提 Issue
- 参与 Discussions
- 查阅示例代码 `TerminalApp/`

---

**文档版本**: 1.0
**最后更新**: 2026-01-25
**作者**: Claude Code Migration Team
