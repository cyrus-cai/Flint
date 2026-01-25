# ✅ SwiftTerm 测试按钮已添加

## 📍 位置

已在主笔记页面（ContentView）的编辑器下方添加了一个蓝色的 "测试 SwiftTerm" 按钮。

## 🎯 使用方法

### 1. 添加 SwiftTerm 依赖（必须先完成）

在 Xcode 中：
1. 打开项目 `Writedown.xcodeproj`
2. 选择 `Writedown` target → `Package Dependencies`
3. 点击 `+` 添加：`https://github.com/migueldeicaza/SwiftTerm`

### 2. 配置权限

编辑 `Writedown/Writedown.entitlements`：

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

### 3. 测试

1. **编译项目**：`Command + B`
2. **运行应用**：`Command + R`
3. 在主笔记窗口，你会在编辑器下方看到蓝色的 **"测试 SwiftTerm"** 按钮
4. 点击按钮会弹出终端窗口
5. 如果笔记有内容，会发送笔记内容给 Claude；如果为空，会发送测试提示语

## 🎨 按钮外观

```
┌──────────────────────────────┐
│  [Editor Area]               │
│                              │
│                              │
└──────────────────────────────┘
              ┌────────────────┐
              │ 🖥️ 测试 SwiftTerm│  ← 蓝色按钮
              └────────────────┘
┌──────────────────────────────┐
│  [Down Function View]        │
└──────────────────────────────┘
```

## 📋 弹出窗口功能

点击按钮后会打开一个新窗口，包含：

- **顶部栏**：
  - 终端图标 🖥️
  - 标题："Claude Code Terminal"
  - 主题选择器（VS Code Dark / Dracula / One Dark）
  - 运行状态指示器
  - 关闭按钮

- **终端区域**：
  - 完整的终端仿真
  - ANSI 颜色支持
  - 文本选择和复制
  - 滚动功能

- **底部栏**：
  - 会话信息（模型、工作目录）
  - 取消/关闭按钮

## ✅ 验证清单

运行后检查：

- [ ] 按钮在编辑器下方正确显示
- [ ] 点击按钮弹出终端窗口
- [ ] 终端窗口尺寸为 900x700
- [ ] Claude CLI 进程启动（检查 Xcode 控制台）
- [ ] 终端中显示输出
- [ ] 可以选择和复制文本
- [ ] 主题切换正常工作
- [ ] 可以取消执行
- [ ] 关闭窗口正常

## 🔧 故障排除

### 按钮不显示
- 检查是否在正确的视图（主笔记页面）
- 重新编译项目

### 点击无反应
- 检查 SwiftTerm 依赖是否正确添加
- 查看 Xcode 控制台的错误信息

### 编译错误
- 确认已添加 SwiftTerm 依赖
- 检查所有文件都已添加到项目中
- 尝试 `Product` → `Clean Build Folder`

### 运行时崩溃
- 检查沙盒配置
- 查看 Xcode 控制台的详细错误
- 确认 Claude CLI 已安装

## 🗑️ 移除测试按钮（测试完成后）

测试完成后，可以删除以下代码：

### 1. 删除状态变量（第 68 行）
```swift
// 🧪 SwiftTerm 测试
@State private var showSwiftTermTest = false
```

### 2. 删除按钮代码（第 436-458 行）
```swift
// 🧪 SwiftTerm 测试按钮（临时）
HStack {
    // ... 整个按钮代码块
}
```

### 3. 删除弹窗代码（第 513-521 行）
```swift
// 🧪 SwiftTerm 测试窗口
.sheet(isPresented: $showSwiftTermTest) {
    // ... 整个弹窗代码块
}
```

或者直接运行：
```bash
git checkout Writedown/Note/ContentView.swift
```

## 📊 代码改动摘要

**文件**: `Writedown/Note/ContentView.swift`

**改动**:
- 添加了 1 个状态变量
- 添加了 1 个测试按钮（23 行代码）
- 添加了 1 个弹窗定义（9 行代码）
- 总计：约 33 行代码

**影响**:
- 不影响任何现有功能
- 纯增量修改
- 可随时移除

---

**开始测试吧！** 🚀

记得先完成步骤 1（添加依赖）和步骤 2（配置权限）。
