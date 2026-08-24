# External Markdown Drop Design

Markv accepts file URLs dropped from Finder or another macOS application anywhere over its main window. While a compatible item is hovering, the window shows a restrained vermilion dashed border and a “Drop to open” label so the target is visible without obscuring the document.

The SwiftUI drop destination forwards URLs to one model method shared with macOS external-open events. The model chooses the first existing Markdown file, switches the sidebar to that file's parent directory, opens it, and adds it to Recent. Existing unsaved-change confirmation remains authoritative. Unsupported files and folders are rejected with the existing native alert mechanism.

This keeps drag-and-drop behavior consistent with sidebar and Recent navigation and avoids a separate document-loading path. Tests cover mixed external drops and rejection of unsupported items.
