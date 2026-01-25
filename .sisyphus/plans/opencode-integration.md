# Integrate OpenCode CLI into HyperNote

## Context

### Original Request
Integrate "OpenCode" CLI into HyperNote similar to "Claude Code".

### Interview Summary
**Key Discussions**:
- **Target**: `opencode` CLI.
- **Method**: CLI process spawning (`Process`).
- **Output**: JSON streaming (`--format json`) confirmed.
- **UI**: Replicate existing terminal/window pattern.

**Research Findings**:
- `opencode` supports `run` command with JSON output.
- Existing `ClaudeCodeService` uses a robust `Process` + `Pipe` + JSON parsing architecture.
- `TitleBarView.swift` is the UI entry point.

### Metis Review
**Identified Gaps** (addressed):
- **JSON Schema**: Verified `type` field exists in OpenCode output. `OpenCodeService` will handle standard event types and fallback gracefully.
- **Model Selection**: OpenCode requires a model. Service should allow passing a model or rely on default configuration. *Self-Correction*: Will use default unless configured.

---

## Work Objectives

### Core Objective
Enable users to launch OpenCode sessions directly from HyperNote to analyze/edit the current note.

### Concrete Deliverables
- `OpenCodeService.swift` (Service layer)
- `OpenCodeTerminalWindowController.swift` (Window management)
- `OpenCodeTerminalWindow.swift` (SwiftUI wrapper)
- `OpenCodeOutputView.swift` (UI for stream output)
- Updated `TitleBarView.swift` (Entry point)

### Definition of Done
- [ ] Clicking "OpenCode" button in TitleBar launches a window.
- [ ] Window shows "Starting OpenCode...".
- [ ] Note content is passed to `opencode run`.
- [ ] Output from `opencode` is streamed and displayed in the window.
- [ ] Streaming tokens (thinking/text) appear in real-time.

### Must Have
- `opencode` CLI detection.
- JSON stream parsing.
- Independent window (non-blocking).

### Must NOT Have
- Deep API client implementation (unless CLI fails).
- Modification of `opencode` binary.

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES (HyperNote has tests, but CLI integration is hard to unit test).
- **User wants tests**: Manual verification is key for UI/Process tasks.
- **QA approach**: Manual verification procedures.

### Manual Execution Verification

**For UI/Integration changes:**
- [ ] **Launch**: Open a note, click "OpenCode" icon.
- [ ] **Process**: Verify `opencode` process starts (Activity Monitor or `ps`).
- [ ] **Output**: Verify text appears in the new window.
- [ ] **Interaction**: Verify window can be closed/minimized.

---

## Task Flow

```
1. Create Service (OpenCodeService)
        ↓
2. Create UI Components (Window/View)
        ↓
3. Integrate (TitleBarView)
```

---

## TODOs

- [ ] 1. Create `OpenCodeService.swift`
  **What to do**:
  - Clone `Writedown/Services/ClaudeCodeService.swift` to `Writedown/Services/OpenCodeService.swift`.
  - Rename class `ClaudeCodeService` to `OpenCodeService`.
  - Update `resolveClaudeCodePath` to `resolveOpenCodePath` (search for `opencode`).
  - Update `execute` method:
    - Executable: `opencode`
    - Arguments: `run`, `-p` (or equivalent `[message]`), `--format`, `json`, `--model`, `google/gemini-2.0-flash` (or configurable).
    - Note: `opencode run "content"` might behave differently than `claude -p "content"`. Check if `opencode` accepts content as first arg. (Yes, `opencode run [message..]`).
  - Update `processStreamJsonLine` to handle OpenCode specific events if needed (or keep generic `type` handling).

  **References**:
  - `Writedown/Services/ClaudeCodeService.swift` (Source template)

  **Acceptance Criteria**:
  - [ ] Compiles without errors.
  - [ ] `OpenCodeService.shared` is available.

- [ ] 2. Create `OpenCodeOutputView.swift`
  **What to do**:
  - Clone `Writedown/ClaudeCode/ClaudeCodeOutputView.swift` to `Writedown/OpenCode/OpenCodeOutputView.swift`.
  - Rename class and binding types.
  - Ensure it binds to `OpenCodeService` instead of `ClaudeCodeService`.

  **References**:
  - `Writedown/ClaudeCode/ClaudeCodeOutputView.swift`

  **Acceptance Criteria**:
  - [ ] View compiles.

- [ ] 3. Create `OpenCodeTerminalWindow.swift`
  **What to do**:
  - Clone `Writedown/ClaudeCode/ClaudeCodeTerminalWindow.swift` to `Writedown/OpenCode/OpenCodeTerminalWindow.swift`.
  - Rename class.
  - Use `OpenCodeOutputView` inside.
  - Trigger `OpenCodeService.shared.execute` on appear.

  **References**:
  - `Writedown/ClaudeCode/ClaudeCodeTerminalWindow.swift`

  **Acceptance Criteria**:
  - [ ] Compiles.

- [ ] 4. Create `OpenCodeTerminalWindowController.swift`
  **What to do**:
  - Clone `Writedown/ClaudeCode/ClaudeCodeTerminalWindowController.swift` to `Writedown/OpenCode/OpenCodeTerminalWindowController.swift`.
  - Rename class `ClaudeCodeTerminalWindowController` to `OpenCodeTerminalWindowController`.
  - Use `OpenCodeTerminalWindow` as root view.
  - Update window title to "OpenCode Terminal".

  **References**:
  - `Writedown/ClaudeCode/ClaudeCodeTerminalWindowController.swift`

  **Acceptance Criteria**:
  - [ ] Controller can be instantiated.

- [ ] 5. Update `SettingsListView.swift`
  **What to do**:
  - Add `case testOpenCode` to `SettingsItem` enum.
  - Add `onTestOpenCode: () -> Void` property to `SettingsListView`.
  - Update `handleAction`, `title`, and `icon` properties for the new case.
  - Ensure "Test Opencode" appears below "Test Claude Code".

  **References**:
  - `Writedown/Note/ContentViewComponents/SettingsListView.swift`

  **Acceptance Criteria**:
  - [ ] Compiles.
  - [ ] Button appears in Settings list.

- [ ] 6. Update `TitleBarView.swift`
  **What to do**:
  - Update `SettingsListView` initialization in `TitleBarToolbar` to pass `onTestOpenCode`.
  - Add `onTestOpenCode` closure to `TitleBarToolbarState`.
  - Implement `openOpenCodeWindow` in `TitleBarToolbarState`.
  - Trigger `OpenCodeTerminalWindowController.show` inside the closure.

  **References**:
  - `Writedown/Note/ContentViewComponents/TitleBarView.swift`

  **Acceptance Criteria**:
  - [ ] Clicking "Test Opencode" launches the terminal window.
