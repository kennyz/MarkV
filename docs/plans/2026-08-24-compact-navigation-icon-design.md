# Compact Navigation and Icon Design

Markv's library switcher uses two icon-only controls: a folder for the current directory and a clock for recent files. The selected state is expressed with a quiet paper-colored rounded rectangle; labels remain available to VoiceOver and as hover help.

The transparent document outline no longer displays a visible “Outline” heading. Its default width is 220 points and can be dragged between 160 and 360 points, with the selected width persisted across launches. The outer inset stays at 8 points. Outline text uses regular weight with more vertical breathing room. The count and close control remain available without creating a separate visual header. The editor's reserved trailing inset derives from the live outline width, so the writing surface remains centered when the outline opens, closes, or resizes.

The library sidebar places New Document, Open Document, and Open Folder above the search field. Folder and Recent navigation move to the bottom-left beside the persistent Settings entry, keeping document actions close to the library content while leaving navigation stable at the bottom.

The application icon replaces the font-based `M` and arrow with a geometric two-ribbon symbol. A warm cream left fold and vermilion right fold meet at a low center joint, forming an asymmetric M on a charcoal rounded square. The mark is drawn with native paths at every iconset resolution, avoiding font rendering differences and retaining a recognizable silhouette at 16–32 pixels. The same two-part M is used in Markv's empty state for visual consistency.
