import Foundation

/// Which tracked applications leave the store when `NSWorkspace.runningApplications`
/// reports departures (#136).
///
/// Matching is by process identity, never by the departed object's process identifier:
/// after the process is gone that identifier can already read -1, and a new process can
/// reuse it. AltTab removes by `isEqual` for the same reason
/// (`317a485b:src/logic/Applications.swift`, `removeRunningApplications`). WindowHop adds
/// one guard: an app that is still in the running list has not departed, so a change that
/// lists it among the old values removes nothing.
public enum AppDeparture {
    /// The keys of `tracked` to remove, in the order their apps appear in `departed`,
    /// each once.
    public static func keysToRemove<Key: Hashable, App>(
        tracked: [Key: App],
        departed: [App],
        stillListed: [App],
        isSameProcess: (App, App) -> Bool
    ) -> [Key] {
        var keys: [Key] = []
        var seen: Set<Key> = []
        for app in departed where !stillListed.contains(where: { isSameProcess($0, app) }) {
            for (key, trackedApp) in tracked where isSameProcess(trackedApp, app) && seen.insert(key).inserted {
                keys.append(key)
            }
        }
        return keys
    }
}
