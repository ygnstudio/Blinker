import SwiftUI

/// Inline two-language switch: UI text is authored as `tr("中文", "English")`.
/// Views observe `AppPreferences.shared`, so changing the language setting
/// re-renders them immediately — no `.strings` infrastructure needed for an
/// app of this size.
func tr(_ chinese: String, _ english: String) -> String {
    AppPreferences.shared.isEnglish ? english : chinese
}
