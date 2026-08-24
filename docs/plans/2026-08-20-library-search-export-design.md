# Library Search and PDF Export Design

## Scope

Markv widens the writing canvas while keeping the editor centered and readable. The maximum editor width increases from 780 to 920 points; responsive padding still protects narrow windows.

The current-folder sidebar builds a local index when a directory is opened or refreshed. Each Markdown file stores its decoded text and a short plain-text preview derived from the first meaningful body lines. The search field filters by file name and full document content, is case- and diacritic-insensitive, and treats whitespace-separated terms as an AND query. Search stays local to the selected directory and never sends document content over the network. Empty directories and empty result sets use different messages.

File rows show the document name followed by a two-line muted preview. Recent files reuse cached previews so ordinary view refreshes do not repeatedly read files from disk.

The macOS File menu uses standard document commands: Command-O opens one Markdown file, Shift-Command-O opens a folder, and Shift-Command-E exports the active document. Export presents an `NSSavePanel`, then asynchronously captures a finite vector PDF from the live `WKWebView`. A Core Graphics paginator slices that source into standard A4 pages with fixed margins while retaining vector text and graphics. This avoids WebKit's `NSPrintOperation` pagination loop, which could generate millions of PDF objects and extremely large incomplete files. Export errors return to the app model and appear through the existing alert path.

Regression coverage verifies preview cleanup, file-name and full-content matching, multiple search terms, export destination normalization, existing editing flows, customized scroll indicators, and compact A4 pagination of a 20,000-point vector document.
