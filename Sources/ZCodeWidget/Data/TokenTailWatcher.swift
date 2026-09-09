import Foundation
import GRDB

/// Watches ~/.zcode/log/token-tail.jsonl for new entries appended by the Stop hook.
/// Also polls the DB every 5 seconds as a fallback.
final class TokenTailWatcher {
    private let tailPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zcode/log/token-tail.jsonl").path
    private var lastOffset: UInt64 = 0
    private var fd: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private let queue = DispatchQueue(label: "com.zcode.widget.tail", qos: .utility)
    private let decoder = JSONDecoder()

    /// Called on the main thread whenever a new UsageRecord is appended
    var onNewRecord: ((UsageRecord) -> Void)?

    init() {
        decoder.dateDecodingStrategy = .iso8601
        startPolling()
        startTail()
    }

    deinit {
        stopTail()
        pollTimer?.invalidate()
    }

    // MARK: - Polling (every 5s)

    private func startPolling() {
        DispatchQueue.main.async { [weak self] in
            self?.pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.pollLatest()
            }
        }
    }

    private func pollLatest() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let repo = TokenUsageRepository()
            guard let latest = try? repo.recentUsage(limit: 1).first else { return }
            DispatchQueue.main.async {
                self.onNewRecord?(latest)
            }
        }
    }

    // MARK: - FSEvents Tail (sub-second)

    private func startTail() {
        let openedFd = open(tailPath, O_EVTONLY)
        guard openedFd >= 0 else { return }

        fd = openedFd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: openedFd,
            eventMask: .write,
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.readNewLines()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 {
                close(fd)
            }
        }

        dispatchSource = source
        source.resume()

        // Read any existing content (set offset to end of file on start)
        lastOffset = fileSize(at: fd)
    }

    private func stopTail() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    private func readNewLines() {
        guard fd >= 0 else { return }
        let currentSize = fileSize(at: fd)

        guard currentSize > lastOffset else { return }

        lseek(fd, off_t(lastOffset), SEEK_SET)
        var buffer = [CChar](repeating: 0, count: 4096)
        let bytesRead = read(fd, &buffer, buffer.count)
        guard bytesRead > 0 else { return }

        let data = Data(bytes: buffer, count: bytesRead)
        guard let text = String(data: data, encoding: .utf8) else { return }

        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            if let lineData = line.data(using: .utf8),
               let record = try? decoder.decode(UsageRecord.self, from: lineData) {
                DispatchQueue.main.async { [weak self] in
                    self?.onNewRecord?(record)
                }
            }
        }

        lastOffset = currentSize
    }

    private func fileSize(at fd: Int32) -> UInt64 {
        var stat = stat()
        guard fstat(fd, &stat) == 0 else { return 0 }
        return UInt64(stat.st_size)
    }
}
