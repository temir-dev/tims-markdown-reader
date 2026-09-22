import Darwin
import Foundation
import Testing
@testable import ReaderApp

@Suite(.serialized) @MainActor
struct FileWatcherTests {
    @Test func observesPermissionChangesWithoutContentChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("permissions.md")
        try Data("# Unchanged".utf8).write(to: file)
        var notifications = 0
        let watcher = try #require(DocumentFileWatcher(documentURL: file) { notifications += 1 })
        defer { watcher.cancel() }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        try await waitForChange { notifications == 1 }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try await waitForChange { notifications == 2 }
    }

    @Test func busyDirectoryCannotPostponeDocumentRefreshIndefinitely() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("watched.md")
        try Data("# Before".utf8).write(to: file)
        var notifications = 0
        let watcher = try #require(DocumentFileWatcher(documentURL: file) { notifications += 1 })
        defer { watcher.cancel() }
        try Data("# After".utf8).write(to: file, options: .atomic)
        for index in 0..<30 {
            try Data("noise".utf8).write(to: directory.appendingPathComponent("unrelated-\(index)"))
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(notifications > 0, "A busy agent-output directory must not starve the document watcher")
    }

    @Test func detectsInPlaceAndAtomicSavesButIgnoresUnrelatedFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("note.md")
        try Data("# First".utf8).write(to: file)
        var changes = 0
        let watcher = try #require(DocumentFileWatcher(documentURL: file) { changes += 1 })
        defer { watcher.cancel() }

        // No directory entry changes: the file itself must be watched.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\nEdited in place".utf8))
        try handle.close()
        try await waitForChange { changes >= 1 }

        try Data("# Atomic replacement".utf8).write(to: file, options: .atomic)
        try await waitForChange { changes >= 2 }
        // The file watch must have moved to the new inode.
        let replacement = try FileHandle(forWritingTo: file)
        try replacement.seekToEnd()
        try replacement.write(contentsOf: Data("\nAnother edit".utf8))
        try replacement.close()
        try await waitForChange { changes >= 3 }

        let before = changes
        try Data("unrelated".utf8).write(to: directory.appendingPathComponent("other.md"))
        try await Task.sleep(for: .milliseconds(400))
        #expect(changes == before)
        watcher.cancel()
        try Data("# After cancellation".utf8).write(to: file, options: .atomic)
        try await Task.sleep(for: .milliseconds(400))
        #expect(changes == before)
    }

    @Test func fallsBackToWatchingOnlyTheFileWhenTheFolderCannotBeOpened() async throws {
        // Simulates a privacy-protected folder: the document is readable, its folder is not.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("desktop.md")
        try Data("# First".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o100], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        #expect(Darwin.open(directory.path, O_EVTONLY) < 0, "The folder itself must be unwatchable for this test")

        var changes = 0
        let watcher = try #require(DocumentFileWatcher(documentURL: file) { changes += 1 })
        defer { watcher.cancel() }
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\nEdited in place".utf8))
        try handle.close()
        try await waitForChange { changes >= 1 }
    }

    private func waitForChange(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(condition(), "File modification was not observed within 2.5 seconds")
    }
}
