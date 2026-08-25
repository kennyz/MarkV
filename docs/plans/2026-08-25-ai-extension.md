# AI Editing Extension Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an optional OpenAI-compatible AI extension for selection-based revisions and slash-triggered Markdown generation with review-before-apply UX.

**Architecture:** `AIService` validates an OpenAI-compatible base URL, creates `POST /chat/completions` requests, and decodes `choices[].message.content`. Non-secret AI preferences live in `UserDefaults`; API keys live only in macOS Keychain. `MarkdownWebView` preserves native selection/range state and emits selection/slash events, while SwiftUI presents prompt, loading, and revision cards before applying changes.

**Tech Stack:** Swift 6, SwiftUI, WebKit JavaScript bridge, URLSession, Security.framework Keychain, OpenAI-compatible Chat Completions JSON, Swift Testing.

---

### Task 1: Secure AI configuration

**Files:**
- Create: `Sources/Markv/AIService.swift`
- Create: `Sources/Markv/AIKeychainStore.swift`
- Modify: `Sources/Markv/AppModel.swift`
- Modify: `Sources/Markv/Localization.swift`
- Test: `Tests/MarkvTests/AIServiceTests.swift`

**Steps:**
1. Test base-URL normalization for `/v1`, `/chat/completions`, trailing slashes, invalid schemes, localhost HTTP, and insecure keyed HTTP.
2. Implement Codable Chat Completions request/response models with `model`, `messages`, and non-streaming text output.
3. Add an API-key header only when a key exists; never log or persist it outside Keychain.
4. Implement Keychain read/write/delete using the MarkV bundle identifier as service.
5. Persist enablement, base URL, and model in UserDefaults; expose the Keychain-backed key through `AppModel`.

### Task 2: Editor selection and slash bridge

**Files:**
- Modify: `Sources/Markv/MarkdownWebView.swift`
- Test: `Tests/MarkvTests/AIEditorBridgeTests.swift`

**Steps:**
1. Add editor commands to capture a non-collapsed selection, replace it, or insert after it.
2. Preserve the DOM Range while the user reviews an AI suggestion.
3. Detect a paragraph containing only `/` when AI is enabled, preserve its block, and send a slash event once.
4. Add a sanitized HTML insertion command that replaces the slash block with rendered AI Markdown.
5. Test that the shell includes selection, range restoration, slash detection, and safe insertion handlers.

### Task 3: AI request state and prompts

**Files:**
- Modify: `Sources/Markv/AppModel.swift`
- Test: `Tests/MarkvTests/AIServiceTests.swift`

**Steps:**
1. Define edit actions: improve, fix grammar, shorten, lengthen, and custom instruction.
2. Capture selected text before starting a request; reject empty selections.
3. Build focused developer/user messages that request only revised text or Markdown.
4. Store loading state, prompt context, last request for retry, and proposed revision in the model.
5. Support cancellation, retry, replace selection, insert after selection, and slash-content insertion.

### Task 4: Notion-like SwiftUI experience

**Files:**
- Modify: `Sources/Markv/ContentView.swift`
- Modify: `Sources/Markv/MarkvApp.swift`
- Modify: `Sources/Markv/Localization.swift`

**Steps:**
1. Add an AI section to Settings with enable toggle, Base URL, model, SecureField API key, and a privacy note.
2. Show an AI toolbar menu only when the extension is enabled.
3. Provide preset selection actions and a custom instruction action.
4. Show a compact slash/custom prompt card with Generate and Cancel.
5. Show original and proposed text in a revision card with Replace, Insert Below, Try Again, and Discard.
6. Cover empty, loading, API error, and disabled states in English and Chinese.

### Task 5: Verification and packaging

**Files:**
- Modify: `README.md`
- Modify: `Resources/Info.plist`

**Steps:**
1. Run focused endpoint, request-body, Keychain seam, editor bridge, and model-state tests.
2. Run the complete test suite.
3. Audit that API keys never enter UserDefaults, logs, errors, Markdown, or Git diffs.
4. Build and sign `dist/Markv.app`; verify Info.plist and release version.
