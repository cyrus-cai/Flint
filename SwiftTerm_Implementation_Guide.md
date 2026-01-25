# SwiftTerm 实施指南

> **状态**: 概念验证阶段
> **日期**: 2026-01-25

---

## ✅ 已完成的工作

我已经创建了以下核心文件，实现了 SwiftTerm 集成的基础架构：

### 1. 服务层
- **SwiftTermService.swift** (`Writedown/Services/`)
  - 管理终端视图创建和进程生命周期
  - 处理 Claude CLI 路径检测
  - 配置进程环境和参数
  - 异步读取输出并喂给终端

### 2. 终端视图组件
- **ClaudeTerminalView.swift** (`Writedown/ClaudeCode/`)
  - 继承自 SwiftTerm 的 `TerminalView`
  - 提供 ANSI 颜色便捷方法
  - 包含 3 个预设主题（VS Code Dark、Dracula、One Dark）
  - 支持主题切换

### 3. 代理实现
- **ClaudeTerminalDelegate.swift** (`Writedown/ClaudeCode/`)
  - 实现 `TerminalViewDelegate` 协议
  - 处理数据发送、剪贴板、铃声等事件
  - 支持终端标题更新

### 4. SwiftUI 包装器
- **SwiftTerminalView.swift** (`Writedown/ClaudeCode/`)
  - `NSViewRepresentable` 包装器
  - 支持主题化版本
  - 包含预览代码

### 5. 窗口视图
- **ClaudeCodeTerminalWindow.swift** (`Writedown/ClaudeCode/`)
  - 替代原有的 `ClaudeCodeOutputView`
  - 包含头部栏、终端视图、底部栏
  - 支持主题切换、状态显示

---

## 🔧 下一步：添加依赖

### ⚠️ 重要：必须手动完成

**当前所有 Swift 文件都显示 "No such module 'SwiftTerm'" 错误**，这是正常的，因为还没有添加依赖。

### 操作步骤

1. **打开 Xcode 项目**
   ```bash
   open Writedown.xcodeproj
   ```

2. **添加 Swift Package**
   - 在项目导航器中选择 `Writedown` 项目（蓝色图标）
   - 选择 `Writedown` target
   - 切换到 `Package Dependencies` 标签
   - 点击 `+` 按钮
   - 输入仓库 URL：
     ```
     https://github.com/migueldeicaza/SwiftTerm
     ```
   - 选择 `Up to Next Major Version`，最低版本选择最新的（例如 1.0.0）
   - 点击 `Add Package`
   - 在弹出的产品选择窗口中，确保 `SwiftTerm` 被选中
   - 点击 `Add Package`

3. **验证依赖**
   - 在项目导航器左侧应该能看到 `Package Dependencies` 节点
   - 展开后应该有 `SwiftTerm` 条目
   - 编译错误应该消失

4. **重新构建项目**
   ```
   Command + B
   ```

---

## ⚙️ 沙盒配置（重要）

SwiftTerm 使用伪终端 (pty)，需要特定权限。

### 方式 1: 禁用沙盒（开发阶段推荐）

编辑 `Writedown.entitlements`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- 现有权限保持不变 -->

    <!-- 禁用沙盒 -->
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

### 方式 2: 保留沙盒并添加权限（生产环境）

```xml
<dict>
    <!-- 保留沙盒 -->
    <key>com.apple.security.app-sandbox</key>
    <true/>

    <!-- 添加设备访问权限 -->
    <key>com.apple.security.device.serial</key>
    <true/>

    <!-- 文件系统访问 -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
```

**注意**: App Store 审核可能拒绝没有充分理由禁用沙盒的应用。考虑提供两个版本：
- **App Store 版本**: 保留沙盒，功能受限
- **直接分发版本**: 禁用沙盒，完整功能

---

## 🧪 测试实施

### 1. 快速测试

在任何视图中添加测试按钮：

```swift
import SwiftUI

struct TestTerminalView: View {
    @State private var showTerminal = false

    var body: some View {
        VStack {
            Button("Test SwiftTerm") {
                showTerminal = true
            }
        }
        .sheet(isPresented: $showTerminal) {
            ClaudeCodeTerminalWindow(
                noteContent: "帮我分析这个项目",
                noteTitle: "测试",
                workingDirectory: URL(fileURLWithPath: NSHomeDirectory())
            )
        }
    }
}
```

### 2. 替换现有 ClaudeCodeOutputView

在显示终端的地方（例如 `ContentView.swift` 或其他触发位置）：

**原代码**:
```swift
ClaudeCodeOutputView(...)
```

**新代码**:
```swift
ClaudeCodeTerminalWindow(
    noteContent: document.text,
    noteTitle: document.title,
    workingDirectory: URL(fileURLWithPath: NSHomeDirectory())
)
```

### 3. 测试检查清单

运行应用并测试以下功能：

- [ ] 终端窗口成功打开
- [ ] Claude CLI 进程启动
- [ ] 能看到彩色输出（如果 Claude 使用 ANSI 颜色）
- [ ] 文本选择和复制功能正常
- [ ] 滚动流畅
- [ ] 主题切换工作正常
- [ ] 可以取消执行
- [ ] 进程结束后显示完成消息

---

## 🐛 故障排除

### 问题 1: 找不到 Claude CLI

**症状**: 终端显示 "❌ Claude Code CLI not found"

**解决**:
1. 确认 Claude CLI 已安装：
   ```bash
   which claude
   ```
2. 如果使用自定义路径，在设置中配置
3. 检查 `SwiftTermService.resolveClaudeCodePath()` 的路径列表

### 问题 2: 进程启动失败

**症状**: 终端显示 "Failed to launch"

**可能原因**:
- 沙盒权限不足
- 工作目录不存在
- CLI 路径无执行权限

**解决**:
1. 检查沙盒配置（见上文）
2. 验证工作目录有效
3. 检查 CLI 权限：
   ```bash
   ls -la $(which claude)
   chmod +x $(which claude)  # 如果需要
   ```

### 问题 3: 输出没有颜色

**症状**: 所有文本都是白色

**原因**: Claude CLI 可能检测到非终端环境，禁用了颜色

**解决**: 已在代码中设置环境变量 `FORCE_COLOR=1` 和 `TERM=xterm-256color`

如果仍无效，可以尝试：
```swift
// 在 SwiftTermService.startClaudeProcess() 中添加
env["CLICOLOR_FORCE"] = "1"
```

### 问题 4: 终端尺寸不正确

**症状**: 输出换行位置错误

**解决**: 调整终端初始尺寸
```swift
// 在 ClaudeTerminalView.setupTerminal() 中
terminal.resize(cols: 150, rows: 50)  // 调整数值
```

---

## 📊 性能优化建议

### 1. 滚动缓冲区限制

如果输出非常大，考虑限制历史行数：

```swift
// 在 ClaudeTerminalView 中添加
func configureScrollback(lines: Int = 10000) {
    let terminal = getTerminal()
    // SwiftTerm 内部管理，通常不需要手动配置
}
```

### 2. 输出节流

如果 CLI 输出速度极快，可以添加节流：

```swift
// 在 SwiftTermService.startClaudeProcess() 的读取循环中
var buffer = ""
var lastUpdate = Date()

for try await line in bytes.lines {
    buffer += line + "\r\n"

    // 每 50ms 批量更新
    if Date().timeIntervalSince(lastUpdate) > 0.05 {
        await terminalView.feed(text: buffer)
        buffer = ""
        lastUpdate = Date()
    }
}

// 发送剩余缓冲
if !buffer.isEmpty {
    await terminalView.feed(text: buffer)
}
```

---

## 🔄 与现有系统集成

### 保留旧实现（渐进迁移）

如果想同时保留两个版本：

```swift
struct ContentView: View {
    @AppStorage("useSwiftTerm") private var useSwiftTerm = false

    var terminalView: some View {
        if useSwiftTerm {
            ClaudeCodeTerminalWindow(...)
        } else {
            ClaudeCodeOutputView(...)  // 旧实现
        }
    }
}
```

在设置中添加切换选项：

```swift
Toggle("使用 SwiftTerm 终端 (实验性)", isOn: $useSwiftTerm)
```

### 迁移现有功能

#### 权限请求

如果需要保留权限请求横幅，可以在终端输出中检测特定模式：

```swift
extension ClaudeTerminalDelegate {
    func dataReceived(data: ArraySlice<UInt8>) {
        guard let text = String(bytes: data, encoding: .utf8) else { return }

        // 检测权限请求（如果 Claude 有特定输出格式）
        if text.contains("Permission required") {
            // 显示 SwiftUI 弹窗
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .permissionRequested,
                    object: text
                )
            }
        }
    }
}
```

#### 浮动状态指示器

可以复用现有的 `ClaudeCodeFloatingStatusView`：

```swift
// 在显示终端的视图中
.overlay(alignment: .topTrailing) {
    if service.isRunning {
        ClaudeCodeFloatingStatusView()
            .padding()
    }
}
```

---

## 📈 后续增强计划

### 阶段 2: 交互式输入

```swift
// 添加到 ClaudeTerminalView
override func keyDown(with event: NSEvent) {
    guard let characters = event.characters else {
        super.keyDown(with: event)
        return
    }

    // 发送键盘输入到进程
    if let data = characters.data(using: .utf8) {
        let bytes = [UInt8](data)
        send(data: ArraySlice(bytes))
    }
}
```

### 阶段 3: 会话录制

```swift
class TerminalRecorder {
    private var events: [(timestamp: TimeInterval, data: Data)] = []

    func record(data: Data) {
        events.append((Date().timeIntervalSinceNow, data))
    }

    func saveAsAsciinema(to url: URL) {
        // 保存为 asciinema 格式
    }
}
```

### 阶段 4: 自定义渲染

```swift
// 在特定输出上添加可点击链接
extension ClaudeTerminalView {
    func makeLinksClickable() {
        // 检测 URL 模式并添加点击处理
    }
}
```

---

## ✅ 验收标准

概念验证成功的标准：

1. **基础功能**
   - [x] 代码文件已创建
   - [ ] SwiftTerm 依赖已添加
   - [ ] 编译无错误
   - [ ] 终端窗口可以打开

2. **核心功能**
   - [ ] Claude CLI 进程成功启动
   - [ ] 输出正确显示在终端中
   - [ ] 支持 ANSI 颜色（如果 CLI 使用）
   - [ ] 文本可以选择和复制

3. **用户体验**
   - [ ] 滚动流畅
   - [ ] 主题切换工作
   - [ ] 可以取消执行
   - [ ] 性能可接受（无卡顿）

---

## 📝 下一步行动

### 立即执行

1. **添加 SwiftTerm 依赖**（见上文操作步骤）
2. **配置沙盒权限**（开发阶段建议禁用）
3. **编译项目** (`Command + B`)
4. **运行测试** - 创建测试按钮或替换现有视图

### 如果成功

- 逐步替换现有的 `ClaudeCodeOutputView` 使用
- 收集用户反馈
- 计划功能增强（交互式输入、录制等）

### 如果遇到问题

- 参考故障排除部分
- 检查 Claude CLI 是否支持终端输出模式
- 考虑降级到混合模式（保留 stream-json 解析）

---

## 📞 需要帮助？

如果遇到问题：

1. 检查 Xcode 控制台的详细错误信息
2. 验证 Claude CLI 在终端中手动运行是否正常
3. 参考 SwiftTerm 示例：`https://github.com/migueldeicaza/SwiftTerm/tree/main/TerminalApp`
4. 查看迁移计划文档：`SwiftTerm_Migration_Plan.md`

---

**祝实施顺利！** 🚀
