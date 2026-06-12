import Foundation

public final class AudioRingBuffer {
    private var storage: [Float]
    private var writeIndex = 0
    private var filledCount = 0
    private let lock = NSLock()

    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = Array(repeating: 0, count: max(1, capacity))
    }

    public func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.lock()
        for sample in samples {
            storage[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            filledCount = min(capacity, filledCount + 1)
        }
        lock.unlock()
    }

    public func latest(_ count: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        let requested = min(max(0, count), filledCount)
        guard requested > 0 else { return [] }

        var output = Array(repeating: Float(0), count: requested)
        let start = (writeIndex - requested + capacity) % capacity
        for index in 0..<requested {
            output[index] = storage[(start + index) % capacity]
        }
        return output
    }

    public func clear() {
        lock.lock()
        storage = Array(repeating: 0, count: capacity)
        writeIndex = 0
        filledCount = 0
        lock.unlock()
    }
}
