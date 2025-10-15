import Foundation
#if canImport(UIKit)
import UIKit
#endif
import MultipeerConnectivity
import Combine
import os

/// Manages intelligent backoff strategies based on context and history
class AdaptiveBackoffManager: ObservableObject {

    // MARK: - Types

    struct ConnectionContext: Hashable, Codable {
        let timeOfDay: TimeOfDayCategory
        let peerDensity: DensityCategory
        let batteryLevel: BatteryCategory
        let networkMode: String
        let failureCount: Int

        enum TimeOfDayCategory: String, Codable {
            case earlyMorning  // 00:00 - 06:00
            case morning       // 06:00 - 12:00
            case afternoon     // 12:00 - 18:00
            case evening       // 18:00 - 00:00

            init(hour: Int) {
                switch hour {
                case 0..<6: self = .earlyMorning
                case 6..<12: self = .morning
                case 12..<18: self = .afternoon
                default: self = .evening
                }
            }
        }

        enum DensityCategory: String, Codable {
            case sparse   // 0-2 peers
            case moderate // 3-5 peers
            case dense    // 6-10 peers
            case crowded  // 11+ peers

            init(peerCount: Int) {
                switch peerCount {
                case 0...2: self = .sparse
                case 3...5: self = .moderate
                case 6...10: self = .dense
                default: self = .crowded
                }
            }
        }

        enum BatteryCategory: String, Codable {
            case critical  // < 10%
            case low       // 10-30%
            case moderate  // 30-70%
            case high      // > 70%

            init(level: Float) {
                switch level {
                case 0..<0.1: self = .critical
                case 0.1..<0.3: self = .low
                case 0.3..<0.7: self = .moderate
                default: self = .high
                }
            }
        }
    }

    struct BackoffStrategy: Codable {
        var baseDelay: TimeInterval
        var multiplier: Double
        var maxDelay: TimeInterval
        var jitterRange: Double  // 0.0 to 1.0
        var successRate: Float = 0.0
        var attemptCount: Int = 0
        var successCount: Int = 0

        static let aggressive = BackoffStrategy(
            baseDelay: 0.5,
            multiplier: 1.5,
            maxDelay: 10.0,
            jitterRange: 0.2
        )

        static let standard = BackoffStrategy(
            baseDelay: 2.0,
            multiplier: 2.0,
            maxDelay: 30.0,
            jitterRange: 0.3
        )

        static let conservative = BackoffStrategy(
            baseDelay: 5.0,
            multiplier: 2.5,
            maxDelay: 60.0,
            jitterRange: 0.4
        )

        static let powerSaving = BackoffStrategy(
            baseDelay: 10.0,
            multiplier: 3.0,
            maxDelay: 120.0,
            jitterRange: 0.5
        )

        mutating func recordAttempt(success: Bool) {
            attemptCount += 1
            if success {
                successCount += 1
            }
            successRate = Float(successCount) / Float(attemptCount)
        }

        func calculateDelay(for attemptNumber: Int) -> TimeInterval {
            // Base exponential calculation
            let exponentialDelay = baseDelay * pow(multiplier, Double(min(attemptNumber - 1, 10)))
            let clampedDelay = min(exponentialDelay, maxDelay)

            // Add jitter to prevent synchronization
            let jitter = Double.random(in: -jitterRange...jitterRange) * clampedDelay
            let finalDelay = max(0.1, clampedDelay + jitter)

            return finalDelay
        }
    }

    // MARK: - Properties

    @Published private(set) var currentStrategy: BackoffStrategy = .standard
    @Published private(set) var isAdapting: Bool = false

    private var successHistory: [ConnectionContext: BackoffStrategy] = [:]
    private var peerSpecificStrategies: [String: BackoffStrategy] = [:]
    private var recentAttempts: [(context: ConnectionContext, success: Bool, timestamp: Date)] = []

    private let queue = DispatchQueue(label: "com.meshred.backoff", attributes: .concurrent)
    private let maxHistorySize = 100
    private let learningThreshold = 10  // Minimum attempts before adapting

    // Persistence
    private let historyKey = "BackoffSuccessHistory"

    // MARK: - Initialization

    init() {
        loadHistory()
    }

    // MARK: - Strategy Selection

    func selectStrategy(
        for peer: MCPeerID,
        nearbyPeers: Int,
        failureCount: Int,
        networkMode: String = "standard"
    ) -> BackoffStrategy {

        let context = createContext(
            nearbyPeers: nearbyPeers,
            failureCount: failureCount,
            networkMode: networkMode
        )

        return queue.sync {
            // Check peer-specific strategy first
            if let peerStrategy = peerSpecificStrategies[peer.displayName],
               peerStrategy.attemptCount >= learningThreshold {
                print("📊 Using peer-specific strategy for \(peer.displayName)")
                return adaptStrategy(peerStrategy, for: context)
            }

            // Check historical success for similar context
            if let historicalStrategy = successHistory[context],
               historicalStrategy.attemptCount >= learningThreshold {
                print("📊 Using historical strategy for context")
                return adaptStrategy(historicalStrategy, for: context)
            }

            // Default strategy based on context
            return selectDefaultStrategy(for: context)
        }
    }

    func calculateBackoff(
        attemptNumber: Int,
        for peer: MCPeerID,
        nearbyPeers: Int,
        failureCount: Int
    ) -> TimeInterval {

        let strategy = selectStrategy(
            for: peer,
            nearbyPeers: nearbyPeers,
            failureCount: failureCount
        )

        let delay = strategy.calculateDelay(for: attemptNumber)

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("⏰ ADAPTIVE BACKOFF CALCULATION")
        print("   Peer: \(peer.displayName)")
        print("   Attempt: #\(attemptNumber)")
        print("   Strategy: base=\(strategy.baseDelay)s, mult=\(strategy.multiplier)")
        print("   Delay: \(String(format: "%.1f", delay))s")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        return delay
    }

    // MARK: - Context Creation

    private func createContext(
        nearbyPeers: Int,
        failureCount: Int,
        networkMode: String
    ) -> ConnectionContext {

        let hour = Calendar.current.component(.hour, from: Date())

        #if canImport(UIKit)
        let batteryLevel = UIDevice.current.batteryLevel
        #else
        let batteryLevel: Float = 1.0  // Assume full battery on non-iOS platforms
        #endif

        return ConnectionContext(
            timeOfDay: ConnectionContext.TimeOfDayCategory(hour: hour),
            peerDensity: ConnectionContext.DensityCategory(peerCount: nearbyPeers),
            batteryLevel: ConnectionContext.BatteryCategory(level: batteryLevel),
            networkMode: networkMode,
            failureCount: min(failureCount, 10)  // Cap for grouping
        )
    }

    // MARK: - Strategy Adaptation

    private func adaptStrategy(_ base: BackoffStrategy, for context: ConnectionContext) -> BackoffStrategy {
        var adapted = base

        // Adapt based on time of day
        switch context.timeOfDay {
        case .earlyMorning:
            // Less aggressive at night
            adapted.baseDelay *= 1.5
        case .morning, .afternoon:
            // Normal activity hours
            break
        case .evening:
            // Slightly more aggressive for peak usage
            adapted.baseDelay *= 0.8
        }

        // Adapt based on density
        switch context.peerDensity {
        case .sparse:
            // More aggressive when few peers
            adapted.baseDelay *= 0.7
            adapted.multiplier = max(1.5, adapted.multiplier - 0.3)
        case .moderate:
            // Standard behavior
            break
        case .dense:
            // More conservative to avoid collisions
            adapted.baseDelay *= 1.3
            adapted.multiplier += 0.2
        case .crowded:
            // Very conservative in crowds
            adapted.baseDelay *= 2.0
            adapted.multiplier += 0.5
        }

        // Adapt based on battery
        switch context.batteryLevel {
        case .critical:
            // Extreme power saving
            adapted.baseDelay *= 3.0
            adapted.maxDelay = min(300, adapted.maxDelay * 2)
        case .low:
            // Conservative power usage
            adapted.baseDelay *= 1.5
        case .moderate, .high:
            // Normal operation
            break
        }

        // Adapt based on failure count
        if context.failureCount > 5 {
            // Increasingly conservative with failures
            let failureFactor = Double(context.failureCount - 5) * 0.2
            adapted.baseDelay *= (1.0 + failureFactor)
        }

        return adapted
    }

    private func selectDefaultStrategy(for context: ConnectionContext) -> BackoffStrategy {
        // Battery critical - always power saving
        if context.batteryLevel == .critical {
            return .powerSaving
        }

        // Dense network - conservative
        if context.peerDensity == .crowded {
            return .conservative
        }

        // Many failures - conservative
        if context.failureCount > 7 {
            return .conservative
        }

        // Sparse network with good battery - aggressive
        if context.peerDensity == .sparse && context.batteryLevel == .high {
            return .aggressive
        }

        // Default to standard
        return .standard
    }

    // MARK: - Learning

    func recordAttempt(
        for peer: MCPeerID,
        success: Bool,
        context: ConnectionContext,
        strategy: BackoffStrategy
    ) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // Update peer-specific strategy
            var peerStrategy = self.peerSpecificStrategies[peer.displayName] ?? strategy
            peerStrategy.recordAttempt(success: success)
            self.peerSpecificStrategies[peer.displayName] = peerStrategy

            // Update context-specific strategy
            var contextStrategy = self.successHistory[context] ?? strategy
            contextStrategy.recordAttempt(success: success)
            self.successHistory[context] = contextStrategy

            // Record recent attempt
            self.recentAttempts.append((context, success, Date()))

            // Limit history size
            if self.recentAttempts.count > self.maxHistorySize {
                self.recentAttempts.removeFirst()
            }

            // Trigger adaptation if enough data
            if self.recentAttempts.count >= self.learningThreshold {
                self.adaptFromHistory()
            }

            self.saveHistory()
        }
    }

    private func adaptFromHistory() {
        // Analyze recent success patterns
        let recentWindow = 20
        let recent = Array(recentAttempts.suffix(recentWindow))

        guard !recent.isEmpty else { return }

        let successRate = Float(recent.filter { $0.success }.count) / Float(recent.count)

        DispatchQueue.main.async { [weak self] in
            self?.isAdapting = true
        }

        // Adjust future strategies based on success rate
        if successRate > 0.7 {
            // High success - can be more aggressive
            print("📈 High success rate (\(successRate)): Adjusting to more aggressive backoff")
            adjustStrategies(factor: 0.8)
        } else if successRate < 0.3 {
            // Low success - be more conservative
            print("📉 Low success rate (\(successRate)): Adjusting to more conservative backoff")
            adjustStrategies(factor: 1.5)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isAdapting = false
        }
    }

    private func adjustStrategies(factor: Double) {
        // Adjust all stored strategies based on learning
        for key in successHistory.keys {
            if var strategy = successHistory[key] {
                strategy.baseDelay *= factor
                strategy.baseDelay = max(0.1, min(60, strategy.baseDelay))
                successHistory[key] = strategy
            }
        }
    }

    // MARK: - Analytics

    func getSuccessRate(for peer: MCPeerID) -> Float? {
        return queue.sync {
            return peerSpecificStrategies[peer.displayName]?.successRate
        }
    }

    func getAverageSuccessRate() -> Float {
        return queue.sync {
            let strategies = Array(successHistory.values) + Array(peerSpecificStrategies.values)
            guard !strategies.isEmpty else { return 0 }

            let totalSuccess = strategies.reduce(0) { $0 + $1.successCount }
            let totalAttempts = strategies.reduce(0) { $0 + $1.attemptCount }

            guard totalAttempts > 0 else { return 0 }
            return Float(totalSuccess) / Float(totalAttempts)
        }
    }

    func getMostSuccessfulContext() -> ConnectionContext? {
        return queue.sync {
            return successHistory.max { $0.value.successRate < $1.value.successRate }?.key
        }
    }

    // MARK: - Management

    func reset() {
        queue.async(flags: .barrier) { [weak self] in
            self?.successHistory.removeAll()
            self?.peerSpecificStrategies.removeAll()
            self?.recentAttempts.removeAll()
            self?.saveHistory()
        }

        DispatchQueue.main.async { [weak self] in
            self?.currentStrategy = .standard
        }

        print("🔄 Backoff manager reset to defaults")
    }

    func forgetPeer(_ peerId: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.peerSpecificStrategies.removeValue(forKey: peerId)
        }
    }

    // MARK: - Persistence

    private func saveHistory() {
        let encoder = JSONEncoder()

        // Save success history
        if let encoded = try? encoder.encode(successHistory) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }

        // Save peer strategies
        if let encoded = try? encoder.encode(peerSpecificStrategies) {
            UserDefaults.standard.set(encoded, forKey: "\(historyKey).peers")
        }
    }

    private func loadHistory() {
        let decoder = JSONDecoder()

        // Load success history
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? decoder.decode([ConnectionContext: BackoffStrategy].self, from: data) {
            queue.async(flags: .barrier) { [weak self] in
                self?.successHistory = decoded
                print("📊 Loaded backoff history with \(decoded.count) contexts")
            }
        }

        // Load peer strategies
        if let data = UserDefaults.standard.data(forKey: "\(historyKey).peers"),
           let decoded = try? decoder.decode([String: BackoffStrategy].self, from: data) {
            queue.async(flags: .barrier) { [weak self] in
                self?.peerSpecificStrategies = decoded
                print("📊 Loaded peer-specific strategies for \(decoded.count) peers")
            }
        }
    }
}

// MARK: - Helpers

extension AdaptiveBackoffManager {

    func shouldRetry(attemptNumber: Int, maxAttempts: Int) -> Bool {
        // Could implement more sophisticated logic here
        return attemptNumber < maxAttempts
    }

    func getRecommendedMaxAttempts(for context: ConnectionContext) -> Int {
        switch context.batteryLevel {
        case .critical: return 3
        case .low: return 5
        case .moderate: return 7
        case .high: return 10
        }
    }
}