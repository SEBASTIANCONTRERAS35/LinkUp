//
//  GeofenceCreatorView.swift
//  MeshRed
//
//  Created by Claude for StadiumConnect Pro - Geofencing System
//  Updated: Fixed map interaction and added tap gesture
//

import SwiftUI
import MapKit

struct GeofenceCreatorView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var geofenceManager: GeofenceManager
    @ObservedObject var locationService: LocationService

    @State private var name: String = ""
    @State private var radius: Double = 500  // Default 500m
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 19.302778, longitude: -99.150556),  // Default: Estadio Azteca
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var shareWithFamily: Bool = true
    @State private var showSaveConfirmation = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Map with tap/long press gestures
                ZStack {
                    GeofenceMapEditor(
                        region: $region,
                        selectedCoordinate: $selectedCoordinate,
                        radius: $radius
                    )

                    // Instruction overlay when no pin selected
                    if selectedCoordinate == nil {
                        VStack {
                            Spacer()
                            HStack(spacing: 8) {
                                Image(systemName: "hand.tap.fill")
                                    .font(.title3)
                                Text("Toca el mapa para colocar el pin del geofence")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                            .padding()
                        }
                        .transition(.opacity)
                    }
                }
                .frame(maxHeight: .infinity)

                // Controls panel
                VStack(spacing: 16) {
                    // Selected coordinate indicator
                    if let coordinate = selectedCoordinate {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.blue)
                            Text("Pin colocado en: \(String(format: "%.4f", coordinate.latitude)), \(String(format: "%.4f", coordinate.longitude))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: { selectedCoordinate = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }

                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nombre del lugar")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("ej. Estadio Azteca", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Radius slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Radio")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("\(Int(radius))m")
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                        }

                        Slider(value: $radius, in: 100...5000, step: 50)
                            .tint(.accentColor)
                    }

                    // Share toggle
                    Toggle("Compartir con familia", isOn: $shareWithFamily)
                        .font(.subheadline)

                    // Save button
                    Button(action: saveGeofence) {
                        Label("Crear Geofence", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canSave ? Color.accentColor : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(!canSave)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Crear Geofence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: centerOnUser) {
                        Image(systemName: "location.fill")
                    }
                    .disabled(!locationService.isLocationAvailable)
                }
            }
            .alert("Geofence Creado", isPresented: $showSaveConfirmation) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("'\(name)' está ahora activo. Recibirás notificaciones cuando familiares entren o salgan.")
            }
        }
        .onAppear {
            centerOnUser()
            debugMapState()
        }
    }

    private var canSave: Bool {
        !name.isEmpty && selectedCoordinate != nil
    }

    private func centerOnUser() {
        guard let location = locationService.currentLocation else {
            print("⚠️ GeofenceCreator: No location available, using default (Estadio Azteca)")
            return
        }

        withAnimation {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: location.latitude,
                    longitude: location.longitude
                ),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)  // More zoom for better precision
            )
        }

        print("📍 GeofenceCreator: Centered map on user location: \(location.latitude), \(location.longitude)")
    }

    private func saveGeofence() {
        guard let coordinate = selectedCoordinate else { return }

        geofenceManager.createGeofence(
            name: name,
            center: coordinate,
            radius: radius,
            shareWithFamily: shareWithFamily
        )

        showSaveConfirmation = true
    }

    private func debugMapState() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🗺️ GEOFENCE CREATOR VIEW APPEARED")
        print("   Region Center: \(region.center.latitude), \(region.center.longitude)")
        print("   Region Span: \(region.span.latitudeDelta), \(region.span.longitudeDelta)")
        print("   Location Available: \(locationService.isLocationAvailable)")
        if let loc = locationService.currentLocation {
            print("   Current Location: \(loc.latitude), \(loc.longitude)")
        } else {
            print("   Current Location: nil")
        }
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

// MARK: - Map Editor Component
struct GeofenceMapEditor: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var selectedCoordinate: CLLocationCoordinate2D?
    @Binding var radius: Double

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator

        // Enhanced visual configuration
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.mapType = .standard

        // Enable map interaction
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false

        mapView.setRegion(region, animated: false)

        // Add TAP gesture for quick pin placement
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(tapGesture)

        // Add LONG PRESS gesture as alternative
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delegate = context.coordinator
        mapView.addGestureRecognizer(longPress)

        print("🗺️ GeofenceMapEditor: Created with tap and long press gestures")

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update overlays and annotations when radius or coordinate changes
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)

        if let coordinate = selectedCoordinate {
            // Add pin annotation
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            annotation.title = "Centro del Geofence"
            annotation.subtitle = "Radio: \(Int(radius))m"
            mapView.addAnnotation(annotation)

            // Add circle overlay
            let circle = MKCircle(center: coordinate, radius: radius)
            mapView.addOverlay(circle)

            print("📍 GeofenceMapEditor: Updated annotation at \(coordinate.latitude), \(coordinate.longitude) with radius \(Int(radius))m")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: GeofenceMapEditor

        init(_ parent: GeofenceMapEditor) {
            self.parent = parent
        }

        // MARK: - UIGestureRecognizerDelegate

        /// Allow simultaneous gesture recognition so map pan/zoom still works
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        // MARK: - Gesture Handlers

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let mapView = gesture.view as! MKMapView
            let touchPoint = gesture.location(in: mapView)
            let coordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)

            DispatchQueue.main.async {
                self.parent.selectedCoordinate = coordinate
            }

            // Haptic feedback
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            print("📍 GeofenceMapEditor: TAP at \(coordinate.latitude), \(coordinate.longitude)")
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }

            let mapView = gesture.view as! MKMapView
            let touchPoint = gesture.location(in: mapView)
            let coordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)

            DispatchQueue.main.async {
                self.parent.selectedCoordinate = coordinate
            }

            // Stronger haptic feedback for long press
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

            print("📍 GeofenceMapEditor: LONG PRESS at \(coordinate.latitude), \(coordinate.longitude)")
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.2)
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

            let identifier = "GeofencePin"

            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
            } else {
                annotationView?.annotation = annotation
            }

            annotationView?.markerTintColor = .systemBlue
            annotationView?.glyphImage = UIImage(systemName: "mappin.circle.fill")

            return annotationView
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.async {
                self.parent.region = mapView.region
            }
        }
    }
}
