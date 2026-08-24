# Interface Localization Design

Markv supports an explicit in-app language preference with English and Simplified Chinese options. English remains the default to preserve existing behavior. The selected language is stored in `UserDefaults`, restored on launch, and changed from a segmented control in Appearance Settings.

All application-owned interface text uses a central translation table: SwiftUI labels, accessibility descriptions, hover help, status text, formatting controls, custom macOS menu commands, file panels, export panels, validation errors, and unsaved-change alerts. File names and Markdown document content are never translated.

The editor receives the language alongside theme, focus mode, and typewriter mode. WebKit updates its `data-language` attribute without reloading the document, allowing placeholder text and JavaScript prompts to change immediately without disturbing the selection or edit history. Newly inserted task and table placeholder content follows the active language.

Regression tests cover core translations, formatted strings, language persistence, Chinese file-validation errors, and the Chinese presentation strings embedded in the editor shell.
