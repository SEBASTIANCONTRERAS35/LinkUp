import SwiftUI
import MultipeerConnectivity

/// Advanced network orchestrator diagnostics and control panel
struct NetworkOrchestratorView: View {
    @ObservedObject var networkManager: NetworkManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HeaderSection(networkManager: networkManager)

                // Leader Election Status
                LeaderElectionSection(networkManager: networkManager)

                // Connection Pool Status
                ConnectionPoolSection(networkManager: networkManager)

                // Network State
                NetworkStateSection(networkManager: networkManager)

                // Peer Reputations
                PeerReputationSection(networkManager: networkManager)

                // Recommendations
                RecommendationsSection(networkManager: networkManager)

                // Controls
                ControlsSection(networkManager: networkManager)
            }
            .padding()
        }
        .navigationTitle("Network Orchestrator")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Header Section

private struct HeaderSection: View {
    @ObservedObject var networkManager: NetworkManager

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: networkManager.isOrchestratorEnabled ? "brain.head.profile" : "brain.head.profile.fill")
                    .font(.largeTitle)
                    .foregroundColor(networkManager.isOrchestratorEnabled ? .green : .gray)

                VStack(alignment: .leading) {
                    Text("Orchestrator Status")
                        .font(.headline)
                    Text(networkManager.isOrchestratorEnabled ? "Active" : "Disabled")
                        .font(.subheadline)
                        .foregroundColor(networkManager.isOrchestratorEnabled ? .green : .red)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { networkManager.isOrchestratorEnabled },
                    set: { networkManager.isOrchestratorEnabled = $0 }
                ))
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 5)
        }
    }
}

// MARK: - Leader Election Section

private struct LeaderElectionSection: View {
    @ObservedObject var networkManager: NetworkManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leader Election")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    if networkManager.isOrchestratorEnabled {
                        if networkManager.isClusterLeader() {
                            Label("You are the LEADER", systemImage: "crown.fill")
                                .foregroundColor(.yellow)
                                .font(.subheadline.bold())
                        } else {
                            Label("Follower Mode", systemImage: "person.fill")
                                .foregroundColor(.blue)
                                .font(.subheadline)

                            if let leader = networkManager.orchestrator.leaderElection.currentLeader {
                                Text("Leader: \(leader)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("Term: \(networkManager.orchestrator.leaderElection.currentTerm)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Orchestrator disabled")
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if networkManager.isOrchestratorEnabled {
                    Button(action: {
                        networkManager.forceLeaderElection()
                    }) {
                        Label("Start Election", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Connection Pool Section

private struct ConnectionPoolSection: View {
    @ObservedObject var networkManager: NetworkManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection Pool")
                .font(.headline)

            if networkManager.isOrchestratorEnabled {
                let status = networkManager.orchestrator.connectionPool.getStatus()

                HStack(spacing: 20) {
                    ConnectionStatusBadge(label: "Occupied", value: "\(status.occupied)/5", color: .green)
                    ConnectionStatusBadge(label: "Reserved", value: "\(status.reserved)", color: .orange)
                    ConnectionStatusBadge(label: "Available", value: "\(status.available)", color: .blue)
                }

                // Slot Details
                VStack(spacing: 8) {
                    ForEach(networkManager.orchestrator.connectionPool.getSlotInfo(), id: \.peer) { slot in
                        SlotRow(
                            priority: slot.priority,
                            peer: slot.peer,
                            duration: slot.duration
                        )
                    }
                }
            } else {
                Text("Orchestrator disabled")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

private struct ConnectionStatusBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct SlotRow: View {
    let priority: ConnectionPoolManager.ConnectionPriority
    let peer: String?
    let duration: TimeInterval?

    var body: some View {
        HStack {
            Text(priority.color)
                .font(.title3)

            VStack(alignment: .leading) {
                Text(peer ?? "Empty")
                    .font(.subheadline)
                    .foregroundColor(peer != nil ? .primary : .secondary)

                Text(priority.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let duration = duration {
                Text(formatDuration(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Network State Section

private struct NetworkStateSection: View {
    @ObservedObject var networkManager: NetworkManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network State")
                .font(.headline)

            if networkManager.isOrchestratorEnabled {
                let state = networkManager.orchestrator.networkState

                VStack(spacing: 8) {
                    StateRow(label: "Connected Peers", value: "\(state.connectedPeers)")
                    StateRow(label: "Available Peers", value: "\(state.availablePeers)")
                    StateRow(label: "Network Load", value: String(format: "%.1f%%", state.networkLoad * 100))
                    StateRow(label: "Battery Level", value: String(format: "%.0f%%", state.batteryLevel * 100))
                    StateRow(label: "Avg Latency", value: String(format: "%.1f ms", state.averageLatency))
                }
            } else {
                Text("Orchestrator disabled")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

private struct StateRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(.blue)
        }
    }
}

// MARK: - Peer Reputation Section

private struct PeerReputationSection: View {
    @ObservedObject var networkManager: NetworkManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Peer Reputations")
                .font(.headline)

            if networkManager.isOrchestratorEnabled {
                let topPeers = networkManager.orchestrator.reputationSystem.getTopPeers(limit: 5)

                if topPeers.isEmpty {
                    Text("No reputation data yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(topPeers, id: \.peerId) { reputation in
                            ReputationRow(reputation: reputation)
                        }
                    }
                }
            } else {
                Text("Orchestrator disabled")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

private struct ReputationRow: View {
    let reputation: PeerReputationSystem.PeerReputation

    var body: some View {
        HStack {
            Text(reputation.trustLevel.rawValue)
                .font(.title3)

            VStack(alignment: .leading) {
                Text(reputation.peerId)
                    .font(.subheadline)

                HStack {
                    Text(reputation.trustLevel.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(reputation.successfulConnections) connections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text(String(format: "%.0f", reputation.trustScore))
                    .font(.title3.bold())
                    .foregroundColor(scoreColor(reputation.trustScore))

                Text("score")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func scoreColor(_ score: Float) -> Color {
        switch score {
        case 0..<30: return .red
        case 30..<50: return .orange
        case 50..<70: return .yellow
        case 70..<85: return .green
        default: return .blue
        }
    }
}

// MARK: - Recommendations Section

private struct RecommendationsSection: View {
    @ObservedObject var networkManager: NetworkManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommendations")
                .font(.headline)

            if networkManager.isOrchestratorEnabled {
                let recommendations = networkManager.getConnectionRecommendations()

                if recommendations.isEmpty || recommendations.first == "Orchestrator disabled" {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("All systems optimal")
                            .font(.subheadline)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(recommendations, id: \.self) { recommendation in
                            HStack(alignment: .top) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                Text(recommendation)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            } else {
                Text("Enable orchestrator to see recommendations")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Controls Section

private struct ControlsSection: View {
    @ObservedObject var networkManager: NetworkManager

    var body: some View {
        VStack(spacing: 12) {
            Button(action: {
                networkManager.optimizeConnections()
            }) {
                Label("Optimize Connections", systemImage: "wand.and.stars")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(!networkManager.isOrchestratorEnabled)

            Button(action: {
                // Show full network summary in console
                print(networkManager.getOrchestratorStatus())
            }) {
                Label("Print Full Status", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.secondary.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
            }
        }
    }
}

// MARK: - Preview

struct NetworkOrchestratorView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NetworkOrchestratorView(networkManager: NetworkManager())
        }
    }
}