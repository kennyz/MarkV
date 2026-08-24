# Markv Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS Markdown viewer/editor named Markv with directory browsing and recent files.

**Architecture:** A Swift Package executable hosts a SwiftUI app. `AppModel` owns file-system and document state, `MarkdownRenderer` converts safe Markdown to HTML, and `MarkdownWebView` displays live styled preview content with WebKit.

**Tech Stack:** Swift 6, SwiftUI, AppKit, WebKit, XCTest/Swift Testing, Swift Package Manager

---

### Task 1: Package and document model

**Files:**
- Create: `Package.swift`
- Create: `Sources/Markv/AppModel.swift`
- Test: `Tests/MarkvTests/AppModelTests.swift`

1. Define the executable and test targets.
2. Write tests for Markdown extension filtering and recent-file de-duplication.
3. Implement folder scanning, document loading, dirty state, persistence, and saving.
4. Run `swift test` and confirm the model tests pass.

### Task 2: Markdown rendering

**Files:**
- Create: `Sources/Markv/MarkdownRenderer.swift`
- Test: `Tests/MarkvTests/MarkdownRendererTests.swift`

1. Write tests for escaping, headings, inline syntax, fenced code, lists, and tables.
2. Implement a deterministic renderer that never executes raw document HTML.
3. Run `swift test` and confirm all renderer tests pass.

### Task 3: Native interface

**Files:**
- Create: `Sources/Markv/MarkvApp.swift`
- Create: `Sources/Markv/ContentView.swift`
- Create: `Sources/Markv/MarkdownWebView.swift`

1. Build the directory/recent-files sidebar.
2. Add Preview, Source, and Split document modes.
3. Add empty state, file metadata, dirty indicator, save and directory actions.
4. Add Command-S and Command-O commands and unsaved-change confirmation.
5. Build the debug executable and launch it for a visual check.

### Task 4: Application packaging

**Files:**
- Create: `Resources/Info.plist`
- Create: `scripts/build-app.sh`
- Create: `README.md`

1. Build a release executable with Swift Package Manager.
2. Assemble `dist/Markv.app` with its executable and property list.
3. Verify the bundle with `plutil`, launch it, and smoke-test file open/edit/save.
4. Run the full test suite once more before delivery.
