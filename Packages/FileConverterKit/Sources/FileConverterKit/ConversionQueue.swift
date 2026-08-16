import Foundation

/// One file's conversion request plus its live status. Value type so the UI
/// can freely copy/display snapshots (`ConversionQueue.snapshot()`).
public struct ConversionJobStatus: Identifiable, Sendable {
    public let id: UUID
    public let inputURL: URL
    public let preset: ConversionPreset
    public var state: ConversionState = .ready
    public var progress: Double = 0
    public var outputURLs: [URL] = []
    public var errorDescription: String?

    public init(id: UUID = UUID(), inputURL: URL, preset: ConversionPreset) {
        self.id = id
        self.inputURL = inputURL
        self.preset = preset
    }
}

/// Replaces the Windows app's manual 50ms-polling thread-pool scheduler
/// (Services/ConversionService.cs:65-157) with a Swift `actor` + bounded
/// `TaskGroup`. Default concurrency matches the Windows default
/// (`ProcessorCount/2`, Settings.cs `MaximumNumberOfSimultaneousConversions`).
public actor ConversionQueue {
    private var jobs: [UUID: ConversionJobStatus] = [:]
    private var order: [UUID] = []
    private var runners: [UUID: ProcessRunner] = [:]
    public let maxConcurrency: Int

    public init(maxConcurrency: Int = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)) {
        self.maxConcurrency = maxConcurrency
    }

    @discardableResult
    public func enqueue(inputURL: URL, preset: ConversionPreset) -> UUID {
        let status = ConversionJobStatus(inputURL: inputURL, preset: preset)
        jobs[status.id] = status
        order.append(status.id)
        return status.id
    }

    public func snapshot() -> [ConversionJobStatus] {
        order.compactMap { jobs[$0] }
    }

    public func status(for id: UUID) -> ConversionJobStatus? {
        jobs[id]
    }

    /// Runs every `.ready` job to completion, `maxConcurrency` at a time.
    /// Mirrors the Windows app's prepare -> convert -> finalize sequence per
    /// job (ConversionJob.cs `PrepareConversion`/`StartConversion`).
    public func runAll() async {
        await withTaskGroup(of: Void.self) { group in
            var iterator = order.makeIterator()
            var active = 0

            func startNext() {
                while active < maxConcurrency, let id = iterator.next() {
                    guard jobs[id]?.state == .ready else { continue }
                    active += 1
                    group.addTask { [weak self] in
                        await self?.run(id: id)
                    }
                }
            }

            startNext()
            while await group.next() != nil {
                active -= 1
                startNext()
            }
        }
    }

    public func cancel(id: UUID) async {
        await runners[id]?.cancel()
    }

    private func run(id: UUID) async {
        guard var status = jobs[id] else { return }
        status.state = .inProgress
        jobs[id] = status

        let outputURL = ConversionOutputPlanner.outputURL(for: status.inputURL, preset: status.preset)

        do {
            let (effectiveInput, cleanupTempInput) = try ConversionOutputPlanner.resolveCollision(
                inputURL: status.inputURL, outputURL: outputURL
            )

            let outputs = try await ConversionJobFactory.run(
                preset: status.preset, inputURL: effectiveInput, outputURL: outputURL
            ) { [weak self] fraction in
                Task { await self?.updateProgress(id: id, fraction: fraction) }
            }

            for url in outputs where !FileManager.default.fileExists(atPath: url.path) {
                throw ConversionJobError.outputFileMissing(url)
            }

            ConversionOutputPlanner.copyTimestamps(from: status.inputURL, to: outputs)
            try ConversionOutputPlanner.applyPostConversionAction(status.preset.inputPostConversionAction, to: effectiveInput)
            cleanupTempInput?()

            status.outputURLs = outputs
            status.state = .done
            status.progress = 1
        } catch {
            ConversionOutputPlanner.cleanUpPartialOutputs(status.outputURLs)
            status.state = .failed
            status.errorDescription = error.localizedDescription
        }

        jobs[id] = status
        runners[id] = nil
    }

    private func updateProgress(id: UUID, fraction: Double) {
        guard var status = jobs[id] else { return }
        status.progress = fraction
        jobs[id] = status
    }
}
