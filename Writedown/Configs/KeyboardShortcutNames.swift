//
//  KeyboardShortcutNames.swift
//  Writedown
//
//  Created by LC John on 2/14/25.
//

import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let quickWakeup = Self("quickWakeup", default: .init(.x, modifiers: [.option]))
}

// Make shortcuts enumerable
extension KeyboardShortcuts.Name: CaseIterable {
    public static let allCases: [Self] = [
        .quickWakeup
    ]
}
