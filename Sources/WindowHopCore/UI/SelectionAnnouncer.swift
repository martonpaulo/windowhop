import AppKit

/// Posts the switcher's selection announcement — the only accessible output of
/// a selection change, because nothing moves VoiceOver focus into the panel.
///
/// Selection is one shared state across mirrored panels, so it has one poster:
/// `SwitcherPanelGroup` owns a single announcer and one semantic change speaks
/// once, whatever the number of target displays.
final class SelectionAnnouncer {
    /// Receives the announced window's identity and the text to speak.
    typealias Post = (_ id: AnyHashable, _ text: String) -> Void

    private let post: Post

    /// The window identity spoken last, or nil when no session is presented.
    private(set) var lastAnnouncedID: AnyHashable?

    init(post: @escaping Post = SelectionAnnouncer.postToApplication) {
        self.post = post
    }

    /// Announces `item` unconditionally: an explicit selection re-confirms its
    /// target even when it did not move (a one-item wrap).
    func announce(_ item: SwitcherItem) {
        lastAnnouncedID = item.id
        post(item.id, SwitcherTileView.accessibilityText(
            for: item, showTabCounts: Preferences.shared.showTabCounts))
    }

    /// Announces `item` only when it is a different window from the last one
    /// spoken: a live refresh that replaced the selected window must say so,
    /// while a title, preview or appended-window refresh must stay silent.
    func announceIfChanged(_ item: SwitcherItem) {
        guard item.id != lastAnnouncedID else { return }
        announce(item)
    }

    /// Forgets the last target, at the end of a presentation.
    func reset() {
        lastAnnouncedID = nil
    }

    private static func postToApplication(_: AnyHashable, text: String) {
        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [.announcement: text,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
