# Fix OpenCodeService Runtime Crash

## Context
The application crashes with `EXC_BREAKPOINT` at `static let shared = OpenCodeService()`.
This is likely due to `OpenCodeService` being marked `@MainActor`, but the static initializer might be called from a non-main context or in a way that Swift's concurrency model disallows for global actors in this specific version/configuration.

Also, `private init()` calls `resolveOpenCodePath()` which accesses `UserDefaults`, which is thread-safe but the overall initialization flow on `@MainActor` might be tricky if accessed improperly.

## Objectives
Fix the crash by ensuring `OpenCodeService.shared` is safely initialized, potentially by removing `@MainActor` from the class and applying it only to the properties/methods that need UI updates, or by ensuring the singleton is accessed correctly.

Given `ObservableObject` usually requires `@MainActor` for published property updates, we should keep it but perhaps relax the strictness on the shared instance or initialization.

## Plan
1.  Remove `@MainActor` from the class definition.
2.  Add `@MainActor` to the `execute` method and other methods that update `@Published` properties.
3.  Alternatively, keep `@MainActor` but move initialization logic to a separate setup method if needed.

*Self-Correction*: The safest fix for `ObservableObject` singletons causing crashes is often to ensure the `init` is safe.
Actually, the crash might be because `resolveOpenCodePath` uses `Process` which might have thread affinity issues or `FileManager`.

Let's try removing `@MainActor` from the *class* and adding it to the *properties* and *methods* that interact with UI.

## TODOs

- [ ] 1. Refactor `OpenCodeService.swift` concurrency
  **What to do**:
  - Remove `@MainActor` from class declaration.
  - Annotate `state`, `outputLines`, `pendingPermission`, `sessionInfo` with `@MainActor` (or ensure they are updated on main thread).
  - Actually, `ObservableObject` published properties update the UI, so the whole class usually *should* be MainActor.
  - **Better Fix**: The crash `EXC_BREAKPOINT` often indicates a swift runtime check failure.
  - Let's try to make `shared` explicitly `@MainActor static let shared`.
  
  **Wait**, if I access `OpenCodeService.shared` from a background thread (like in the WindowController init or View init if not careful), it might crash.
  
  **Proposed Fix**:
  - Remove `@MainActor` from the class.
  - Update `@Published` properties on `MainActor` explicitly in the methods (using `await MainActor.run` or `Task { @MainActor in ... }`).
  - This is safer and more robust.

  **Refined Plan**:
  1. Remove `@MainActor` from `class OpenCodeService`.
  2. In `execute`, `cancel`, `clearOutput`, etc., ensure `state` and `outputLines` are modified on MainActor.
  
  *Wait, `OpenCodeOutputView` observes it.* `ObservableObject` needs to publish on main thread.
  
  Let's try a simpler fix first: Keep `@MainActor` on the class, but verify where it's being called. The view calls it: `@ObservedObject var service = OpenCodeService.shared`. This is correct.
  
  Maybe `resolveOpenCodePath` is doing something bad during `init`.
  
  Let's assume the crash is due to the global actor strictness. I will remove `@MainActor` from the class and manually dispatch updates. This is the "old reliable" way to fix concurrency crashes in Swift UI services.

- [ ] 2. Apply "Manual MainActor Dispatch" pattern
  **What to do**:
  - Remove `@MainActor` from `class OpenCodeService`.
  - In `addOutputLine`, `addSystemMessage`, `state` setters -> wrap in `DispatchQueue.main.async` or `await MainActor.run`.

  **Acceptance Criteria**:
  - [ ] Service compiles.
  - [ ] No crash on launch.
