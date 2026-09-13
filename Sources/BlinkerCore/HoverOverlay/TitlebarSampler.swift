import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Captures a pixel-accurate backdrop for the mask from the host window's
/// own title bar.
///
/// The native buttons sit inside the mask area, so the strip directly behind
/// the mask cannot be sampled — instead a clean strip of the *same height*
/// is taken from beside the button group (the title bar right of the buttons
/// is usually the widest) and stretched horizontally across the mask frame.
/// Title bars are near-uniform horizontally, so the stretch is visually
/// seamless.
///
/// Sampling uses `SCScreenshotManager` one-shot captures (macOS 14+); the
/// legacy `CGWindowListCreateImage` is hard-unavailable in recent SDKs.
public enum TitlebarSampler {
    /// Minimum width (pt) of a clean strip worth sampling.
    private static let minimumStripWidth: CGFloat = 12
    /// Clearance (pt) kept from the window edges and the button group so
    /// window borders and buttons never leak into the strip.
    private static let clearance: CGFloat = 4

    /// `true` when the user has already granted Screen Recording access.
    public static func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Prompts the system Screen Recording permission dialog. The grant
    /// arrives asynchronously; the overlay keeps falling back to glass
    /// until `hasScreenCapturePermission()` turns `true`.
    public static func requestScreenCapturePermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Renders the mask backdrop by sampling `windowID` beside the button
    /// group, stretched to `maskFrame`'s size. Returns `nil` when screen
    /// capture is unavailable (no permission, window gone, no clean strip) —
    /// callers fall back to the material backdrop.
    ///
    /// - Parameter scale: Backing scale factor for the output pixel size;
    ///   read `NSScreen.backingScaleFactor` on the main thread and pass it in.
    static func maskImage(
        windowID: CGWindowID,
        windowBounds: CGRect,
        maskFrame: CGRect,
        scale: CGFloat
    ) async -> NSImage? {
        guard let stripFrame = cleanStripFrame(
            windowBounds: windowBounds,
            maskFrame: maskFrame
        ) else { return nil }

        let shareable = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let scWindow = shareable?.windows.first(where: { $0.windowID == windowID }) else {
            return nil
        }

        let configuration = SCStreamConfiguration()
        // sourceRect is window-local, top-left origin — same axis as the
        // global CG/AX coordinate space, so a plain origin shift applies.
        configuration.sourceRect = CGRect(
            x: stripFrame.minX - windowBounds.minX,
            y: stripFrame.minY - windowBounds.minY,
            width: stripFrame.width,
            height: stripFrame.height
        )
        configuration.width = Int(stripFrame.width * scale)
        configuration.height = Int(stripFrame.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        guard
            let sampled = try? await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        else { return nil }

        let stretched = NSImage(size: maskFrame.size)
        stretched.lockFocusFlipped(false)
        NSGraphicsContext.current?.cgContext.interpolationQuality = .high
        NSImage(cgImage: sampled, size: maskFrame.size)
            .draw(in: CGRect(origin: .zero, size: maskFrame.size))
        stretched.unlockFocus()
        return stretched
    }

    /// The widest clean strip beside the button group at the mask's vertical
    /// range, in global top-left coordinates, or `nil` when neither side of
    /// the window offers enough room.
    private static func cleanStripFrame(
        windowBounds: CGRect,
        maskFrame: CGRect
    ) -> CGRect? {
        let leftWidth = maskFrame.minX - clearance - (windowBounds.minX + clearance)
        let rightWidth = (windowBounds.maxX - clearance) - (maskFrame.maxX + clearance)
        let stripY = maskFrame.minY
        let stripHeight = maskFrame.height

        if leftWidth >= rightWidth, leftWidth >= minimumStripWidth {
            return CGRect(
                x: windowBounds.minX + clearance,
                y: stripY,
                width: min(leftWidth, stripHeight * 4),
                height: stripHeight
            )
        }
        if rightWidth >= minimumStripWidth {
            let width = min(rightWidth, stripHeight * 4)
            return CGRect(
                x: windowBounds.maxX - clearance - width,
                y: stripY,
                width: width,
                height: stripHeight
            )
        }
        return nil
    }
}
