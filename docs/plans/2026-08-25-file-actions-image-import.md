# File Actions and Image Import Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add safe file-list actions and a unified local image-import pipeline supporting toolbar upload, Finder drop, and clipboard paste.

**Architecture:** `AppModel` owns all disk mutations: trashing files, copying paths, choosing context-menu PDF targets, creating `IMG`, resolving image-name collisions, and producing relative Markdown paths. `MarkdownWebView` handles editor selection and browser clipboard/drop payloads, then forwards image bytes to the model and inserts the saved relative URL through an editor command.

Local image display uses a restricted `markv-image://` WebKit scheme rooted at the current Markdown directory. The DOM keeps the portable Markdown path in `data-markv-src`, while the display URL is served by the scheme handler. Spaces and legacy HTML space entities are normalized to `%20` before rendering or serialization.

**Tech Stack:** Swift 6, SwiftUI, AppKit, WebKit JavaScript bridge, UniformTypeIdentifiers, Swift Testing.

---

### Task 1: File context actions

**Files:**
- Modify: `Sources/Markv/AppModel.swift`
- Modify: `Sources/Markv/ContentView.swift`
- Modify: `Sources/Markv/Localization.swift`
- Test: `Tests/MarkvTests/AppModelTests.swift`

**Steps:**
1. Add clipboard path copy and verified Trash operations to the model.
2. Confirm deletion with a localized alert and clear current/recent state only after Trash succeeds.
3. Add Open, Export as PDF, Copy File Path, and Move to Trash to folder and recent-file context menus.
4. Ensure context PDF export loads the target document before issuing the export command.
5. Test current-file deletion state and path clipboard output.

### Task 2: Local image asset store

**Files:**
- Modify: `Sources/Markv/AppModel.swift`
- Modify: `Sources/Markv/MarkdownWebView.swift`
- Test: `Tests/MarkvTests/AppModelTests.swift`

**Steps:**
1. Add `insertImage(relativePath)` as an editor action.
2. Create `IMG` beside the current Markdown file when the first image is imported.
3. Copy selected image files into `IMG`, append numeric suffixes on collisions, and insert URL-encoded relative paths.
4. Support image bytes from clipboard with a safe MIME-derived extension and generated name.
5. Test folder creation, copied bytes, collision handling, and emitted editor commands.

### Task 3: Toolbar, drag, and paste UX

**Files:**
- Modify: `Sources/Markv/ContentView.swift`
- Modify: `Sources/Markv/MarkvApp.swift`
- Modify: `Sources/Markv/MarkdownWebView.swift`
- Modify: `Sources/Markv/Localization.swift`
- Test: `Tests/MarkvTests/LocalizationTests.swift`

**Steps:**
1. Replace the image toolbar button with a menu for URL insertion and local upload.
2. Add equivalent Format menu commands.
3. Route dropped image URLs through the local asset store while keeping Markdown-file drop behavior.
4. Capture pasted or dropped browser image files as bounded base64 payloads and send them through a dedicated script handler.
5. Preserve the editor caret and insert the saved relative image URL after native persistence completes.

### Task 4: Verification and packaging

**Files:**
- Modify: `README.md`
- Modify: `Resources/Info.plist`

**Steps:**
1. Run focused file and image tests, then the full suite.
2. Build and sign `dist/Markv.app`.
3. Verify Info.plist, signature, and version.
