import SwiftUI
import FileConverterKit

@main
struct FileConverterApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .onAppear(perform: handleCommandLineLaunch)
                .onOpenURL(perform: handleIncomingURL)
                .onReceive(NotificationCenter.default.publisher(for: sessionFinishedNotification)) { _ in
                    scheduleAutoQuitIfNeeded()
                }
        }
        .windowResizability(.contentSize)
    }

    /// `--preset <name> <files...>` / `--input-files <path>` — manual/dev
    /// launches. The primary hand-off path is `handleIncomingURL`.
    private func handleCommandLineLaunch() {
        guard let request = LaunchRequest.from(commandLineArguments: CommandLine.arguments) else { return }
        appModel.handle(request: request)
    }

    /// `fileconverter://convert?preset=<name>&list=<tempPath>` — the Quick
    /// Action's hand-off (ActionRequestHandler.swift). Verified end-to-end
    /// against the real built app (see macOS/FileConverterMac/README.md):
    /// both the exact-preset-name auto-start path and the no-preset-name
    /// picker path.
    private func handleIncomingURL(_ url: URL) {
        guard let request = LaunchRequest.from(url: url) else { return }
        appModel.handle(request: request)
    }

    /// Mirrors Application.xaml.cs's auto-close-after-conversions behavior
    /// (MainViewModel `DurationBetweenEndOfConversionsAndApplicationExit`),
    /// gated by `exitApplicationWhenConversionsFinished`.
    private func scheduleAutoQuitIfNeeded() {
        guard appModel.settings.exitApplicationWhenConversionsFinished else { return }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            NSApplication.shared.terminate(nil)
        }
    }
}

let sessionFinishedNotification = Notification.Name("FileConverter.sessionFinished")
