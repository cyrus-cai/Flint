# SwiftTerm 快速启动指南

> **5 分钟快速开始使用 SwiftTerm**

---

## 🎯 目标

将 HyperNote 的 Claude Code 输出从当前的简易文本显示升级为完整的终端仿真。

---

## 📋 前置检查

- [ ] Xcode 已打开项目
- [ ] Claude CLI 已安装（运行 `which claude` 验证）
- [ ] macOS 13.0+ (如果使用更低版本，检查 SwiftTerm 兼容性)

---

## 🚀 3 步启动

### 步骤 1: 添加 SwiftTerm 依赖（2 分钟）

1. 在 Xcode 中打开 `Writedown.xcodeproj`
2. 选择项目 → `Writedown` target → `Package Dependencies`
3. 点击 `+` 按钮
4. 粘贴 URL：
   ```
   https://github.com/migueldeicaza/SwiftTerm
   ```
5. 点击 `Add Package` → `Add Package`

### 步骤 2: 配置权限（1 分钟）

编辑 `Writedown/Writedown.entitlements`，临时禁用沙盒：

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

> ⚠️ 这是开发阶段的简化配置。生产环境需要更细粒度的权限。

### 步骤 3: 测试运行（2 分钟）

1. 编译项目 (`Command + B`)
2. 在任意视图中添加测试代码：

```swift
import SwiftUI

struct TestView: View {
    @State private var showTerminal = false

    var body: some View {
        Button("测试 SwiftTerm") {
            showTerminal = true
        }
        .sheet(isPresented: $showTerminal) {
            ClaudeCodeTerminalWindow(
                noteContent: "帮我分析项目结构",
                noteTitle: "测试",
                workingDirectory: URL(fileURLWithPath: NSHomeDirectory())
            )
        }
    }
}
```

3. 运行并点击按钮

---

## ✅ 验证成功

你应该看到：

- ✅ 新窗口打开，显示终端界面
- ✅ 顶部有标题栏和主题选择器
- ✅ Claude CLI 输出显示在终端中
- ✅ 文本可以选择和复制
- ✅ 底部显示状态信息

---

## 🐛 遇到问题？

### CLI 未找到

```bash
# 安装 Claude CLI
curl -fsSL https://claude.ai/install.sh | bash

# 验证
which claude
```

### 编译错误

- 确认 SwiftTerm 依赖已正确添加
- 检查 Package Dependencies 列表中是否有 SwiftTerm
- 尝试 `Product` → `Clean Build Folder`

### 运行时错误

- 检查沙盒是否已禁用
- 查看 Xcode 控制台的详细错误信息

---

## 📚 详细文档

- **完整实施计划**: `SwiftTerm_Migration_Plan.md`
- **实施指南**: `SwiftTerm_Implementation_Guide.md`

---

## 🎉 下一步

成功后，可以：

1. 替换现有的 `ClaudeCodeOutputView` 为 `ClaudeCodeTerminalWindow`
2. 尝试不同主题（VS Code Dark、Dracula、One Dark）
3. 测试复杂的 CLI 输出（颜色、进度条等）
4. 规划功能增强（交互式输入、录制等）

**开始使用吧！** 🚀
