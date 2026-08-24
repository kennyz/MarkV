# Markv WYSIWYG Editor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Markv's three viewing modes with a single live-rendered Markdown authoring canvas and add a Markdown Starter template.

**Architecture:** SwiftUI owns files, outline, toolbar, settings, and status. A local WebKit content-editable surface renders safe Markdown HTML and serializes semantic edits back to Markdown through a script message bridge.

**Tech Stack:** Swift 6, SwiftUI, AppKit, WebKit, JavaScript, Swift Testing

---

### Task 1: Document intelligence and template

**Files:**
- Create: `Sources/Markv/MarkdownTemplate.swift`
- Modify: `Sources/Markv/AppModel.swift`
- Test: `Tests/MarkvTests/AppModelTests.swift`

1. Add heading extraction with stable slugs and fenced-code exclusion.
2. Add word, character, and reading-time statistics.
3. Add the built-in Markdown Starter content and save-panel creation flow.
4. Test outline, statistics, and template syntax.

### Task 2: Bidirectional editor bridge

**Files:**
- Replace: `Sources/Markv/MarkdownWebView.swift`
- Modify: `Sources/Markv/MarkdownRenderer.swift`
- Test: `Tests/MarkvTests/MarkdownRendererTests.swift`

1. Add heading IDs, task lists, and images to safe rendering.
2. Make the WebKit document content-editable.
3. Serialize edited semantic HTML to Markdown and debounce model updates.
4. Add formatting, outline-jump, focus, and typewriter commands.
5. Verify native-origin updates do not overwrite the active caret.

### Task 3: Single-canvas interface

**Files:**
- Modify: `Sources/Markv/ContentView.swift`
- Modify: `Sources/Markv/MarkvApp.swift`

1. Remove Preview, Source, and Split controls and commands.
2. Add a compact semantic formatting toolbar.
3. Add Files/Outline sidebar switching and heading navigation.
4. Add Focus and Typewriter settings and status indicators.
5. Add New from Markdown Starter to the sidebar and File menu.

### Task 4: Verification and packaging

**Files:**
- Modify: `README.md`

1. Run the complete test suite.
2. Build and ad-hoc sign `dist/Markv.app`.
3. Open a copy of a Markdown fixture, edit rich content, save, and confirm disk Markdown.
4. Visually verify both appearance themes and the single-canvas layout.
