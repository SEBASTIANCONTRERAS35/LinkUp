//
//  FamilyLinkFenceMapView.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro - Geofencing System
//

import SwiftUI
import MapKit

struct FamilyLinkFenceMapView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var linkfenceManager: LinkFenceManager
    @ObservedObject var familyGroupManager: FamilyGroupManager
    @ObservedObject var locationService: LocationService
    @ObservedObject var networkManager: NetworkManager

    @State private var showCreateGeofence = false
    @State private var showDeactivateAlert = false
    @State private var selectedGeofence: CustomLinkFence?
    @State private var selectedGeofenceForNotifications: CustomLinkFence?
    @State private var mapCameraUpdate: MapCameraUpdate?

    // Show all linkfences (both active and inactive) for demo purposes
    private var activeGeofences: [CustomLinkFence] {
        // If we have linkfences in myGeofences, show those
        // Otherwise fall back to activeGeofences dictionary
        if !linkfenceManager.myGeofences.isEmpty {
            return linkfenceManager.myGeofences
        }
        return Array(linkfenceManager.activeGeofences.values)
    }

    private var selectedLinkFenceNotifications: [LinkFenceNotification] {
        guard let selected = selectedGeofenceForNotifications else { return [] }
        return MockLinkFenceData.generateMockNotifications(for: selected.id)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Map view - Show multiple linkfences
                if !activeGeofences.isEmpty {
                    FamilyMapViewMultiple(
                        linkfences: activeGeofences,
                        memberLocations: linkfenceManager.memberLocations,
                        currentLocation: locationService.currentLocation,
                        familyMembers: familyGroupManager.currentGroup?.members ?? [],
                        localDeviceName: networkManager.localDeviceName,
                        linkfenceManager: linkfenceManager,
                        cameraUpdate: $mapCameraUpdate,
                        selectedGeofence: $selectedGeofenceForNotifications
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    // No active linkfences
                    emptyStateView
                }

                // Bottom info panel - Show all active linkfences
                if !activeGeofences.isEmpty {
                    bottomInfoPanel
                        .background(Color(.systemBackground))
                }
            }
            .navigationTitle("Zonas")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Force load mock data for demo
                linkfenceManager.loadMockData()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showCreateGeofence = true }) {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showCreateGeofence) {
                LinkFenceCreatorView(
                    linkfenceManager: linkfenceManager,
                    locationService: locationService
                )
            }
            .alert("Desactivar LinkFence", isPresented: $showDeactivateAlert) {
                Button("Cancelar", role: .cancel) {}
                Button("Desactivar", role: .destructive) {
                    if let linkfence = selectedGeofence {
                        linkfenceManager.stopMonitoringGeofence(linkfence.id)
                        selectedGeofence = nil
                    }
                }
            } message: {
                Text("¿Deseas dejar de monitorear '\(selectedGeofence?.name ?? "")'?")
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "map.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No hay linkfence activo")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Crea un linkfence para monitorear cuando familiares entren o salgan de un lugar")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: { showCreateGeofence = true }) {
                Label("Crear LinkFence", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var bottomInfoPanel: some View {
        VStack(spacing: 16) {
            // Active linkfences carousel
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Zonas Activas")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Spacer()

                    Text("\(activeGeofences.count)/\(LinkFenceManager.maxMonitoredGeofences)")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(activeGeofences) { linkfence in
                            linkfenceCard(linkfence)
                        }
                    }
                }
            }

            // Notifications for selected linkfence
            if let selected = selectedGeofenceForNotifications {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Notificaciones - \(selected.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        Spacer()

                        Text("\(selectedLinkFenceNotifications.count)")
                            .font(.caption.bold())
                            .foregroundColor(selected.color)
                    }

                    ForEach(selectedLinkFenceNotifications.prefix(5)) { notification in
                        notificationRow(notification)
                    }

                    if selectedLinkFenceNotifications.isEmpty {
                        Text("No hay notificaciones para esta zona")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                }
            } else {
                // Show recent events if no zone selected
                if !linkfenceManager.recentEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Eventos Recientes (Todas las Zonas)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        ForEach(linkfenceManager.recentEvents.prefix(3)) { event in
                            eventRow(event)
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func linkfenceCard(_ linkfence: CustomLinkFence) -> some View {
        Button(action: {
            // Navigate to this linkfence on map
            navigateToGeofence(linkfence)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    // Icon with color
                    ZStack {
                        Circle()
                            .fill(linkfence.color.opacity(0.2))
                            .frame(width: 32, height: 32)

                        Image(systemName: linkfence.category.icon)
                            .font(.system(size: 14))
                            .foregroundColor(linkfence.color)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(linkfence.name)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                            .foregroundColor(.primary)

                        Text("Radio: \(Int(linkfence.radius))m")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Selection indicator
                    if selectedGeofenceForNotifications?.id == linkfence.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(linkfence.color)
                    }
                }

                HStack(spacing: 8) {
                    // View button
                    Button(action: {
                        navigateToGeofence(linkfence)
                    }) {
                        Text("Ver en mapa")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(linkfence.color.opacity(0.15))
                            .foregroundColor(linkfence.color)
                            .cornerRadius(6)
                    }

                    Spacer()

                    // Deactivate button
                    Button(action: {
                        selectedGeofence = linkfence
                        showDeactivateAlert = true
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(12)
        }
        .buttonStyle(.plain)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selectedGeofenceForNotifications?.id == linkfence.id ?
                      linkfence.color.opacity(0.1) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selectedGeofenceForNotifications?.id == linkfence.id ?
                       linkfence.color : Color.clear, lineWidth: 2)
        )
    }

    private func navigateToGeofence(_ linkfence: CustomLinkFence) {
        // Select this linkfence
        selectedGeofenceForNotifications = linkfence

        // Animate map to this linkfence
        mapCameraUpdate = MapCameraUpdate(
            center: linkfence.center,
            span: MKCoordinateSpan(
                latitudeDelta: linkfence.radius * 0.00002,
                longitudeDelta: linkfence.radius * 0.00002
            )
        )

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func notificationRow(_ notification: LinkFenceNotification) -> some View {
        HStack(spacing: 10) {
            // Icon with type color
            ZStack {
                Circle()
                    .fill(notification.type.color.opacity(0.2))
                    .frame(width: 36, height: 36)

                Image(systemName: notification.type.icon)
                    .font(.system(size: 16))
                    .foregroundColor(notification.type.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(notification.message)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(notification.timeAgo)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Importance indicator
            if notification.importance == .high {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
    }

    private func eventRow(_ event: LinkFenceEventMessage) -> some View {
        HStack(spacing: 10) {
            Text(event.emoji)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.senderNickname ?? event.senderId)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("\(event.eventType.displayName) - \(timeAgo(from: event.timestamp))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Circle()
                .fill(event.eventType == .entry ? Color.green : Color.red)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))

        if seconds < 60 {
            return "Hace \(seconds)s"
        } else if seconds < 3600 {
            return "Hace \(seconds / 60)m"
        } else {
            return "Hace \(seconds / 3600)h"
        }
    }
}

// MARK: - Map Camera Update Helper
struct MapCameraUpdate {
    let center: CLLocationCoordinate2D
    let span: MKCoordinateSpan
}

// MARK: - Family Map View Component (Multiple Geofences)
struct FamilyMapViewMultiple: UIViewRepresentable {
    let linkfences: [CustomLinkFence]
    let memberLocations: [String: UserLocation]
    let currentLocation: UserLocation?
    let familyMembers: [FamilyMember]
    let localDeviceName: String
    let linkfenceManager: LinkFenceManager
    @Binding var cameraUpdate: MapCameraUpdate?
    @Binding var selectedGeofence: CustomLinkFence?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true

        // Calculate region that encompasses all linkfences
        if !linkfences.isEmpty {
            let region = calculateOptimalRegion()
            mapView.setRegion(region, animated: false)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Remove old overlays and annotations
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        // Store linkfences in coordinator for color lookup
        context.coordinator.linkfences = linkfences

        // Add all linkfence circles
        for linkfence in linkfences {
            let circle = MKCircle(center: linkfence.center, radius: linkfence.radius)
            mapView.addOverlay(circle)
        }

        // Add family member annotations
        for member in familyMembers {
            // Skip current device (already shown as blue dot)
            if member.peerID == localDeviceName {
                continue
            }

            // Check if we have location for this member
            guard let location = memberLocations[member.peerID] else {
                continue
            }

            // Check if member is inside ANY linkfence
            let isInsideAny = linkfences.contains { $0.contains(location) }

            let annotation = FamilyMemberAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                member: member,
                isInside: isInsideAny
            )
            mapView.addAnnotation(annotation)
        }

        // Handle camera update
        if let update = cameraUpdate {
            let region = MKCoordinateRegion(center: update.center, span: update.span)
            mapView.setRegion(region, animated: true)

            // Clear the update after applying
            DispatchQueue.main.async {
                self.cameraUpdate = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // Calculate region that shows all linkfences
    private func calculateOptimalRegion() -> MKCoordinateRegion {
        guard !linkfences.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                latitudinalMeters: 1000,
                longitudinalMeters: 1000
            )
        }

        // Find bounds
        var minLat = linkfences[0].center.latitude
        var maxLat = linkfences[0].center.latitude
        var minLon = linkfences[0].center.longitude
        var maxLon = linkfences[0].center.longitude

        for linkfence in linkfences {
            minLat = min(minLat, linkfence.center.latitude)
            maxLat = max(maxLat, linkfence.center.latitude)
            minLon = min(minLon, linkfence.center.longitude)
            maxLon = max(maxLon, linkfence.center.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5,
            longitudeDelta: (maxLon - minLon) * 1.5
        )

        return MKCoordinateRegion(center: center, span: span)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        // Store linkfences for color lookup
        var linkfences: [CustomLinkFence] = []

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)

                // Find matching linkfence by comparing coordinates
                let matchingGeofence = linkfences.first { linkfence in
                    abs(linkfence.center.latitude - circle.coordinate.latitude) < 0.00001 &&
                    abs(linkfence.center.longitude - circle.coordinate.longitude) < 0.00001 &&
                    abs(linkfence.radius - circle.radius) < 1.0
                }

                if let linkfence = matchingGeofence {
                    // Use linkfence color
                    let color = linkfence.color
                    renderer.fillColor = UIColor(color).withAlphaComponent(0.15)
                    renderer.strokeColor = UIColor(color)
                    renderer.lineWidth = 2
                } else {
                    // Fallback to default blue
                    renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.15)
                    renderer.strokeColor = UIColor.systemBlue
                    renderer.lineWidth = 2
                }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Skip user location annotation
            if annotation is MKUserLocation {
                return nil
            }

            guard let familyAnnotation = annotation as? FamilyMemberAnnotation else {
                return nil
            }

            let identifier = "FamilyMember"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
            } else {
                annotationView?.annotation = annotation
            }

            // Set color based on inside/outside linkfence
            annotationView?.markerTintColor = familyAnnotation.isInside ? .systemGreen : .systemRed
            annotationView?.glyphImage = UIImage(systemName: familyAnnotation.isInside ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")

            return annotationView
        }
    }
}

// MARK: - Family Member Annotation
class FamilyMemberAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let member: FamilyMember
    let isInside: Bool

    var title: String? {
        return member.displayName
    }

    var subtitle: String? {
        return isInside ? "✅ Dentro del linkfence" : "⚠️ Fuera del linkfence"
    }

    init(coordinate: CLLocationCoordinate2D, member: FamilyMember, isInside: Bool) {
        self.coordinate = coordinate
        self.member = member
        self.isInside = isInside
        super.init()
    }
}
