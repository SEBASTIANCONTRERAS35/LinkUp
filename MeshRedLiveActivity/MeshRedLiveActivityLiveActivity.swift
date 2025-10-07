//
//  MeshRedLiveActivityLiveActivity.swift
//  MeshRedLiveActivity
//
//  Created by Emilio Contreras on 07/10/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct MeshRedLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct MeshRedLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeshRedLiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension MeshRedLiveActivityAttributes {
    fileprivate static var preview: MeshRedLiveActivityAttributes {
        MeshRedLiveActivityAttributes(name: "World")
    }
}

extension MeshRedLiveActivityAttributes.ContentState {
    fileprivate static var smiley: MeshRedLiveActivityAttributes.ContentState {
        MeshRedLiveActivityAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: MeshRedLiveActivityAttributes.ContentState {
         MeshRedLiveActivityAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: MeshRedLiveActivityAttributes.preview) {
   MeshRedLiveActivityLiveActivity()
} contentStates: {
    MeshRedLiveActivityAttributes.ContentState.smiley
    MeshRedLiveActivityAttributes.ContentState.starEyes
}
