import Foundation

class MessageCache {
    private var cache: [UUID: Date] = [:]
    private let maxCacheSize = 500
    private let cacheExpirationTime: TimeInterval = 300
    private let queue = DispatchQueue(label: "com.meshred.messagecache", attributes: .concurrent)
    private var cleanupTimer: Timer?

    init() {
        startCleanupTimer()
    }

    deinit {
        cleanupTimer?.invalidate()
    }

    func hasSeenMessage(_ messageId: UUID) -> Bool {
        queue.sync {
            if let seenDate = cache[messageId] {
                let isExpired = Date().timeIntervalSince(seenDate) > cacheExpirationTime
                if isExpired {
                    return false
                }
                print("🔁 Mensaje duplicado detectado: \(messageId)")
                return true
            }
            return false
        }
    }

    func markMessageAsSeen(_ messageId: UUID) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            self.cache[messageId] = Date()

            if self.cache.count > self.maxCacheSize {
                self.pruneOldestEntries()
            }

            print("✅ Mensaje marcado como visto: \(messageId) - Cache: \(self.cache.count)/\(self.maxCacheSize)")
        }
    }

    func shouldProcessMessage(_ messageId: UUID) -> Bool {
        var shouldProcess = false

        queue.sync(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            if !self.hasSeenMessageInternal(messageId) {
                self.cache[messageId] = Date()
                shouldProcess = true

                if self.cache.count > self.maxCacheSize {
                    self.pruneOldestEntriesInternal()
                }
            }
        }

        return shouldProcess
    }

    private func hasSeenMessageInternal(_ messageId: UUID) -> Bool {
        if let seenDate = cache[messageId] {
            let isExpired = Date().timeIntervalSince(seenDate) > cacheExpirationTime
            return !isExpired
        }
        return false
    }

    private func pruneOldestEntries() {
        let entriesToRemove = cache.count - maxCacheSize + 50

        let sortedEntries = cache.sorted { $0.value < $1.value }
        let keysToRemove = sortedEntries.prefix(entriesToRemove).map { $0.key }

        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }

        print("🧹 Cache podado: Removidos \(keysToRemove.count) mensajes antiguos")
    }

    private func pruneOldestEntriesInternal() {
        let entriesToRemove = cache.count - maxCacheSize + 50

        let sortedEntries = cache.sorted { $0.value < $1.value }
        let keysToRemove = sortedEntries.prefix(entriesToRemove).map { $0.key }

        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
    }

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.cleanupExpiredEntries()
        }
    }

    private func cleanupExpiredEntries() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let now = Date()
            var expiredCount = 0

            self.cache = self.cache.filter { _, seenDate in
                let isExpired = now.timeIntervalSince(seenDate) > self.cacheExpirationTime
                if isExpired { expiredCount += 1 }
                return !isExpired
            }

            if expiredCount > 0 {
                print("🧹 Limpieza automática: Removidos \(expiredCount) mensajes expirados - Cache actual: \(self.cache.count)")
            }
        }
    }

    func getCacheStats() -> (total: Int, oldestMessageAge: TimeInterval?) {
        queue.sync {
            let total = cache.count
            let oldestAge = cache.values.min().map { Date().timeIntervalSince($0) }
            return (total, oldestAge)
        }
    }

    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAll()
            print("🗑️ Cache de mensajes limpiado completamente")
        }
    }

    // MARK: - Route Discovery Support

    /// Check if a string key (like RREQ ID) has been seen
    func contains(_ key: String) -> Bool {
        // Convert string to UUID-like hash for storage
        let hashUUID = UUID(uuidString: key.padding(toLength: 36, withPad: "0", startingAt: 0)) ?? UUID()
        return hasSeenMessage(hashUUID)
    }

    /// Mark a string key (like RREQ ID) as seen
    func add(_ key: String) {
        // Convert string to UUID-like hash for storage
        let hashUUID = UUID(uuidString: key.padding(toLength: 36, withPad: "0", startingAt: 0)) ?? UUID()
        markMessageAsSeen(hashUUID)
    }
}