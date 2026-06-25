//
//  WaitDurationFormatter.swift
//  MuseDrop
//

import Foundation

enum WaitDurationFormatter {
    /// Human-readable elapsed time, e.g. "12 seconds", "2 minutes", "1 minute 5 seconds".
    static func format(seconds: Int) -> String {
        guard seconds > 0 else { return "just started" }
        
        if seconds < 60 {
            return seconds == 1 ? "1 second" : "\(seconds) seconds"
        }
        
        let minutes = seconds / 60
        let remainder = seconds % 60
        
        if remainder == 0 {
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        
        let minuteLabel = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        let secondLabel = remainder == 1 ? "1 second" : "\(remainder) seconds"
        return "\(minuteLabel) \(secondLabel)"
    }
}
