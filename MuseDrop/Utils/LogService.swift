//
//  LogService.swift
//  MuseDrop
//
//  Created on 11/20/25.
//

import Foundation
import OSLog

class LogService {
    static let shared = LogService()
    private let logger: Logger
    
    private init() {
        logger = Logger(subsystem: "com.kekasatori.app", category: "Kekasatori")
    }
    
    func info(_ message: String) {
        logger.info("\(message)")
        writeToFile(message, level: "INFO")
    }
    
    func error(_ message: String, error: Error? = nil) {
        let errorMessage = error != nil ? "\(message): \(error!.localizedDescription)" : message
        logger.error("\(errorMessage)")
        writeToFile(errorMessage, level: "ERROR")
    }
    
    func debug(_ message: String) {
        logger.debug("\(message)")
        writeToFile(message, level: "DEBUG")
    }
    
    func warning(_ message: String) {
        logger.warning("\(message)")
        writeToFile(message, level: "WARNING")
    }
    
    private func writeToFile(_ message: String, level: String) {
        // Only mirror logs to disk in debug builds. The file was unbounded and
        // could contain user-derived content (paper titles, search queries), so
        // release builds keep logging to OSLog/Console only.
        #if DEBUG
        let logMessage = "[\(Date().ISO8601Format())] [\(level)] \(message)\n"

        guard let logData = logMessage.data(using: .utf8) else { return }

        let logFile = PathUtils.applicationSupportDirectory.appendingPathComponent("logs.txt")

        if let fileHandle = try? FileHandle(forWritingTo: logFile) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(logData)
            fileHandle.closeFile()
        } else {
            // Create file if it doesn't exist
            try? logData.write(to: logFile)
        }
        #endif
    }
}

