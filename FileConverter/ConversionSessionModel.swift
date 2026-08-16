import Foundation
import FileConverterKit

/// Drives one batch of conversions and republishes `ConversionQueue`'s actor
/// state to the UI via polling — the queue itself has no push notification
/// mechanism (see ConversionQueue.swift), so this is the equivalent of the
/// Windows app's `MainViewModel` subscribing to each `ConversionJob`'s
/// `PropertyChanged` (Services/ConversionService.cs), simplified to a
/// short poll loop since SwiftUI redraws cheaply on `@Published` changes.
@MainActor
final class ConversionSessionModel: ObservableObject {
    @Published private(set) var jobs: [ConversionJobStatus] = []
    @Published private(set) var isRunning = false
    @Published private(set) var finishedAt: Date?

    private let queue: ConversionQueue
    private let inputURLs: [URL]
    private let preset: ConversionPreset
    private var pollTask: Task<Void, Never>?

    init(inputURLs: [URL], preset: ConversionPreset, maxConcurrency: Int) {
        self.inputURLs = inputURLs
        self.preset = preset
        self.queue = ConversionQueue(maxConcurrency: max(1, maxConcurrency))
    }

    func start() {
        isRunning = true
        pollTask = Task {
            // Enqueue must complete before runAll() reads the queue's job
            // order, and before the poll loop starts checking "all done" —
            // otherwise runAll() can race ahead and find nothing to run.
            for url in inputURLs {
                await queue.enqueue(inputURL: url, preset: preset)
            }
            jobs = await queue.snapshot()

            async let runCompletion: Void = queue.runAll()

            while !Task.isCancelled {
                jobs = await queue.snapshot()
                if !jobs.isEmpty && jobs.allSatisfy({ $0.state == .done || $0.state == .failed }) {
                    break
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }

            _ = await runCompletion
            jobs = await queue.snapshot()
            isRunning = false
            finishedAt = Date()
            NotificationCenter.default.post(name: sessionFinishedNotification, object: nil)
        }
    }

    func cancelAll() {
        for job in jobs where job.state == .inProgress {
            Task { await queue.cancel(id: job.id) }
        }
    }

    deinit {
        pollTask?.cancel()
    }
}
