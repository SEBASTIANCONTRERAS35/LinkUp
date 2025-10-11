import Foundation
import MultipeerConnectivity
import Combine

/// Manages connection slots with intelligent prioritization
class ConnectionPoolManager: ObservableObject {

    // MARK: - Types

    enum ConnectionPriority: Int, CaseIterable, Comparable {
        case critical = 0    // Emergency, Family
        case high = 1       // Close friends, Important services
        case normal = 2     // Regular peers
        case low = 3        // Discovery, Optional connections

        static func < (lhs: ConnectionPriority, rhs: ConnectionPriority) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

        var displayName: String {
            switch self {
            case .critical: return "Crítica"
            case .high: return "Alta"
            case .normal: return "Normal"
            case .low: return "Baja"
            }
        }

        var color: String {
            switch self {
            case .critical: return "🔴"
            case .high: return "🟡"
            case .normal: return "🟢"
            case .low: return "⚪"
            }
        }
    }

    struct ConnectionSlot {
        let id: UUID = UUID()
        let priority: ConnectionPriority
        var peer: MCPeerID?
        var reservedFor: String?  // Can reserve slot for specific peer
        var connectedAt: Date?
        var lastActivity: Date?
        let timeout: TimeInterval

        var isAvailable: Bool {
            return peer == nil && reservedFor == nil
        }

        var isReserved: Bool {
            return reservedFor != nil && peer == nil
        }

        var isOccupied: Bool {
            return peer != nil
        }

        var connectionDuration: TimeInterval? {
            guard let connectedAt = connectedAt else { return nil }
            return Date().timeIntervalSince(connectedAt)
        }

        var idleTime: TimeInterval? {
            guard let lastActivity = lastActivity else { return nil }
            return Date().timeIntervalSince(lastActivity)
        }

        mutating func occupy(with peer: MCPeerID) {
            self.peer = peer
            self.connectedAt = Date()
            self.lastActivity = Date()
            self.reservedFor = nil  // Clear reservation
        }

        mutating func release() {
            self.peer = nil
            self.connectedAt = nil
            self.lastActivity = nil
            // Keep reservation if it exists
        }

        mutating func updateActivity() {
            self.lastActivity = Date()
        }
    }

    // MARK: - Properties

    @Published private(set) var slots: [ConnectionSlot] = []
    @Published private(set) var totalCapacity: Int = 5
    @Published private(set) var occupiedSlots: Int = 0
    @Published private(set) var reservedSlots: Int = 0

    private let maxConnections: Int
    private var slotConfiguration: [ConnectionPriority: Int] = [:]
    private var peerPriorities: [String: ConnectionPriority] = [:]
    private let queue = DispatchQueue(label: "com.meshred.connectionpool", attributes: .concurrent)

    // Monitoring
    private var monitorTimer: Timer?
    private let monitorInterval: TimeInterval = 10.0

    // MARK: - Initialization

    init(maxConnections: Int = 5) {
        self.maxConnections = maxConnections
        self.totalCapacity = maxConnections
        configureSlots()
        startMonitoring()
    }

    deinit {
        monitorTimer?.invalidate()
    }

    // MARK: - Configuration

    private func configureSlots() {
        // Default configuration based on max connections
        switch maxConnections {
        case 1...2:
            slotConfiguration = [
                .critical: 1,
                .high: maxConnections - 1
            ]
        case 3...4:
            slotConfiguration = [
                .critical: 1,
                .high: 1,
                .normal: maxConnections - 2
            ]
        default:  // 5+
            slotConfiguration = [
                .critical: 2,
                .high: 1,
                .normal: 1,
                .low: maxConnections - 4
            ]
        }

        rebuildSlots()
    }

    func customizeConfiguration(_ config: [ConnectionPriority: Int]) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let totalConfigured = config.values.reduce(0, +)
            guard totalConfigured <= self.maxConnections else {
                print("❌ Invalid configuration: total slots exceed max connections")
                return
            }

            self.slotConfiguration = config
            self.rebuildSlots()
        }
    }

    private func rebuildSlots() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            var newSlots: [ConnectionSlot] = []

            // Create slots based on configuration
            for priority in ConnectionPriority.allCases {
                let count = self.slotConfiguration[priority] ?? 0
                for _ in 0..<count {
                    let timeout: TimeInterval
                    switch priority {
                    case .critical: timeout = 300  // 5 minutes
                    case .high: timeout = 120      // 2 minutes
                    case .normal: timeout = 60     // 1 minute
                    case .low: timeout = 30        // 30 seconds
                    }

                    newSlots.append(ConnectionSlot(
                        priority: priority,
                        peer: nil,
                        reservedFor: nil,
                        connectedAt: nil,
                        lastActivity: nil,
                        timeout: timeout
                    ))
                }
            }

            // Migrate existing connections to new slots
            for oldSlot in self.slots where oldSlot.isOccupied {
                if let newSlotIndex = newSlots.firstIndex(where: {
                    $0.priority == oldSlot.priority && $0.isAvailable
                }) {
                    newSlots[newSlotIndex] = oldSlot
                } else if let anySlotIndex = newSlots.firstIndex(where: { $0.isAvailable }) {
                    // Fallback to any available slot
                    var migratedSlot = newSlots[anySlotIndex]
                    migratedSlot.peer = oldSlot.peer
                    migratedSlot.connectedAt = oldSlot.connectedAt
                    migratedSlot.lastActivity = oldSlot.lastActivity
                    newSlots[anySlotIndex] = migratedSlot
                }
            }

            DispatchQueue.main.async {
                self.slots = newSlots
                self.updateCounts()
            }
        }
    }

    // MARK: - Slot Management

    func requestSlot(for peer: MCPeerID, priority: ConnectionPriority) -> ConnectionSlot? {
        return queue.sync(flags: .barrier) {
            // Check if peer already has a slot
            if let existingSlotIndex = slots.firstIndex(where: { $0.peer?.displayName == peer.displayName }) {
                print("✅ Peer \(peer.displayName) already has slot")
                return slots[existingSlotIndex]
            }

            // Try to find slot of requested priority
            if let slotIndex = findAvailableSlot(priority: priority) {
                slots[slotIndex].occupy(with: peer)
                peerPriorities[peer.displayName] = priority
                updateCounts()

                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("🎰 SLOT ALLOCATED")
                print("   Peer: \(peer.displayName)")
                print("   Priority: \(priority.color) \(priority.displayName)")
                print("   Slot: \(slotIndex + 1)/\(totalCapacity)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                return slots[slotIndex]
            }

            // Try to evict lower priority connection
            if let evictableSlotIndex = findEvictableSlot(for: priority) {
                let evictedPeer = slots[evictableSlotIndex].peer
                slots[evictableSlotIndex].release()

                // Notify about eviction
                if let evicted = evictedPeer {
                    NotificationCenter.default.post(
                        name: .connectionEvicted,
                        object: nil,
                        userInfo: ["peer": evicted, "reason": "priority"]
                    )
                }

                // Occupy the slot
                slots[evictableSlotIndex].occupy(with: peer)
                peerPriorities[peer.displayName] = priority
                updateCounts()

                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("⚡ SLOT ALLOCATED (WITH EVICTION)")
                print("   New Peer: \(peer.displayName)")
                print("   Evicted: \(evictedPeer?.displayName ?? "none")")
                print("   Priority: \(priority.color) \(priority.displayName)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

                return slots[evictableSlotIndex]
            }

            print("❌ No available slot for \(peer.displayName) with priority \(priority.displayName)")
            return nil
        }
    }

    func releaseSlot(for peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            if let slotIndex = self.slots.firstIndex(where: { $0.peer?.displayName == peer.displayName }) {
                self.slots[slotIndex].release()
                self.peerPriorities.removeValue(forKey: peer.displayName)
                self.updateCounts()

                print("🎰 Slot released for \(peer.displayName)")
            }
        }
    }

    func reserveSlot(for peerId: String, priority: ConnectionPriority, duration: TimeInterval = 10.0) -> Bool {
        return queue.sync(flags: .barrier) {
            if let slotIndex = findAvailableSlot(priority: priority) {
                slots[slotIndex].reservedFor = peerId

                // Auto-release reservation after duration
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                    self?.clearReservation(for: peerId)
                }

                updateCounts()
                print("📌 Slot reserved for \(peerId) for \(duration)s")
                return true
            }
            return false
        }
    }

    func clearReservation(for peerId: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            if let slotIndex = self.slots.firstIndex(where: { $0.reservedFor == peerId }) {
                self.slots[slotIndex].reservedFor = nil
                self.updateCounts()
                print("📌 Reservation cleared for \(peerId)")
            }
        }
    }

    // MARK: - Slot Finding

    private func findAvailableSlot(priority: ConnectionPriority) -> Int? {
        // First try exact priority match
        if let index = slots.firstIndex(where: { $0.priority == priority && $0.isAvailable }) {
            return index
        }

        // Then try higher priority slots (if allowed)
        for higherPriority in ConnectionPriority.allCases where higherPriority < priority {
            if let index = slots.firstIndex(where: { $0.priority == higherPriority && $0.isAvailable }) {
                return index
            }
        }

        // Finally try lower priority slots
        for lowerPriority in ConnectionPriority.allCases where lowerPriority > priority {
            if let index = slots.firstIndex(where: { $0.priority == lowerPriority && $0.isAvailable }) {
                return index
            }
        }

        return nil
    }

    private func findEvictableSlot(for priority: ConnectionPriority) -> Int? {
        // Can only evict lower priority connections
        for lowerPriority in ConnectionPriority.allCases.reversed() where lowerPriority > priority {
            // Find oldest connection of this priority
            let slotsOfPriority = slots.enumerated()
                .filter { $0.element.priority == lowerPriority && $0.element.isOccupied }
                .sorted { (slot1, slot2) in
                    let time1 = slot1.element.connectedAt ?? Date.distantFuture
                    let time2 = slot2.element.connectedAt ?? Date.distantFuture
                    return time1 < time2  // Older connections first
                }

            if let evictable = slotsOfPriority.first {
                return evictable.offset
            }
        }
        return nil
    }

    // MARK: - Activity Tracking

    func recordActivity(for peer: MCPeerID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            if let slotIndex = self.slots.firstIndex(where: { $0.peer?.displayName == peer.displayName }) {
                self.slots[slotIndex].updateActivity()
            }
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        monitorTimer = Timer.scheduledTimer(withTimeInterval: monitorInterval, repeats: true) { [weak self] _ in
            self?.checkIdleConnections()
        }
    }

    private func checkIdleConnections() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let now = Date()

            for (index, slot) in self.slots.enumerated() {
                guard slot.isOccupied,
                      let lastActivity = slot.lastActivity else { continue }

                let idleTime = now.timeIntervalSince(lastActivity)

                if idleTime > slot.timeout {
                    print("⏰ Idle timeout for \(slot.peer?.displayName ?? "unknown")")

                    // Notify about idle timeout
                    if let peer = slot.peer {
                        NotificationCenter.default.post(
                            name: .connectionIdleTimeout,
                            object: nil,
                            userInfo: ["peer": peer, "idleTime": idleTime]
                        )
                    }

                    // Don't auto-disconnect critical connections
                    if slot.priority != .critical {
                        self.slots[index].release()
                        self.updateCounts()
                    }
                }
            }
        }
    }

    // MARK: - Status

    private func updateCounts() {
        occupiedSlots = slots.filter { $0.isOccupied }.count
        reservedSlots = slots.filter { $0.isReserved }.count
    }

    func getStatus() -> (occupied: Int, reserved: Int, available: Int) {
        return queue.sync {
            let occupied = slots.filter { $0.isOccupied }.count
            let reserved = slots.filter { $0.isReserved }.count
            let available = slots.filter { $0.isAvailable }.count
            return (occupied, reserved, available)
        }
    }

    func getSlotInfo() -> [(priority: ConnectionPriority, peer: String?, duration: TimeInterval?)] {
        return queue.sync {
            return slots.map { slot in
                (slot.priority, slot.peer?.displayName, slot.connectionDuration)
            }
        }
    }

    func hasAvailableSlot(for priority: ConnectionPriority) -> Bool {
        return queue.sync {
            return findAvailableSlot(priority: priority) != nil ||
                   findEvictableSlot(for: priority) != nil
        }
    }

    func canAcceptPeer(_ peer: MCPeerID, withPriority priority: ConnectionPriority) -> Bool {
        return queue.sync {
            // Already connected?
            if slots.contains(where: { $0.peer?.displayName == peer.displayName }) {
                return true
            }

            // Can allocate new slot?
            return hasAvailableSlot(for: priority)
        }
    }

    // MARK: - Priority Management

    func updatePriority(for peer: MCPeerID, to newPriority: ConnectionPriority) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            self.peerPriorities[peer.displayName] = newPriority

            // If connected, might need to move to different slot
            if let currentSlotIndex = self.slots.firstIndex(where: { $0.peer?.displayName == peer.displayName }) {
                let currentSlot = self.slots[currentSlotIndex]

                if currentSlot.priority != newPriority {
                    // Try to find better slot
                    if let betterSlotIndex = self.findAvailableSlot(priority: newPriority) {
                        // Create new slot with updated priority
                        var newSlot = self.slots[betterSlotIndex]
                        newSlot.occupy(with: peer)
                        self.slots[betterSlotIndex] = newSlot
                        self.slots[currentSlotIndex].release()

                        print("📊 Moved \(peer.displayName) to \(newPriority.displayName) priority slot")
                    }
                }
            }
        }
    }

    func getPriority(for peer: MCPeerID) -> ConnectionPriority {
        return queue.sync {
            return peerPriorities[peer.displayName] ?? .normal
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let connectionEvicted = Notification.Name("ConnectionEvicted")
    static let connectionIdleTimeout = Notification.Name("ConnectionIdleTimeout")
    static let slotReserved = Notification.Name("SlotReserved")
    static let slotReleased = Notification.Name("SlotReleased")
}