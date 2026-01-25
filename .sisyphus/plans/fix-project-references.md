# Fix Xcode Project References

## Context
The previous task created `OpenCodeService.swift` and related UI files but did not add them to the `Writedown.xcodeproj` project file. This causes the "Cannot find ... in scope" compiler error.

## Work Objectives
Programmatically add the missing file references to the Xcode project using the `xcodeproj` Ruby gem.

## TODOs

- [ ] 1. Create `scripts/add_opencode_files.rb`
  **What to do**:
  - Write a Ruby script using `xcodeproj` gem.
  - Script should find `Writedown` target.
  - Add `Services/OpenCodeService.swift` to `Services` group.
  - Add `OpenCode/*.swift` to `OpenCode` group.
  - Add all to `Sources` build phase.
  - Save project.

  **Acceptance Criteria**:
  - [ ] Script exists.

- [ ] 2. Run the fix script
  **What to do**:
  - Execute `ruby scripts/add_opencode_files.rb`.

  **Acceptance Criteria**:
  - [ ] Output says "Project saved successfully".
  - [ ] `grep` checks confirm file IDs are in `project.pbxproj`.

- [ ] 3. Cleanup
  **What to do**:
  - Remove `scripts/add_opencode_files.rb`.

  **Acceptance Criteria**:
  - [ ] Script deleted.
