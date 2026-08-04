import Foundation
import BalconyShared
import os

/// Tails a Claude Code session's JSONL transcript and emits structured
/// ``TranscriptEvent`` batches as the file grows.
///
/// This is the reliable companion to the PTY stream: instead of scraping the
/// reconstructed terminal screen, it reads the structured log Claude Code writes
/// for every turn. On `start()` it emits the full history once (`reset == true`),
/// then watches the file and emits appended turns as they land (`reset == false`).
/// If the file shrinks (compaction) or is replaced (`/clear`, atomic rewrite) it
/// re-snapshots with `reset == true`.
///
/// All mutable state is confined to `queue`; the FS-event handler and the public
/// API both hop onto it, so no locking is needed.
final class TranscriptTailer: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.balcony.mac", category: "TranscriptTailer")

    /// The transcript file currently being tailed. Mutable: `/clear` (and
    /// `/resume`) start a new session file, which the directory watch detects
    /// and switches to.
    private var path: String
    private let sessionId: String
    /// The session's start time. In fallback mode the directory watch only
    /// adopts a transcript *written* at/after this, so a dormant session's file
    /// is never shown (e.g. when this session is brand-new with no file yet).
    /// A resumed conversation's file can be far older than the session, so this
    /// bounds by modification, not creation — see `latestJSONL`.
    private let activeSince: Date?
    /// True when `path` is the session's exact transcript (resolved from a hook,
    /// e.g. SessionStart). In that case the directory watch only waits for that
    /// exact file to appear and never switches to a sibling session's file —
    /// path changes (/clear, resume) arrive as fresh hooks that restart the tailer.
    /// When false (no hook yet) it falls back to the latest file written since start.
    private let authoritative: Bool
    private let onEvents: @Sendable (TranscriptEventsPayload) -> Void

    private let queue = DispatchQueue(label: "com.balcony.mac.transcript-tailer", qos: .utility)

    /// Byte offset up to which the file has been consumed.
    private var offset: UInt64 = 0
    /// A trailing partial line (no newline yet) carried to the next read.
    private var leftover = Data()
    /// Event UUIDs already emitted, so a re-snapshot or overlapping read never
    /// double-delivers a turn.
    private var seenIDs = Set<String>()

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    /// Watches the parent directory so a newly-created active transcript (e.g.
    /// `/clear`) is picked up — the per-file watch only sees the file we hold.
    private var dirSource: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1

    /// - Parameters:
    ///   - path: absolute path to the session JSONL (from `HookEvent.transcriptPath`).
    ///   - sessionId: the PTY session id this transcript is shown under on iOS.
    ///   - activeSince: the session's start time; bounds fallback switches.
    ///   - authoritative: whether `path` is the exact, hook-resolved transcript.
    ///   - onEvents: invoked on the tailer's queue with each batch to send.
    init(path: String, sessionId: String, activeSince: Date? = nil, authoritative: Bool = false, onEvents: @escaping @Sendable (TranscriptEventsPayload) -> Void) {
        self.path = path
        self.sessionId = sessionId
        self.activeSince = activeSince
        self.authoritative = authoritative
        self.onEvents = onEvents
    }

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: self.path) {
                self.snapshot()
                self.beginWatching()
            } else {
                // Fresh session — the file isn't written yet. Show empty and let
                // the directory watch pick it up the moment it's created.
                self.emit([], reset: true)
            }
            self.beginWatchingDirectory()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.source?.cancel()
            self?.source = nil
            self?.dirSource?.cancel()
            self?.dirSource = nil
        }
    }

    // MARK: - Reading (queue-confined)

    /// Read the whole file, emit it as a reset batch, and reset bookkeeping.
    private func snapshot() {
        guard let data = FileManager.default.contents(atPath: path) else {
            logger.warning("Transcript not readable at \(self.path, privacy: .public)")
            return
        }
        leftover = Data()
        seenIDs.removeAll(keepingCapacity: true)

        // `offset` tracks how many bytes we've read from the file (the whole
        // snapshot). A trailing partial line — a turn still being written — is
        // carried in `leftover`; the next read appends only the *new* bytes past
        // `offset` to it, so the line is completed rather than lost or doubled.
        offset = UInt64(data.count)
        let lines = completeLines(from: data, carryingPartial: true)

        let events = parse(lines)
        seenIDs.formUnion(events.map(\.id))
        // Always emit a reset — even when empty — so iOS clears any stale list.
        emit(events, reset: true)
        logger.info("Transcript snapshot: \(events.count) events for session \(self.sessionId, privacy: .public)")
    }

    /// Read bytes appended since `offset` and emit any newly-completed turns.
    private func readAppended() {
        let size = fileSize()
        if size < offset {
            // File shrank — compaction or rewrite-in-place. Start over.
            logger.info("Transcript shrank (\(size) < \(self.offset)) — re-snapshotting")
            snapshot()
            return
        }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return }
        defer { try? handle.close() }

        guard (try? handle.seek(toOffset: offset)) != nil,
              let chunk = try? handle.readToEnd(), !chunk.isEmpty else { return }
        offset = size

        var buffer = leftover
        buffer.append(chunk)
        let lines = completeLines(from: buffer, carryingPartial: true)

        let fresh = parse(lines).filter { seenIDs.insert($0.id).inserted }
        guard !fresh.isEmpty else { return }
        emit(fresh, reset: false)
        logger.debug("Transcript appended: \(fresh.count) events for session \(self.sessionId, privacy: .public)")
    }

    // MARK: - Watching (queue-confined)

    private func beginWatching() {
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            logger.error("open(O_EVTONLY) failed for \(self.path, privacy: .public)")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.source?.data ?? []
            if flags.contains(.delete) || flags.contains(.rename) {
                // The inode we held was replaced (atomic rewrite). Re-bind to the
                // path and re-snapshot from scratch.
                self.reopen()
            } else {
                self.readAppended()
            }
        }
        src.setCancelHandler { [fd = self.fd] in
            if fd >= 0 { close(fd) }
        }
        source = src
        src.resume()
    }

    /// Tear down the current watch and re-establish it against the path, then
    /// re-snapshot (the file was replaced underneath us).
    private func reopen() {
        source?.cancel()
        source = nil
        snapshot()
        beginWatching()
    }

    /// Watch the parent directory. Directory vnode events fire when entries are
    /// added/removed — i.e. when `/clear` (or `/resume`) spins up a new session
    /// file — which the per-file watch can't see.
    private func beginWatchingDirectory() {
        let dirPath = (path as NSString).deletingLastPathComponent
        dirFD = open(dirPath, O_EVTONLY)
        guard dirFD >= 0 else {
            logger.error("open(O_EVTONLY) failed for dir \(dirPath, privacy: .public)")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: [.write],
            queue: queue
        )
        src.setEventHandler { [weak self] in self?.onDirectoryEvent() }
        src.setCancelHandler { [dirFD = self.dirFD] in if dirFD >= 0 { close(dirFD) } }
        dirSource = src
        src.resume()
    }

    /// Directory changed (a file was created/removed).
    private func onDirectoryEvent() {
        if authoritative {
            // We know the exact file. Only act when *our* file finally appears
            // (fresh session) — never switch to a sibling session's transcript.
            // Path changes (/clear, resume) arrive as new hooks that restart us.
            if source == nil, FileManager.default.fileExists(atPath: path) {
                snapshot()
                beginWatching()
            }
            return
        }

        // Fallback (no hook yet): adopt the latest transcript created after this
        // session started — covers the file first appearing and /clear creating
        // a new one, while never reaching back to a pre-existing session.
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        guard let latest = Self.latestJSONL(inDirectory: dir, activeSince: activeSince), latest != path else {
            // Our chosen file may just now have appeared — start watching it.
            if source == nil, FileManager.default.fileExists(atPath: path) {
                snapshot()
                beginWatching()
            }
            return
        }
        logger.info("Active transcript changed for session \(self.sessionId, privacy: .public) → \(latest, privacy: .public)")
        source?.cancel()
        source = nil
        path = latest
        snapshot()
        beginWatching()
    }

    /// Most-recently-modified non-agent `.jsonl` in a directory, or nil. When
    /// `activeSince` is set, only files *written* at/after it (minus a small
    /// tolerance) are considered — so an unrelated dormant session is never
    /// picked up by a session that has no transcript of its own yet.
    ///
    /// This deliberately tests modification time, not creation time. A resumed
    /// conversation (`claude --resume`, `--continue`) keeps appending to a file
    /// that can be *older than the process writing it* — one real case had a
    /// transcript created Aug 1, its Claude process started Aug 2, and the Mac
    /// app started Aug 4. Filtering on creation date excluded that session's own
    /// live transcript, so the phone showed an empty conversation until the next
    /// hook revealed the exact path and the whole history landed at once.
    /// Modification time answers the question actually being asked: is this file
    /// the one currently being written?
    static func latestJSONL(inDirectory dir: URL, activeSince: Date? = nil) -> String? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let cutoff = activeSince?.addingTimeInterval(-10)
        let latest = files
            .filter { url in
                guard url.pathExtension == "jsonl", !url.lastPathComponent.hasPrefix("agent-") else { return false }
                guard let cutoff else { return true }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return modified >= cutoff
            }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
        return latest?.path
    }

    // MARK: - Helpers (queue-confined)

    /// Split `data` on newlines into complete-line Data slices. When
    /// `carryingPartial` is true, a trailing line without a newline is stashed in
    /// `leftover`; otherwise it is treated as complete.
    private func completeLines(from data: Data, carryingPartial: Bool) -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        let newline = UInt8(ascii: "\n")
        var i = data.startIndex
        while i < data.endIndex {
            if data[i] == newline {
                if i > start { lines.append(data.subdata(in: start..<i)) }
                start = data.index(after: i)
            }
            i = data.index(after: i)
        }
        if start < data.endIndex {
            let tail = data.subdata(in: start..<data.endIndex)
            if carryingPartial { leftover = tail } else { lines.append(tail) }
        } else if carryingPartial {
            leftover = Data()
        }
        return lines
    }

    private func parse(_ lines: [Data]) -> [TranscriptEvent] {
        lines.compactMap { TranscriptParser.parseLine($0) }
    }

    private func emit(_ events: [TranscriptEvent], reset: Bool) {
        onEvents(TranscriptEventsPayload(sessionId: sessionId, events: events, reset: reset))
    }

    private func fileSize() -> UInt64 {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        return (attrs[.size] as? NSNumber)?.uint64Value ?? 0
    }
}
