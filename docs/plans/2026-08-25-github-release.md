# GitHub Public Release Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Publish MarkV as a public MIT-licensed GitHub repository and attach a verified macOS arm64 DMG to release `v0.4.2`.

**Architecture:** Keep source, tests, scripts, and design notes in Git while excluding local documents, Swift build caches, packaged apps, DMGs, and temporary files. Build the existing ad-hoc-signed app, package it in a compressed DMG with an Applications shortcut, then publish the repository and release through the authenticated GitHub CLI.

**Tech Stack:** Swift 6, SwiftUI, WebKit, Swift Package Manager, Git, GitHub CLI, `hdiutil`, macOS code signing.

---

### Task 1: Open-source metadata

**Files:**
- Modify: `.gitignore`
- Replace: `README.md`
- Create: `LICENSE`

**Steps:**
1. Exclude `.build`, `dist`, `release`, `tmp`, DMGs, `.DS_Store`, and the local `new.md` document.
2. Write an English README covering features, installation, Gatekeeper guidance, usage, shortcuts, build/test commands, architecture, privacy, and MIT licensing.
3. Add the MIT License with `MarkV contributors` as the copyright holder.
4. Verify no ignored local document or binary appears in `git status`.

### Task 2: Source and security verification

**Files:**
- Inspect: `Sources/Markv/**`, `scripts/**`, `Resources/Info.plist`

**Steps:**
1. Search tracked candidates for tokens, passwords, private keys, absolute personal paths, and generated binaries.
2. Run `swift test --disable-sandbox` and require all tests to pass.
3. Run `scripts/build-app.sh`, validate `Info.plist`, and verify the app signature.

### Task 3: DMG artifact

**Files:**
- Create locally: `release/MarkV-0.4.2-macOS-arm64.dmg`

**Steps:**
1. Create a clean staging directory containing `Markv.app` and an `/Applications` symlink.
2. Build a compressed UDZO DMG named for version and architecture.
3. Mount the DMG read-only, verify the app bundle and signature, then detach it.
4. Record SHA-256 and file size.

### Task 4: Git and GitHub publication

**Steps:**
1. Confirm GitHub CLI authentication and resolve the authenticated account.
2. Confirm the `MarkV` repository name is available; stop rather than overwrite an unrelated repository.
3. Initialize an independent repository in the MarkV project, use branch `main`, stage reviewed source files, and create the initial commit.
4. Create a public GitHub repository named `MarkV` with the project description and push `main`.
5. Create annotated tag/release `v0.4.2`, publish English release notes, and upload the arm64 DMG.
6. Verify repository visibility, default branch, license detection, release URL, and asset size from the GitHub API.
