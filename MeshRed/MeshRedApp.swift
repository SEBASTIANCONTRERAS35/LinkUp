//
//  MeshRedApp.swift
//  MeshRed
//
//  Created by Emilio Contreras on 28/09/25.
//

import SwiftUI

@main
struct MeshRedApp: App {
    @StateObject private var networkManager = NetworkManager()

    var body: some Scene {
        WindowGroup {
            MainDashboardContainer()
                .environmentObject(networkManager)
                .onAppear {
                    print("🚀 StadiumConnect Pro: App started with device: \(networkManager.localDeviceName)")
                }
        }
    }
}
