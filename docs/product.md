# WindowHop — product definition

What this product is, who it serves, and what it will never become. Read this before proposing
a feature: if a proposal contradicts a non-goal below, the non-goal wins until this document
changes.

## What it is

A native macOS window switcher that gives every top-level window its own tile and activates the
exact window you select.

## Who it is for

Someone on macOS 14 or later who routinely keeps several windows of the *same* application open
— three browser windows, four terminals, two editor projects — spread across Spaces and
displays, and who switches between them dozens of times an hour by keyboard.

Not for someone who runs one window per app. For them the native switcher is already correct,
and WindowHop adds a step without removing one.

## The job

Get to one specific window immediately, without hunting for it.

**How that is done today.** Native ⌘Tab switches *applications* and lands on whichever window
that app last used, so reaching a particular window means a second move: ⌘` to cycle within the
app, or Mission Control and a mouse. Both cost a deliberate pause, and the mouse breaks a
keyboard flow.

**The honest alternative.** [AltTab](https://github.com/lwouis/alt-tab-macos) already solves
this job well, and WindowHop is derived from it. Anyone happy with AltTab has no reason to
switch. WindowHop is the deliberately smaller answer: a fixed presentation, two appearance
modes, and close to no configuration surface, for people who want the behavior without the
settings screen. That is a positioning choice, not a claim of superiority.

## What it does

- Lands on the exact window selected, including windows on another Space or another display.
- Shows one entry per top-level window. Tab groups collapse to their visible window, so a
  ten-tab Safari window is one tile, never ten.
- Works with no Screen Recording permission at all in its default App Icons mode. Window
  Previews is an opt-in that captures only while the switcher is open.
- Stays out of the way when it cannot help: if WindowHop is not running, is disabled, lacks
  Accessibility, or secure input is active, native ⌘Tab behaves exactly as it always did.
- Updates in place without costing the user their Accessibility grant.

## What it will never do

Each non-goal carries the reason that makes it one. A reason that stops being true is grounds
to reopen the non-goal — an inconvenient feature request is not.

- **Manage windows.** No tiling, moving, resizing, snapping, or arranging. The job ends the
  moment the right window has focus; arranging windows is a different product with a different
  mental model, and Rectangle and Magnet already serve it.
- **Search or launch.** No fuzzy-matching window titles, and never launching an application that
  is not already running. WindowHop switches among what exists; Spotlight, Raycast, and Alfred
  own find-and-launch. This one has a real cost — type-to-filter is a common switcher feature,
  including in AltTab — and it is declined anyway to keep the interaction a single held modifier.
- **Ship through the Mac App Store.** The sandbox forbids the Accessibility access the entire
  product depends on, and GPL-3.0 conflicts with the App Store distribution terms. A signed,
  notarized DMG updated by Sparkle is the only channel.
- **Collect anything.** No telemetry, analytics, accounts, advertising, or paid tier. Update
  checks are the only network activity the app is permitted to make. Privacy here is a property
  users can verify by reading the source, not a promise.
- **Use private APIs.** Public Apple APIs only. This costs real capability — windows on a Space
  the user has never visited stay undiscoverable — and the cost is accepted, because a switcher
  that breaks on a macOS update is worse than one that misses a window.
- **Localize.** English only, authored inline, with no localization layer. A single maintainer
  cannot keep translations honest, and stale translations are worse than none.
- **Disable the native switcher.** The Cmd-Tab symbolic hotkey is never taken away and
  `flagsChanged` events are never consumed. If WindowHop dies mid-keystroke, the user still has
  a working switcher. This is the fail-safe the whole design is arranged around.

Appearance customization is deliberately *not* on this list. It is currently constrained to two
modes and system Light/Dark by an implementation rule in `AGENTS.md`, which is a narrower and
more reversible commitment than a product non-goal.

## How you know it worked

There is no telemetry, so both signals are observed directly rather than measured remotely.

- **Daily use.** Across a normal working day the maintainer never consciously reaches for
  Apple's switcher, and never lands on a window they did not intend. Subjective, and true at
  n=1 — but it is the signal that tests the product's actual claim, and it is available today.
- **Correctness reports.** A release cycle closes with no report of a wrong window activated, a
  missing window, or a lost Accessibility grant. Baseline as of v1.5.0: no issue has ever been
  filed, so this signal is trivially met and only becomes informative once there is an audience.

Adoption numbers are explicitly not a success signal. Across thirteen releases the repository
has recorded 56 total asset downloads, which cannot distinguish a user from a Sparkle check.

## Constraints

- macOS 14 or later; Apple Silicon and Intel.
- Accessibility permission is mandatory; Screen Recording is optional and only for previews.
- Sparkle is the only runtime dependency.
- GPL-3.0-only, with AltTab attribution preserved in [UPSTREAM.md](../UPSTREAM.md).
- Official releases carry one stable Developer ID identity, notarized and stapled, so the TCC
  Accessibility grant survives updates.
- One maintainer. Anything that needs ongoing human upkeep — translations, a server, a support
  queue — is a cost the project cannot absorb.

## What this document is not

A specification. Individual requirements, acceptance criteria, and edge cases belong in issues.
Implementation rules, layer boundaries, and defaults belong in [AGENTS.md](../AGENTS.md),
[architecture.md](architecture.md), and [feature-defaults.md](feature-defaults.md).
