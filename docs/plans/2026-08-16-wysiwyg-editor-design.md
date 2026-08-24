# Markv WYSIWYG Editor Design

Markv will replace its Preview, Source, and Split modes with one continuous Markdown editing surface. The design follows the interaction principles described by Typora's public documentation—live rendering, smart Markdown syntax, file navigation, outline, word count, focus mode, and typewriter mode—without copying Typora branding, proprietary assets, or source code.

The editor is a local `WKWebView` content-editable document. Swift converts disk Markdown to safe HTML. JavaScript converts edited semantic HTML back into Markdown and sends it to the existing document model, which remains the source of truth for saving. Native toolbar commands call a narrow JavaScript command bridge for headings, emphasis, links, lists, quotes, code, rules, and tables. Native-to-web updates are ignored when they originated in the editor, preserving the caret and avoiding render loops.

The sidebar gains Files and Outline panels. Outline items are derived from Markdown headings and jump to matching rendered headings. Status information includes words, characters, reading time, dirty state, Focus mode, and Typewriter mode. A built-in “Markdown Starter” template creates a real `.md` file with representative headings, lists, tasks, tables, quotes, code, and links.

The first WYSIWYG release targets reliable GFM-style authoring for headings, paragraphs, emphasis, links, ordered/unordered/task lists, blockquotes, fenced code, horizontal rules, images, and tables. Math, diagrams, export/import, image upload, global search, and advanced table resizing are separate subsystems and are not represented as complete in this release.
