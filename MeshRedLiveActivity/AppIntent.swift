//
//  AppIntent.swift
//  MeshRedLiveActivity
//
//  Created by Emilio Contreras on 07/10/25.
//

import WidgetKit
import AppIntents
import Foundation

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }

    // An example configurable parameter.
    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}

// MARK: - Stop Live Activity Intent

/// App Intent to stop the Live Activity from the Dynamic Island
///
/// SOLUTION FOR iOS 18+ COMPATIBILITY:
/// Uses App Group UserDefaults to communicate stop request to main app
/// This works because:
/// 1. AppIntent runs in widget extension process
/// 2. Widget writes "stop_live_activity" flag to shared UserDefaults
/// 3. Main app observes UserDefaults changes and terminates activity
/// 4. No need for dual target membership or complex Intent routing
///
/// RESULT:
/// - User taps Stop → Widget sets flag → App observes → Activity ends → No UI shown
///
/// CRITICAL FIX FOR iOS 18:
/// Using LiveActivityIntent instead of AppIntent because iOS 18 has a regression bug
/// where AppIntent.perform() never gets called when openAppWhenRun = false
/// LiveActivityIntent is the proper protocol for Live Activity interactions
@available(iOS 16.1, *)
struct StopActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Live Activity"
    static var description: IntentDescription = "Stops the StadiumConnect Pro Live Activity"

    // This property ensures the app doesn't open visually
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let timestamp = Date()
        let timestampString = DateFormatter.localizedString(from: timestamp, dateStyle: .none, timeStyle: .medium)

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🛑 STOP BUTTON PRESSED IN DYNAMIC ISLAND")
        print("   ⏰ Time: \(timestampString)")
        print("   📱 Process: WIDGET EXTENSION")
        print("   🔍 Thread: \(Thread.current)")
        print("   📤 Attempting to send stop request via App Group...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Use App Group to communicate with main app
        let appGroupName = "group.EmilioContreras.MeshRed"
        print("   📂 App Group: \(appGroupName)")

        if let sharedDefaults = UserDefaults(suiteName: appGroupName) {
            print("   ✅ Successfully accessed App Group UserDefaults")

            // Read current value before writing
            let previousValue = sharedDefaults.bool(forKey: "stop_live_activity")
            print("   📖 Previous 'stop_live_activity' value: \(previousValue)")

            // Set stop flag
            let timestampValue = timestamp.timeIntervalSince1970
            sharedDefaults.set(true, forKey: "stop_live_activity")
            sharedDefaults.set(timestampValue, forKey: "stop_live_activity_timestamp")

            print("   ✍️ Writing 'stop_live_activity' = true")
            print("   ✍️ Writing timestamp = \(timestampValue)")

            // Force synchronize
            let syncSuccess = sharedDefaults.synchronize()
            print("   💾 synchronize() returned: \(syncSuccess)")

            // Verify write succeeded
            let verifyValue = sharedDefaults.bool(forKey: "stop_live_activity")
            let verifyTimestamp = sharedDefaults.double(forKey: "stop_live_activity_timestamp")
            print("   🔍 Verification read 'stop_live_activity' = \(verifyValue)")
            print("   🔍 Verification read timestamp = \(verifyTimestamp)")

            if verifyValue == true {
                print("   ✅ WRITE VERIFIED: Flag successfully set to true")
                print("   🔄 Main app should detect this within 0.5 seconds")
            } else {
                print("   ❌ WRITE FAILED: Flag is still false after write!")
            }
        } else {
            print("   ❌ CRITICAL ERROR: Failed to access App Group UserDefaults")
            print("   ⚠️  Check that App Group '\(appGroupName)' is configured in:")
            print("      - MeshRed.entitlements")
            print("      - MeshRedLiveActivity.entitlements")
        }

        print("   🏁 StopActivityIntent.perform() completing")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        return .result()
    }
}
