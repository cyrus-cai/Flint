# Fix OpenCodeOutputView Compilation

## Context
There is a conflict between `ClaudeCodeOutputView.swift` and `OpenCodeOutputView.swift` because both define `OutputLineView` (implicitly or explicitly during my copy-paste refactor).
Also, the LSP is reporting "Cannot find 'OpenCodeService' in scope", which is likely a false positive or due to the file being recently added to the project but not yet indexed. The previous task confirmed `OpenCodeService.swift` was added to the target.

## Objectives
1.  Rename `OutputLineView` in `OpenCodeOutputView.swift` to `OpenCodeOutputLineView` to avoid conflict.
2.  Ensure correct usage of `OpenCodeService.OutputLine`.
3.  Force a clean/re-index if needed (simulated by verifying file content).

## TODOs

- [ ] 1. Rename `OutputLineView` in `OpenCodeOutputView.swift`
  **What to do**:
  - Rename the struct to `OpenCodeOutputLineView`.
  - Update usage in `OpenCodeOutputView`.
  - Ensure `timeFormatter` is correctly included (it seemed to be missing in the read, or I missed it).

  **Acceptance Criteria**:
  - [ ] No redeclaration errors.

- [ ] 2. Verify `OpenCodeService` availability
  **What to do**:
  - The LSP error might be persistent until a full build. I will rely on the code correctness.
  - Check `OpenCodeService.swift` again to ensure it is `public` or internal (default) and compiles.

  **Acceptance Criteria**:
  - [ ] Code looks correct.
