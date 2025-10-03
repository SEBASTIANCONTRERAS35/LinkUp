//
//  ContentView.swift
//  MeshRed Watch App Watch App
//
//  Created by Emilio Contreras on 03/10/25.
//  StadiumConnect Pro - Apple Watch App
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: SOS Emergency Button
            WatchSOSView()
                .tag(0)

            // Tab 2: Family Status (TODO: Fase 2)
            WatchFamilyStatusView()
                .tag(1)

            // Tab 3: Settings (TODO: Fase 2)
            WatchSettingsView()
                .tag(2)
        }
        .tabViewStyle(.page)
    }
}

// MARK: - Placeholder Views (Fase 2)

struct WatchFamilyStatusView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 40))
                .foregroundColor(.blue)

            Text("Familia")
                .font(.headline)

            Text("Próximamente")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct WatchSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gear")
                .font(.system(size: 40))
                .foregroundColor(.gray)

            Text("Configuración")
                .font(.headline)

            Text("Próximamente")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
