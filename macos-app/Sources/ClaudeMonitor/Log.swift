import Foundation
import os.log

enum Log {
    static let subsystem = "com.cybrosys.claudemonitor"
    static let appLog    = OSLog(subsystem: subsystem, category: "app")
    static let claudeLog = OSLog(subsystem: subsystem, category: "claude")
    static let codexLog  = OSLog(subsystem: subsystem, category: "codex")

    static func info(_ tag: String, _ message: String) {
        let log: OSLog
        switch tag {
        case "claude": log = claudeLog
        case "codex":  log = codexLog
        default:       log = appLog
        }
        os_log("%{public}@", log: log, type: .default, message)
    }
}
