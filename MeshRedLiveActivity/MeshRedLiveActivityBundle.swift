//
//  MeshRedLiveActivityBundle.swift
//  MeshRedLiveActivity
//
//  Created by Emilio Contreras on 07/10/25.
//

import WidgetKit
import SwiftUI

@main
struct MeshRedLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        // Only register the actual MeshActivityWidget for StadiumConnect Pro
        if #available(iOS 16.1, *) {
            MeshActivityWidget()
        }
    }
}
