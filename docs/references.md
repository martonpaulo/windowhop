# References and inspirations

Every source WindowHop learned from, in one index. [UPSTREAM.md](../UPSTREAM.md) owns the
third-party code sources (the AltTab upstream, forks, similar switchers, window managers), with
their licences and verdicts; this file points to its sections and records only the design
inspirations and technical sources, which no other file records.

Before diagnosing a hard bug, choosing a module boundary, or deciding a UX pattern, read the
matching section and check how these sources solved the same problem. Their solution is evidence,
not a rule: adopt it, adapt it, or record why WindowHop differs. Add what was learned to the row.
Cite, never copy: third-party code, images and text stay where they are published unless their
licence permits reuse, and then the credit is kept.
In the Access column, *link checked* means the link opened on that date when this index was
written; the content was read when the linked issue was worked.

## Upstream and forks

- [UPSTREAM.md](../UPSTREAM.md) › *Upstream: AltTab*: the base revision (`v10.12.0`,
  `317a485b`) and what was retained, corrected and removed, with each ported rule's upstream
  commit.
- [UPSTREAM.md](../UPSTREAM.md) › *Other sources* › *AltTab forks*: the forks reviewed, what
  each contributes, and the issues that used them.

## Reference implementations

- [UPSTREAM.md](../UPSTREAM.md) › *Other sources* › *Similar switchers and preview tools*:
  BetterCmdTab, DockDoor, sxitch, switch, and the website source of rcmd.
- [UPSTREAM.md](../UPSTREAM.md) › *Other sources* › *Window managers, automation tools, and AX
  libraries*: AeroSpace, Loop, Rectangle, Hammerspoon and others, with the rule each informed.
- [UPSTREAM.md](../UPSTREAM.md) › *Other sources* › *Imported test data*: the AeroSpace AX dumps
  used as test fixtures (#115).

## Product and visual design inspirations

| Source | Where to obtain it | Access | What it established or inspired here | Rights |
| --- | --- | --- | --- | --- |
| macOS App Switcher (⌘Tab) | Built into macOS | 2026-09-25, used | No panel for a quick ⌘Tab tap ([#32](https://github.com/martonpaulo/windowhop/issues/32)); `` ` `` steps back in a session ([#135](https://github.com/martonpaulo/windowhop/issues/135)); the native switcher takes over when WindowHop is off ([#72](https://github.com/martonpaulo/windowhop/issues/72), `Sources/WindowHopKit/SwitchingGuide.swift`); the baseline of the comparison page (`site/alttab-alternative/index.html`) | Apple; nothing reused |
| Apple HIG, Keyboards | <https://developer.apple.com/design/human-interface-guidelines/keyboards> | 2026-09-25, link checked | The standard app commands a recorded shortcut must not take (`Sources/WindowHopKit/ShortcutConflicts.swift`, `7769e01c`, [#56](https://github.com/martonpaulo/windowhop/issues/56)) | Apple; nothing reused |
| Apple HIG, Buttons (destructive role) | <https://developer.apple.com/design/human-interface-guidelines/buttons> | 2026-09-25, link checked | "Quit WindowHop…" is not red: destructive style is for actions that lose data ([#121](https://github.com/martonpaulo/windowhop/issues/121)) | Apple; nothing reused |

## Technical literature, specs and research

| Source | Where to obtain it | Access | What it established or inspired here | Rights |
| --- | --- | --- | --- | --- |
| Apple docs, `CGDisplayCreateUUIDFromDisplayID` | <https://developer.apple.com/documentation/colorsync/cgdisplaycreateuuidfromdisplayid(_:)> | 2026-09-25, link checked | The display UUID is the stable display identity, and the call can return nil (`Sources/WindowHopCore/Engine/DisplayRegistry.swift`, `38cc1ce7`, [#11](https://github.com/martonpaulo/windowhop/issues/11)) | Apple; nothing reused |
| Stack Overflow answer 56268826 | <https://stackoverflow.com/a/56268826/2249756> | 2026-09-25, failed (bot check); cited in code inherited from AltTab `23bbd649` | Do not use `NSScreen.main` for the display under the pointer (`Sources/WindowHopCore/Engine/DisplayRegistry.swift`) | CC BY-SA; nothing copied |
| Apple docs, `SMAppService.Status` | <https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum> | 2026-09-25, link checked | Launch-at-login state is read back from the system, never assumed (`Sources/WindowHopCore/Engine/LoginItem.swift`, `bb868eaa`, [#57](https://github.com/martonpaulo/windowhop/issues/57)) | Apple; nothing reused |
| Apple docs, Swift Testing | <https://developer.apple.com/documentation/testing> | 2026-09-25, link checked | The only test framework (`docs/testing.md`, `e8500917`, [#102](https://github.com/martonpaulo/windowhop/issues/102)) | Apple; nothing reused |
| Apple, Accessibility for custom controls (archived guide) | <https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/ImplementingAccessibilityforCustomControls.html> | 2026-09-25, link checked | Tiles expose the accessibility actions that match their role ([#17](https://github.com/martonpaulo/windowhop/issues/17)) | Apple; nothing reused |
| Apple SDK header `NSRunningApplication.h` | AppKit headers in the macOS SDK shipped with Xcode | 2026-09-25, read (macOS 27.0 SDK, lines 103–107) | `processIdentifier` is not an identity: compare with `isEqual:` (`Sources/WindowHopKit/AppDeparture.swift`, [#136](https://github.com/martonpaulo/windowhop/issues/136)) | Apple; nothing reused |
| W3C, WCAG 2.2 Understanding Contrast (Minimum) | <https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html> | 2026-09-25, link checked | 4.5:1 contrast for the site's download buttons, hover included ([#26](https://github.com/martonpaulo/windowhop/issues/26)) | W3C; nothing reused |
| W3C, CSS Syntax Module Level 3 | <https://www.w3.org/TR/css-syntax-3/> | 2026-09-25, link checked | A comment is not a token, so a leftover selector swallows the next at-rule; `make validate` now rejects that shape ([#133](https://github.com/martonpaulo/windowhop/issues/133)) | W3C; nothing reused |
| Google Search Central, favicon in search results | <https://developers.google.com/search/docs/appearance/favicon-in-search> | 2026-09-25, link checked | A square, crawlable icon at a stable URL, larger than 48 px (`fdcd03c9`, [#93](https://github.com/martonpaulo/windowhop/issues/93)) | Google; nothing reused |
| Google Search Central, SEO starter guide and title links | <https://developers.google.com/search/docs/fundamentals/seo-starter-guide>, <https://developers.google.com/search/docs/appearance/title-link> | 2026-09-25, link checked | Write for the terms readers use; no meta keywords or keyword stuffing ([#94](https://github.com/martonpaulo/windowhop/issues/94)) | Google; nothing reused |
| Microsoft, ICO file format | <https://learn.microsoft.com/en-us/previous-versions/ms997538(v=msdn.10)> | 2026-09-25, link checked | The PNG-in-ICO layout of the favicon (`scripts/make-icon.swift`, `fdcd03c9`, [#93](https://github.com/martonpaulo/windowhop/issues/93)) | Microsoft; nothing reused |
| GitHub docs, issue form schema | <https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-githubs-form-schema> | 2026-09-25, link checked | "Report an Issue" prefills form fields by their `id` (`Sources/WindowHopKit/ProjectLinks.swift`, `8665513e`, [#69](https://github.com/martonpaulo/windowhop/issues/69)) | GitHub; nothing reused |
