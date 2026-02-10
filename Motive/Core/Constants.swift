//
//  Constants.swift
//  Motive
//

import Foundation

enum MotiveConstants {
    enum Timeouts {
        /// API request timeout (seconds)
        static let apiRequest: TimeInterval = 30
        /// API resource timeout (seconds)
        static let apiResource: TimeInterval = 300
        /// Session activity timeout before showing warning (seconds)
        static let sessionActivity: TimeInterval = 120
        /// Delay before dismissing reasoning bubble (seconds)
        static let reasoningDismiss: TimeInterval = 2
        /// Server port detection timeout (seconds)
        static let portDetection: TimeInterval = 30
        /// Graceful server shutdown wait (seconds)
        static let gracefulShutdown: TimeInterval = 2
    }
    enum Limits {
        /// Maximum number of recent projects to keep
        static let maxRecentProjects = 10
        /// Maximum server restart attempts before giving up
        static let maxServerRestartAttempts = 3
    }
}
