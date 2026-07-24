# User-facing defaults and configurability

`Preferences.Defaults` is the only runtime source of persisted defaults. Every typed
user-facing key participates in `Preferences.configurableKeys`, and a regression test
fails when a new configurable key is omitted from Restore Defaults.

## WindowHop 1.3.1 decisions

| Feature | Default | Configurable | Settings / persistence / migration / Restore Defaults |
|---|---|---|---|
| Switcher shortcut | ⌘Tab | Yes | Shortcuts; typed `UserDefaults`; existing stored values win; resets to ⌘Tab. |
| Open WindowHop shortcut | ⌥Tab | Yes | Shortcuts; typed `UserDefaults`; an existing custom or explicitly cleared value wins; resets to ⌥Tab. |
| Show tab counts | Off | Yes | Appearance; typed `UserDefaults`; existing stored values win; resets to Off. |
| Context-sensitive Settings button | Enabled | No | One intended presentation behavior: hidden in cycling until panel hover, always visible in persistent mode. No persistence or reset entry. |
| Complete shortcut interception | Enabled | No | Correctness fix: an owned shortcut must not leak into the native app switcher. No persistence or reset entry. |
| Native title and metadata typography | Enabled | No | Shared required presentation and accessibility behavior. No arbitrary font preference, persistence, migration, or reset entry. |
| Preview skeletons | Enabled | No | Standard loading/fallback presentation. Loading animation follows the mandatory Reduce Motion system setting. No persistence or reset entry. |
| About attribution and website | Shown | No | Application metadata, centralized in `ProjectLinks`; no persistence or reset entry. |
| Restore Defaults | Available | No | Confirmed action rather than a preference. Resets every key in `Preferences.configurableKeys` and never changes permissions, identity, version, or first-run state. |

Existing preferences are never overwritten during an upgrade. Missing keys receive the
centralized default through the registration domain; migrations are explicit and tested.

## Unreleased decisions

| Feature | Default | Configurable | Settings / persistence / migration / Restore Defaults |
|---|---|---|---|
| Uniform Settings pane size | Enabled | No | One intended presentation behavior: every pane shares `DesignTokens.settingsPaneWidth`/`settingsPaneHeight`, so selecting a pane never resizes the window. No persistence or reset entry. |
| Selected Settings pane | General | No | Window-state restoration, not a preference: the pane identifier is stored in `UserDefaults` and ignored when unknown. Not part of `configurableKeys`; Restore Defaults leaves it untouched. |
| Unambiguous preview matching | Enabled | No | Correctness fix: a preview is shown only for the window it belongs to, otherwise the tile keeps its placeholder. No persistence or reset entry. |
