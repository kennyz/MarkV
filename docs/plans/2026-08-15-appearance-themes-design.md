# Appearance Themes Design

Markv keeps its quiet editorial identity while moving to a lighter visual baseline. The default Khaki theme becomes a pale warm-paper treatment rather than the previous beige canvas. A White theme offers a cleaner neutral page with a soft gray sidebar and editor surface. Both retain graphite type and the restrained vermilion accent so controls and document structure remain recognizable.

A gear button in the sidebar header opens a compact Appearance popover. Two large preview cards show the actual background relationship of each theme; clicking a card applies it immediately and displays a checkmark. The choice is persisted in `UserDefaults` and restored on future launches.

The selected palette drives the entire native shell, including the sidebar gradient, selected rows, editor, empty state, drag overlay, header, and footer. The same theme value is sent to the WebKit preview without reloading the page, where CSS variables update the document canvas, dividers, inline code, tables, and quotation colors.
