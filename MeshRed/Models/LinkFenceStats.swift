//
//  LinkFenceStats.swift
//  MeshRed - StadiumConnect Pro
//
//  Created for CSC 2025 - UNAM
//  Statistics and analytics for linkfence usage
//

import Foundation

/// Statistics for a specific linkfence calculated from event history
struct LinkFenceStats {
    let linkfenceId: UUID
    let linkfenceName: String
    let totalVisits: Int                    // Number of entry events
    let totalTimeInside: TimeInterval       // Total seconds spent inside
    let lastEntry: Date?                    // Most recent entry timestamp
    let lastExit: Date?                     // Most recent exit timestamp
    let averageStayDuration: TimeInterval   // Average duration per visit
    let currentlyInside: Bool               // Whether user is currently inside

    init(
        linkfenceId: UUID,
        linkfenceName: String,
        events: [LinkFenceEventMessage]
    ) {
        self.linkfenceId = linkfenceId
        self.linkfenceName = linkfenceName

        // Filter events for this specific linkfence
        let linkfenceEvents = events.filter { $0.linkfenceId == linkfenceId }

        // Calculate total visits (count entry events)
        let entryEvents = linkfenceEvents.filter { $0.eventType == .entry }
        let exitEvents = linkfenceEvents.filter { $0.eventType == .exit }
        self.totalVisits = entryEvents.count

        // Find most recent entry and exit
        self.lastEntry = entryEvents.map { $0.timestamp }.max()
        self.lastExit = exitEvents.map { $0.timestamp }.max()

        // Determine if currently inside
        if let lastEntry = lastEntry, let lastExit = lastExit {
            self.currentlyInside = lastEntry > lastExit
        } else if lastEntry != nil {
            self.currentlyInside = true
        } else {
            self.currentlyInside = false
        }

        // Calculate total time inside by pairing entries with exits
        var totalSeconds: TimeInterval = 0
        var completedVisits = 0

        // Sort events chronologically
        let sortedEvents = linkfenceEvents.sorted { $0.timestamp < $1.timestamp }

        // Pair entries with exits
        var lastEntryTime: Date?
        for event in sortedEvents {
            if event.eventType == .entry {
                lastEntryTime = event.timestamp
            } else if event.eventType == .exit, let entryTime = lastEntryTime {
                let duration = event.timestamp.timeIntervalSince(entryTime)
                totalSeconds += duration
                completedVisits += 1
                lastEntryTime = nil
            }
        }

        self.totalTimeInside = totalSeconds

        // Calculate average stay duration
        if completedVisits > 0 {
            self.averageStayDuration = totalSeconds / Double(completedVisits)
        } else {
            self.averageStayDuration = 0
        }
    }

    /// Human-readable total time inside
    var formattedTotalTime: String {
        return formatDuration(totalTimeInside)
    }

    /// Human-readable average duration
    var formattedAverageDuration: String {
        return formatDuration(averageStayDuration)
    }

    /// Human-readable time since last entry
    var timeSinceLastEntry: String? {
        guard let lastEntry = lastEntry else { return nil }
        return formatTimeAgo(from: lastEntry)
    }

    /// Human-readable time since last exit
    var timeSinceLastExit: String? {
        guard let lastExit = lastExit else { return nil }
        return formatTimeAgo(from: lastExit)
    }

    // MARK: - Helper Methods

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else if minutes > 0 {
            return "\(minutes)min"
        } else {
            return "< 1min"
        }
    }

    private func formatTimeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))

        if seconds < 60 {
            return "Hace \(seconds)s"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "Hace \(minutes)min"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "Hace \(hours)h"
        } else {
            let days = seconds / 86400
            return "Hace \(days)d"
        }
    }
}
