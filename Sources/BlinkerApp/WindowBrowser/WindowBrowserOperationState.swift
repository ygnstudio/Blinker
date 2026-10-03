import BlinkerCore
import Foundation

/// Only one window action can be submitted per presentation at a time.
struct WindowBrowserOperationState {
    struct Request: Equatable {
        let id = UUID()
        let sessionID: UUID
        let windowID: UUID
        let action: ButtonAction
    }

    private(set) var current: Request?

    mutating func begin(_ action: ButtonAction, windowID: UUID, sessionID: UUID) -> Request? {
        guard current == nil else { return nil }
        let request = Request(sessionID: sessionID, windowID: windowID, action: action)
        current = request
        return request
    }

    /// A dismissed operation may still finish in AX; it cannot clear a newer operation's feedback.
    mutating func finish(_ request: Request) -> Bool {
        guard current == request else { return false }
        current = nil
        return true
    }

    mutating func reset() {
        current = nil
    }
}
