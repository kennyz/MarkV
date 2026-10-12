import Foundation

/// Poll the path, not its inode: many editors save by atomically replacing the file.
/// This also works when the sandbox grants access to a file but not its parent folder.
@MainActor
final class DocumentFileMonitor {
    private var task: Task<Void, Never>?

    init(url: URL, onChange: @escaping @MainActor (String) -> Void) {
        task = Task {
            var signature: DiskSignature?
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(750))
                } catch {
                    return
                }
                let previous = signature
                let snapshot = await Task.detached(priority: .utility) {
                    DiskSnapshot.read(url, after: previous)
                }.value
                guard !Task.isCancelled else { return }
                if let snapshot {
                    signature = snapshot.signature
                    onChange(snapshot.text)
                }
            }
        }
    }

    func stop() { task?.cancel() }

    deinit { task?.cancel() }
}

private struct DiskSignature: Equatable, Sendable {
    let modified: Date?
    let created: Date?
    let size: UInt64
    let inode: UInt64

    static func read(_ url: URL) -> DiskSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
        return DiskSignature(
            modified: attributes[.modificationDate] as? Date,
            created: attributes[.creationDate] as? Date,
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        )
    }
}

private struct DiskSnapshot: Sendable {
    let signature: DiskSignature
    let text: String

    static func read(_ url: URL, after previous: DiskSignature?) -> DiskSnapshot? {
        guard let signature = DiskSignature.read(url), signature != previous,
              let text = try? String(contentsOf: url, encoding: .utf8),
              DiskSignature.read(url) == signature else { return nil }
        // Missing, unreadable, or mid-write files are retried without interrupting writing.
        return DiskSnapshot(signature: signature, text: text)
    }
}
