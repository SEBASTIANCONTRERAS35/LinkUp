import Foundation

class MessageQueue {
    private var heap: [NetworkMessage] = []
    private var maxSize: Int {
        // Dynamic queue size based on network mode
        return NetworkConfig.shared.networkMode.messageQueueSize
    }
    private let queue = DispatchQueue(label: "com.meshred.messagequeue", attributes: .concurrent)

    var count: Int {
        queue.sync {
            return heap.count
        }
    }

    var isEmpty: Bool {
        queue.sync {
            return heap.isEmpty
        }
    }

    func enqueue(_ message: NetworkMessage) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            if self.heap.count >= self.maxSize {
                if let lowestPriorityIndex = self.findLowestPriorityIndex() {
                    let lowestPriority = self.heap[lowestPriorityIndex].priority
                    if message.priority < lowestPriority {
                        self.heap.remove(at: lowestPriorityIndex)
                        self.insertMessage(message)
                        print("📥 Cola llena: Reemplazando mensaje de prioridad \(lowestPriority) con mensaje de prioridad \(message.priority)")
                    } else {
                        print("⚠️ Cola llena: Descartando mensaje de prioridad \(message.priority)")
                    }
                }
            } else {
                self.insertMessage(message)
                print("📥 Mensaje encolado - Tipo: \(message.messageType.displayName), Prioridad: \(message.priority), Cola: \(self.heap.count)/\(self.maxSize)")
            }
        }
    }

    private func insertMessage(_ message: NetworkMessage) {
        heap.append(message)
        bubbleUp(heap.count - 1)
    }

    func dequeue() -> NetworkMessage? {
        queue.sync {
            guard !heap.isEmpty else { return nil }

            if heap.count == 1 {
                return heap.removeLast()
            }

            let message = heap[0]
            heap[0] = heap.removeLast()
            bubbleDown(0)

            print("📤 Mensaje desencolado - Tipo: \(message.messageType.displayName), Prioridad: \(message.priority), Cola restante: \(heap.count)")
            return message
        }
    }

    func peek() -> NetworkMessage? {
        queue.sync {
            return heap.first
        }
    }

    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?.heap.removeAll()
            print("🗑️ Cola de mensajes limpiada")
        }
    }

    func getQueueStatus() -> [(MessageType, Int)] {
        queue.sync {
            var statusDict: [MessageType: Int] = [:]
            for message in heap {
                statusDict[message.messageType, default: 0] += 1
            }
            return Array(statusDict).sorted { $0.key.defaultPriority < $1.key.defaultPriority }
        }
    }

    private func bubbleUp(_ index: Int) {
        var childIndex = index
        let childMessage = heap[childIndex]

        while childIndex > 0 {
            let parentIndex = (childIndex - 1) / 2
            let parentMessage = heap[parentIndex]

            if compareMessages(childMessage, parentMessage) {
                heap[childIndex] = parentMessage
                childIndex = parentIndex
            } else {
                break
            }
        }

        heap[childIndex] = childMessage
    }

    private func bubbleDown(_ index: Int) {
        var parentIndex = index
        let parentMessage = heap[parentIndex]

        while true {
            let leftChildIndex = 2 * parentIndex + 1
            let rightChildIndex = leftChildIndex + 1
            var candidateIndex = parentIndex

            if leftChildIndex < heap.count && compareMessages(heap[leftChildIndex], heap[candidateIndex]) {
                candidateIndex = leftChildIndex
            }

            if rightChildIndex < heap.count && compareMessages(heap[rightChildIndex], heap[candidateIndex]) {
                candidateIndex = rightChildIndex
            }

            if candidateIndex == parentIndex {
                break
            }

            heap[parentIndex] = heap[candidateIndex]
            parentIndex = candidateIndex
        }

        heap[parentIndex] = parentMessage
    }

    private func compareMessages(_ msg1: NetworkMessage, _ msg2: NetworkMessage) -> Bool {
        if msg1.priority != msg2.priority {
            return msg1.priority < msg2.priority
        }
        return msg1.timestamp < msg2.timestamp
    }

    private func findLowestPriorityIndex() -> Int? {
        guard !heap.isEmpty else { return nil }

        var lowestIndex = 0
        var lowestPriority = heap[0].priority

        for i in 1..<heap.count {
            if heap[i].priority > lowestPriority {
                lowestPriority = heap[i].priority
                lowestIndex = i
            }
        }

        return lowestIndex
    }
}