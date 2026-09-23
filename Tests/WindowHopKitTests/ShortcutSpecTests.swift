import Foundation
import Testing

@testable import WindowHopKit

@MainActor  // reads ShortcutFormatter.keyLabels (see ShortcutFormatterLayoutTests)
struct ShortcutSpecTests {
    @Test func holdModifiers() {
        #expect(ShortcutSpec.commandTab.holdModifier == .maskCommand)
        #expect(ShortcutSpec.optionTab.holdModifier == .maskAlternate)
        #expect(ShortcutSpec.controlTab.holdModifier == .maskControl)
    }

    @Test func displayNamesUseTheSharedFormatter() {
        #expect(ShortcutSpec.commandTab.displayName == "⌘⇥")
        #expect(ShortcutSpec.optionTab.displayName == "⌥⇥")
        #expect(ShortcutSpec.controlTab.displayName == "⌃⇥")
    }

    @Test func formatterConsistency() {
        // ShortcutSpec and PersistentShortcut must render identical chords identically
        let persistent = PersistentShortcut(keyCode: KeyCode.tab, modifiers: [.maskCommand])
        #expect(persistent.displayString == ShortcutSpec.commandTab.displayName)
    }

    @Test func formatterKeyGlyphs() {
        #expect(ShortcutFormatter.chord(modifiers: [.maskCommand, .maskShift], keyCode: KeyCode.tab) == "⇧⌘⇥")
        #expect(ShortcutFormatter.chord(modifiers: [.maskAlternate], keyCode: KeyCode.space) == "⌥Space")
        #expect(ShortcutFormatter.keySymbol(for: KeyCode.returnKey) == "↩")
        #expect(ShortcutFormatter.keySymbol(for: KeyCode.escape) == "⎋")
        #expect(ShortcutFormatter.keySymbol(for: KeyCode.delete) == "⌫")
        #expect(ShortcutFormatter.keySymbol(for: KeyCode.forwardDelete) == "⌦")
        #expect(ShortcutFormatter.keySymbol(for: KeyCode.leftArrow) == "←")
        #expect(ShortcutFormatter.keySymbol(for: KeyCode.rightArrow) == "→")
        #expect(ShortcutFormatter.keySymbol(for: KeyCode.upArrow) == "↑")
        #expect(ShortcutFormatter.keySymbol(for: KeyCode.downArrow) == "↓")
    }

    @Test func spokenChordForAccessibility() {
        #expect(
            ShortcutFormatter.spokenChord(modifiers: [.maskCommand, .maskShift], keyCode: KeyCode.tab)
                == "Shift Command Tab")
        #expect(
            ShortcutFormatter.spokenChord(modifiers: [.maskAlternate], keyCode: KeyCode.space) == "Option Space")
    }

    @Test func rawValuesAreStable() {
        // persisted in UserDefaults; renaming cases would silently reset user settings
        #expect(ShortcutSpec.commandTab.rawValue == "commandTab")
        #expect(ShortcutSpec.optionTab.rawValue == "optionTab")
        #expect(ShortcutSpec.controlTab.rawValue == "controlTab")
    }
}
