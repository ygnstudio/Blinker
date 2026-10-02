import AppKit

/// The local event monitor returns this router's result unchanged: nil consumes a handled key.
public enum WindowBrowserKeyRouting {
    public struct Context {
        let isOpen: Bool
        let isKeyWindow: Bool
        let rowStep: Int

        public init(isOpen: Bool, isKeyWindow: Bool, rowStep: Int) {
            self.isOpen = isOpen
            self.isKeyWindow = isKeyWindow
            self.rowStep = rowStep
        }
    }

    public enum Action: Equatable {
        case move(Int)
        case commit
        case dismiss
        case releaseOption
        case perform(ButtonAction)
    }

    public static func route(_ event: NSEvent, context: Context?,
                             perform: (Action) -> Void) -> NSEvent? {
        guard let context else { return event }
        guard context.isOpen else { return event }
        if event.type == .flagsChanged {
            if !event.modifierFlags.contains(.option) {
                perform(.releaseOption)
            }
            return event
        }
        guard event.type == .keyDown, context.isKeyWindow else { return event }
        guard let action = keyAction(event, rowStep: context.rowStep) else { return event }
        perform(action)
        return nil
    }

    private static func keyAction(_ event: NSEvent, rowStep: Int) -> Action? {
        let directions: [UInt16: Int] = [123: -1, 124: 1, 125: rowStep, 126: -rowStep]
        if let delta = directions[event.keyCode] {
            return .move(delta)
        }
        switch event.keyCode {
        case 53: return .dismiss
        case 36, 76: return .commit
        case 48: return .move(event.modifierFlags.contains(.shift) ? -1 : 1)
        case 13 where event.modifierFlags.contains(.command): return .perform(.closeWindow)
        case 46 where event.modifierFlags.contains(.command): return .perform(.minimize)
        default: return nil
        }
    }
}
