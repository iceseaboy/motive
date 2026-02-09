//
//  CommandBarSupport.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import Foundation

extension AppState.MenuBarState {
    var displayText: String {
        switch self {
        case .idle: return L10n.CommandBar.ready
        case .reasoning: return L10n.StatusBar.reasoning
        case .executing: return L10n.StatusBar.executing
        case .responding: return L10n.StatusBar.executing
        }
    }
}
