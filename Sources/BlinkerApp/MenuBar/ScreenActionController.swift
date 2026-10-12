import Combine
import Foundation

/// Owned by the presentation so command completion survives closing the panel.
@MainActor
final class ScreenActionController: ObservableObject {
    enum Action: Sendable { case screenSaver, displaySleep }

    @Published private(set) var running: Action?
    @Published private(set) var failed: Action?
    @Published private(set) var completed: Action?
    private let perform: @Sendable (Action) async throws -> Void

    init(perform: @escaping @Sendable (Action) async throws -> Void = { action in
        switch action {
        case .screenSaver: try await SystemScreenActions.startScreenSaver()
        case .displaySleep: try SystemScreenActions.sleepDisplays()
        }
    }) {
        self.perform = perform
    }

    func run(_ action: Action) {
        guard running == nil else { return }
        running = action
        failed = nil
        completed = nil
        let perform = perform
        Task {
            let succeeded = await Task.detached(priority: .userInitiated) {
                do {
                    try await perform(action)
                    return true
                } catch {
                    return false
                }
            }.value
            failed = succeeded ? nil : action
            completed = succeeded ? action : nil
            running = nil
        }
    }
}
