# Markv Design

Markv is a small native macOS Markdown workspace for people who want the speed of a reader without losing access to the source. The first release focuses on one loop: choose a folder, move quickly among its Markdown files, read the rendered result, and edit or save the source without leaving the app.

The application uses SwiftUI for the shell and AppKit for native file panels and save confirmation. A three-column-capable `NavigationSplitView` becomes a compact two-pane window: the left sidebar contains the chosen directory and recent files, while the detail pane contains the current document. The detail pane supports Preview, Source, and Split modes. Preview is rendered inside `WKWebView` from escaped local content, giving Markv typographic control without granting Markdown documents script execution.

The visual direction is “quiet editorial tool”: warm paper, dark graphite, restrained vermilion accents, Avenir Next for interface text, New York for rendered prose, and SF Mono for source. It should feel closer to a well-made notebook than an IDE. Native focus, selection, keyboard shortcuts, and window behavior remain intact.

Document state lives in a single main-actor model. It scans only the selected directory's immediate Markdown files, tracks the selected URL and dirty state, persists up to twelve recent paths in `UserDefaults`, and confirms unsaved changes before switching. Errors are shown with native alerts. The Markdown renderer is a small deterministic Swift component covered by unit tests; the initial syntax set includes headings, paragraphs, emphasis, links, lists, blockquotes, fenced code, horizontal rules, and simple tables.

Success means the packaged app launches on macOS, opens a directory, lists and switches `.md`/`.markdown` files, restores recent-file shortcuts, edits source with a live preview, warns before discarding edits, and saves with Command-S.
