# Window previews and switching

Dock previews, Option-Tab and the traffic-light panel share one window browser. Window placement uses the existing action performer. No external project is embedded or required at runtime.

User controls are described in the [user guide](USER_GUIDE.md); this document defines identity, discovery, capture and compatibility boundaries.

## Components

| Component | Responsibility |
|---|---|
| `WindowBrowserController` | Sessions, filtering, stable selection/order and action routing |
| `WindowBrowserPresentation` | Native panel/hosting-view lifetime, placement and corner clipping |
| `WindowBrowserFade` | Interruptible appearance/departure opacity and stale-completion rejection |
| `WindowBrowserPreferences` | Persistent feature toggles, delays and scale |
| `WindowCatalog` | Main-actor published list; serialized worker access and coalesced refreshes |
| `WindowDiscovery` | AX window identities, ordering, capture matching and activation |
| `WindowTabDiscovery` | Standard window tab bars and the scoped Safari adapter |
| `ActiveWindowObserver` / `DockHoverObserver` | Focus changes and Dock selection notifications |
| `WindowThumbnailStore` | Cache, retry policy and result lifetime |
| `ScreenCaptureThumbnailSource` | ScreenCaptureKit source matching and image capture |
| `WindowBrowserGeometry` / `WindowBrowserView` | Grid sizing and scaled preview content |

## Window and tab identity

Actions target a retained AX window and PID. CGWindowList/ScreenCaptureKit matching supplies a thumbnail source only; title matches never determine which window an action changes. Ambiguous capture matches use an icon. Temporary AX failures preserve an app's last known list rather than dropping it immediately.

“Show Tabs” is enabled by default. Standard recognition accepts a window-owned tab group with closable items and exactly one selected tab. Ordinary settings/content tab views do not qualify. The Safari exception recognizes native toolbar-provider tab buttons and is scoped to Safari. Discovery stays outside webpage/document content and does not use Apple Events. A shared monotonic deadline and request allowance bounds a scan; child-array reads are also capped. Exhausting the scan budget falls back to the window.

Each tab retains its AX element and containing window. Selecting an item raises that window and presses the exact tab element. Duplicate titles are valid; titles are not tab identity. Close Window, Minimize and placement apply to the containing window, not just the selected tab. Unsupported or ambiguous tab bars fall back to ordinary windows.

Inactive tabs share their window's active drawing surface, so they cannot be captured as independent live windows. They use their own cached image or an icon/title. Check selected-tab state before **and** after capture to avoid publishing another tab's image under the wrong label.

## Session and layout behavior

- Option-Tab cycles in a stable order while the panel is open; Shift reverses. Releasing Option or pressing Return activates the selection; Escape cancels. Arrow keys navigate, and focused panels also handle Command-W and Command-M.
- Focus observation includes switching between two windows of the same frontmost app. It refreshes the catalog without reordering an open switching session.
- Dock selection notifications schedule a preview without activating Blinker. Defaults are 150 ms before appearance and 200 ms before departure dismissal; settings allow 0–1000 ms and 100–1000 ms respectively. A grace period bridges travel from icon to panel. Dock restarts are checked periodically; hover discovery does not use permanent screen-wide pointer polling.
- The traffic-light management panel provides a “Windows of This App” entry.
- Scale ranges from 50–150% and applies to images, text, controls, spacing, corners and frame. The same preference controls Dock and keyboard previews. The grid has no pagination; it fits items to available space and scrolls when needed. Capture requests follow visible items in the lazy grid.
- Appearance fades in over 120 ms; departure fades out over 100 ms. Dismissal immediately releases the interactive panel and invalidates its session. A reusable, non-key, click-through panel briefly hosts the same content view for departure, without screen sampling or bitmap copies. Reopening interrupts that transition, and refreshes do not replay it. Reduce Motion makes both transitions immediate.

## Capture and resource policy

Screen Recording is requested only from the explicit settings button. Without it, titles/icons and window actions still work. Traffic-light glass uses native materials and requires no capture.

ScreenCaptureKit work is scheduled only while a preview session is open, one batch at a time. An equivalent request reuses in-flight work; changes to capture-relevant identity replace pending work rather than launching parallel non-cancellable captures. Focus-order changes alone do not discard a result. Closing the panel invalidates the session so late results cannot populate it. Images are not written to disk. Explicitly disabling thumbnails or detecting permission loss clears both published images and cached images; ordinary dismissal retains the cache for later minimized-window previews.

A capture-service preparation failure shows one retry notice and pauses automatic retries for that preview session. Explicit retry reuses the bounded visible request; it never requests permission. Inactive tabs and individual windows without an available image remain ordinary icon/title fallbacks.

Thumbnails are downscaled to fit 640×400 pixels. `NSCache` is configured with a 32 MiB cost limit and 64-entry limit; active image references are also bounded. These are cache policies, not a hard cap on total process memory or capture-framework allocations.

Hidden/minimized windows reuse their own cached images. A cold offscreen capture can be attempted if a source can be matched conservatively; actual failed captures are rate-limited, while cancelled or superseded work does not start the retry cooldown. Fresh minimized-window imagery is not guaranteed by the target app or system. Background tabs are not activated merely to create a thumbnail.

## Compatibility and verification

Discovery uses public Accessibility and CGWindowList APIs. Apps may omit other-Space windows, expose incomplete AX hierarchies or implement their own tab bars. Do not promise universal tab support or complete cross-Space discovery/control. The private Space API used by experimental workspace restore is separate from this browser.

Automated coverage should exercise selection wrapping/retention, ambiguous capture matching, duplicate tab titles, rejection of content tabs, geometry on small/offset screens and stale asynchronous work. Native acceptance checks should cover:

1. Permission fallback and explicit re-check after authorization.
2. Opening, cycling, canceling and activating a specific window/tab.
3. Native AppKit tabs (for example Finder/TextEdit) and Safari's separate adapter.
4. Show Tabs on/off, minimized windows, own-image caching and unavailable captures.
5. Dock-to-panel travel, app/Dock restarts, multiple displays and focus changes.
6. Full-panel scaling and large collections without pagination.

Record observed results in the change or release review, not as a permanent dated log here. Unit tests alone cannot establish mouse-travel behavior, AX support across applications or capture performance.

## Design references

Behavioral references informed the independent implementation; their source code is not vendored into Blinker:

- [AltTab](https://github.com/lwouis/alt-tab-macos): recent-focus ordering, modifier-release switching and bounded thumbnail work. GPL-3.0.
- [DockDoor](https://github.com/ejbills/DockDoor/tree/42b3b1db307fd09f6a3d7974902e87ba37c204a4): Dock selection observation, asynchronous cached previews and Dock-relative positioning. GPL-3.0-or-later.
- [Rectangle](https://github.com/rxhanson/Rectangle/tree/c0ae7f87abe66f66b2857fbd4ad19ef802a9b43a): snap areas, orientation-aware thirds, display transfer and minimum-size handling. MIT.

Keep upstream code reuse distinct from behavioral research and check licensing before importing any future implementation.
