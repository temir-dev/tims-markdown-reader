import Darwin
import Foundation

@MainActor
final class DocumentFileWatcher {
    private struct Fingerprint: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int
        let permissions: mode_t
    }

    private let documentURL: URL
    private let callback: () -> Void
    private let queue = DispatchQueue(label: "dev.tairov.timsmarkdownreader.file-watcher", qos: .utility)
    private var directorySource: (any DispatchSourceFileSystemObject)?
    private var fileSource: (any DispatchSourceFileSystemObject)?
    private var pendingNotification: DispatchWorkItem?
    private var lastFingerprint: Fingerprint?
    private var cancelled = false

    init?(documentURL: URL, callback: @escaping () -> Void) {
        self.documentURL = documentURL
        self.callback = callback
        lastFingerprint = Self.fingerprint(for: documentURL)
        // macOS may allow reading an opened document but refuse its folder (Desktop,
        // Documents, Downloads without folder access). Watching the file alone still
        // catches in-place saves and, via rename/delete events, atomic replacements.
        directorySource = watch(documentURL.deletingLastPathComponent())
        fileSource = watch(documentURL)
        guard directorySource != nil || fileSource != nil else { return nil }
    }

    private func watch(_ url: URL) -> (any DispatchSourceFileSystemObject)? {
        let descriptor = open(url.path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            DispatchQueue.main.async { self?.scheduleNotification() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    func cancel() {
        cancelled = true
        pendingNotification?.cancel()
        pendingNotification = nil
        directorySource?.cancel()
        directorySource = nil
        fileSource?.cancel()
        fileSource = nil
    }

    private func scheduleNotification() {
        // Coalesce into a bounded interval. Restarting the timer for every
        // unrelated directory event would starve refresh in busy agent folders.
        guard !cancelled, pendingNotification == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.cancelled else { return }
            self.pendingNotification = nil
            let fingerprint = Self.fingerprint(for: self.documentURL)
            guard fingerprint != self.lastFingerprint else { return }
            if fingerprint?.device != self.lastFingerprint?.device ||
                fingerprint?.inode != self.lastFingerprint?.inode || self.fileSource == nil {
                // Atomic saves replace the inode; directory events re-arm the file watch.
                self.fileSource?.cancel()
                self.fileSource = self.watch(self.documentURL)
            }
            self.lastFingerprint = fingerprint
            self.callback()
        }
        pendingNotification = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200), execute: workItem)
    }

    private static func fingerprint(for url: URL) -> Fingerprint? {
        var information = stat()
        guard Darwin.lstat(url.path, &information) == 0 else { return nil }
        return Fingerprint(device: information.st_dev, inode: information.st_ino,
                           size: information.st_size, modifiedSeconds: information.st_mtimespec.tv_sec,
                           modifiedNanoseconds: information.st_mtimespec.tv_nsec,
                           changedSeconds: information.st_ctimespec.tv_sec,
                           changedNanoseconds: information.st_ctimespec.tv_nsec,
                           permissions: information.st_mode)
    }

    deinit {
        pendingNotification?.cancel()
        directorySource?.cancel()
        fileSource?.cancel()
    }
}
