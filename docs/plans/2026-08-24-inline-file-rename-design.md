# Inline File Rename Design

The document title remains a quiet label during ordinary writing. A double-click replaces the title with a focused inline text field containing the file's base name. The Markdown extension is preserved automatically and remains visible in the secondary full-file-name line. Return or clicking outside commits the rename; Escape cancels it.

Renaming moves the file on disk immediately without changing the document contents or dirty state. The active file URL, current-folder index, preview cache, and recent-file URLs are updated together. Empty names, path separators, control characters, and collisions with an existing file are rejected through Markv's existing alert path. Case-only renames use a temporary sibling path so they work reliably on case-insensitive file systems.

The outline type scale increases to 13 points for level-one headings and 12 points for all other levels. Compact row padding and indentation remain unchanged, preserving the dense navigation layout while improving legibility.
