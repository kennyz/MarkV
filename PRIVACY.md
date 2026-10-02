# MarkV Privacy Policy

Effective date: October 2, 2026

This policy applies to the MarkV macOS app, including MarkV - Markdown Editor on the Mac App Store. MarkV is a local-first Markdown editor maintained by the MarkV project.

## Local documents and settings

Core editing does not require an account. Documents and imported local images are stored in locations you choose on your Mac. Folder browsing, document search, and PDF export are performed locally. MarkV does not operate a document storage or synchronization server. Files in a folder you synchronize with another service remain subject to that service's policies.

Preferences, recent-file references, and access bookmarks are stored locally. Search indexes stay in memory. Optional AI API keys are stored in macOS Keychain rather than in Markdown files or ordinary preferences.

## Optional AI editing

AI editing is disabled by default. You can enable it and configure an OpenAI-compatible service, endpoint, model, and API key. When you invoke an AI action, MarkV sends the selected text and editing instruction, or the prompt you entered, to that configured endpoint. Requests also include the model name and, when supplied, your API key for authentication. MarkV does not automatically upload your folder or other documents as context.

The AI provider receives the request directly; the MarkV project does not proxy it through a project-operated server. The provider may receive network information such as your IP address and may retain or use requests according to its own privacy policy and your account settings. A configured localhost endpoint can process requests on your Mac. MarkV cannot control a provider's retention, training, or deletion practices. Review your chosen provider's policy before sending confidential or personal information.

You can stop future AI requests by disabling AI in Settings. You can remove or replace the saved API key there. Deletion of information already held by a provider must be requested from that provider.

## Other network connections

Version checks contact GitHub to retrieve the latest public release information. These requests do not include your documents, search queries, or AI API key. GitHub can receive ordinary connection information, such as your IP address and the update checker's user-agent.

Documents containing remote image URLs can cause WebKit to request those images from their hosts. Those hosts can receive the image URL and ordinary network information. Opening an external link uses your browser or the relevant system application and is governed by that destination's policies. Use local images when you do not want remote image requests.

## Analytics, advertising, and tracking

MarkV contains no advertising or analytics SDK and does not use data for cross-app tracking. The MarkV project does not sell document content or maintain a server-side profile of your editing activity. Third-party services you choose to use have their own practices, as described above.

## Support and your choices

Support is available through [GitHub Issues](https://github.com/kennyz/MarkV/issues). Information you voluntarily post there is visible according to GitHub's settings and policies. Do not post API keys, private documents, or other sensitive information in a public issue. The project uses information you submit to respond to support requests and investigate reported problems.

You control your local documents and can delete them using macOS. Removing the app does not necessarily remove documents, preferences, Keychain entries, or copies held by backup or synchronization services. Requests to remove information in third-party services should be directed to those services.

## Changes and contact

This policy may be updated when MarkV's behavior changes. The current version and its effective date will be published in this repository. For privacy questions, contact the maintainer through [GitHub Issues](https://github.com/kennyz/MarkV/issues) without including sensitive information.
