//
//  FamilyGeofenceMapView.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro - Geofencing System
//

import SwiftUI
import MapKit

struct FamilyGeofenceMapView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var geofenceManager: GeofenceManager
    @ObservedObject var familyGroupManager: FamilyGroupManager
    @ObservedObject var locationService: LocationService
    @ObservedObject var networkManager: NetworkManager

    @State private var showCreateGeofence = false
    @State private var showDeactivateAlert = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Map view
                if let geofence = geofenceManager.activeGeofence {
                    FamilyMapView(
                        geofence: geofence,
                        memberLocations: geofenceManager.memberLocations,
                        currentLocation: locationService.currentLocation,
                        familyMembers: familyGroupManager.currentGroup?.members ?? [],
                        localDeviceName: networkManager.localDeviceName,
                        geofenceManager: geofenceManager
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    // No active geofence
                    emptyStateView
                }

                // Bottom info panel
                if geofenceManager.activeGeofence != nil {
                    bottomInfoPanel
                        .background(Color(.systemBackground))
                }
            }
            .navigationTitle("Mapa Familiar")
            .navigationBarTitleDisplayMode(.inline)
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
                GeofenceCreatorView(
                    geofenceManager: geofenceManager,
                    locationService: locationService
                )
            }
            .alert("Desactivar Geofence", isPresented: $showDeactivateAlert) {
                Button("Cancelar", role: .cancel) {}
                Button("Desactivar", role: .destructive) {
                    geofenceManager.deactivateGeofence()
                }
            } message: {
                Text("¿Deseas dejar de monitorear '\(geofenceManager.activeGeofence?.name ?? "")'?")
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "map.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No hay geofence activo")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Crea un geofence para monitorear cuando familiares entren o salgan de un lugar")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: { showCreateGeofence = true }) {
                Label("Crear Geofence", systemImage: "plus.circle.fill")
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
            // Active geofence info
            if let geofence = geofenceManager.activeGeofence {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(geofence.name)
                            .font(.headline)

                        Text("Radio: \(Int(geofence.radius))m")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { showDeactivateAlert = true }) {
                        Text("Desactivar")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }

            // Recent events
            if !geofenceManager.recentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Eventos Recientes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    ForEach(geofenceManager.recentEvents.prefix(3)) { event in
                        eventRow(event)
                    }
                }
            }
        }
        .padding()
    }

    private func eventRow(_ event: GeofenceEventMessage) -> some View {
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

// MARK: - Family Map View Component
struct FamilyMapView: UIViewRepresentable {
    let geofence: CustomGeofence
    let memberLocations: [String: UserLocation]
    let currentLocation: UserLocation?
    let familyMembers: [FamilyMember]
    let localDeviceName: String
    let geofenceManager: GeofenceManager

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true

        // Center on geofence
        let region = MKCoordinateRegion(
            center: geofence.center,
            latitudinalMeters: geofence.radius * 3,
            longitudinalMeters: geofence.radius * 3
        )
        mapView.setRegion(region, animated: false)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Remove old overlays and annotations
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        // Add geofence circle
        let circle = MKCircle(center: geofence.center, radius: geofence.radius)
        mapView.addOverlay(circle)

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

            let annotation = FamilyMemberAnnotation(
                coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                member: member,
                isInside: geofence.contains(location)
            )
            mapView.addAnnotation(annotation)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.15)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 2
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

            // Set color based on inside/outside geofence
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
        return isInside ? "✅ Dentro del geofence" : "⚠️ Fuera del geofence"
    }

    init(coordinate: CLLocationCoordinate2D, member: FamilyMember, isInside: Bool) {
        self.coordinate = coordinate
        self.member = member
        self.isInside = isInside
        super.init()
    }
}
