# MarkV

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

MarkV is a focused, native Markdown reader and WYSIWYG editor for macOS. It combines a quiet writing surface with folder browsing, full-text search, recent files, document outlines, live Markdown formatting, and compact PDF export.

## Highlights

- Native macOS application built with SwiftUI and WebKit
- Typora-inspired single-canvas WYSIWYG Markdown editing
- Folder library with opening-content previews and full-text search
- Recent-file navigation and drag-and-drop opening from Finder
- Transparent, resizable document outline with heading navigation
- Automatic Markdown shortcuts for headings, quotes, lists, tasks, and fenced code
- Formatting tools for emphasis, links, images, tables, code, rules, and task lists
- Khaki and white reading themes
- English and Simplified Chinese interface languages
- Focus mode and typewriter mode
- Word, character, line, and reading-time statistics
- Vector-based, paginated A4 PDF export
- Local-first operation with no analytics and no document uploads

## Download

Download the latest Apple Silicon DMG from the [GitHub Releases page](../../releases/latest).

The downloadable build is ad-hoc signed but not Apple-notarized. On first launch:

1. Open the DMG and drag **Markv.app** to **Applications**.
2. In Finder, Control-click or right-click **Markv.app** and choose **Open**.
3. Confirm **Open** in the macOS security dialog.

The current release requires macOS 14 or later. The prebuilt DMG targets Apple Silicon (`arm64`).

## Using MarkV

Open a Markdown folder from the sidebar or use **File > Open File** for a standalone document. The sidebar can search both file names and complete Markdown content. Double-click the document name in the title area to rename the file while preserving its Markdown extension.

Type Markdown naturally in the editor. Common block prefixes convert automatically after typing a space or pressing Return:

- `# ` through `###### ` for headings
- `> ` for blockquotes
- `- ` for bullet lists
- `1. ` for numbered lists
- `[ ] ` or `[x] ` inside a list for tasks
- Triple backticks or tildes for fenced code blocks

### Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New document from template | `Command-N` |
| Open file | `Command-O` |
| Open folder | `Shift-Command-O` |
| Save | `Command-S` |
| Export PDF | `Shift-Command-E` |
| Bold | `Command-B` |
| Italic | `Command-I` |
| Inline code | `Command-Backtick` |
| Focus mode | `Option-Command-8` |
| Typewriter mode | `Option-Command-9` |

## Build from source

### Requirements

- macOS 14 or later
- Xcode 16 or later with the Swift 6 toolchain

Clone the repository and build the application bundle:

```bash
git clone https://github.com/kennyz/MarkV.git
cd MarkV
./scripts/build-app.sh
open dist/Markv.app
```

The build script creates `dist/Markv.app`, generates the application icon, and applies an ad-hoc local signature.

Run MarkV directly with Swift Package Manager:

```bash
swift run --disable-sandbox Markv
```

Run the test suite:

```bash
swift test --disable-sandbox
```

## Project structure

```text
Sources/Markv/       SwiftUI application, editor bridge, rendering, and models
Tests/MarkvTests/    Unit and regression tests
Resources/           Application bundle metadata
scripts/             App bundle and icon build scripts
docs/plans/          Product and implementation design notes
```

MarkV has no third-party runtime dependencies. Markdown parsing, WYSIWYG synchronization, file search, and PDF pagination are implemented in the project using Apple platform frameworks.

## Privacy

MarkV reads and writes only the files you explicitly open. Search indexing stays in memory on your Mac. The application does not send document content, usage data, or analytics to any server.

## Contributing

Issues and pull requests are welcome. Please run the full test suite before submitting a change and keep new behavior covered by focused regression tests.

## License

MarkV is available under the [MIT License](LICENSE).
