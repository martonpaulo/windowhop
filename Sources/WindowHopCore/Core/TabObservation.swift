import Foundation

/// One attribute read, keeping a legitimate absence (the attribute has no value or
/// is unsupported) apart from a failed read (the app did not answer).
public enum AttributeRead<Value> {
    case value(Value)
    case absent
    case failed

    public func map<Mapped>(_ transform: (Value) -> Mapped) -> AttributeRead<Mapped> {
        switch self {
        case .value(let value): return .value(transform(value))
        case .absent: return .absent
        case .failed: return .failed
        }
    }
}

/// What one read of a window's tab bar established (see TabGroupResolver). Only a
/// complete, successful read may change group membership.
public enum TabObservation: Equatable {
    /// Some read failed: nothing is known, so nothing may change.
    case unknown
    /// The window's children were read and show no tab bar with 2 or more tabs.
    case standalone
    /// Every tab button of the window's tab bar was read, in order.
    case group([String])

    /// One tab-bar child as read from AX.
    public struct TabButtonFacts {
        public let subrole: AttributeRead<String>
        public let title: AttributeRead<String>

        public init(subrole: AttributeRead<String>, title: AttributeRead<String>) {
            self.subrole = subrole
            self.title = title
        }
    }

    /// One child of the window as read from AX; `tabs` matters only for AXTabGroup.
    public struct ChildFacts {
        public let role: AttributeRead<String>
        public let tabs: AttributeRead<[TabButtonFacts]>

        public init(role: AttributeRead<String>, tabs: AttributeRead<[TabButtonFacts]>) {
            self.role = role
            self.tabs = tabs
        }
    }

    /// Decides the observation from plain facts. The first AXTabGroup child decides
    /// (one title per AXTabButton, 2 or more for a group). A failed read on the way
    /// to that answer makes it `.unknown`: AltTab v10.12.0 dropped a tab whose read
    /// failed and treated the rest as complete, which released the dropped tab's
    /// window as an independent entry. Upstream 8c8d2836 separates unknown from
    /// standalone the same way.
    public static func classify(children: AttributeRead<[ChildFacts]>) -> TabObservation {
        let childFacts: [ChildFacts]
        switch children {
        case .failed: return .unknown
        case .absent: return .standalone
        case .value(let read): childFacts = read
        }
        var sawFailedRole = false
        for child in childFacts {
            switch child.role {
            case .failed:
                sawFailedRole = true
                continue
            case .absent:
                continue
            case .value(let role):
                guard role == "AXTabGroup" else { continue }
            }
            return classify(tabs: child.tabs)
        }
        // an unreadable child could have been the tab bar
        return sawFailedRole ? .unknown : .standalone
    }

    private static func classify(tabs: AttributeRead<[TabButtonFacts]>) -> TabObservation {
        let buttons: [TabButtonFacts]
        switch tabs {
        case .failed: return .unknown
        case .absent: buttons = []
        case .value(let read): buttons = read
        }
        var titles = [String]()
        for tab in buttons {
            switch tab.subrole {
            case .failed: return .unknown
            case .absent: continue
            case .value(let subrole): guard subrole == "AXTabButton" else { continue }
            }
            switch tab.title {
            case .failed: return .unknown
            case .absent: titles.append("")
            case .value(let title): titles.append(title)
            }
        }
        return titles.count >= 2 ? .group(titles) : .standalone
    }
}
