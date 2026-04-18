import Foundation

/// Observable<T> — 0.3.0 响应式原语(轻量, 基于 AsyncStream)
///
/// BehaviorSubject 语义:
///   - 订阅立即收到当前值
///   - next() 推送新值给所有订阅者
///
/// 用法:
///   let obs = Observable<[Friend]>(initial: [])
///   Task {
///       for await friends in obs.values {
///           render(friends)
///       }
///   }
///   obs.next(newList)
public final class Observable<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    private var continuations: [UUID: AsyncStream<T>.Continuation] = [:]

    public init(initial: T) {
        self._value = initial
    }

    /// 当前值(非订阅读取)
    public var value: T {
        lock.lock(); defer { lock.unlock() }
        return _value
    }

    /// 写入(SDK 内部用)
    public func next(_ newValue: T) {
        lock.lock()
        _value = newValue
        let snapshot = continuations
        lock.unlock()
        for (_, c) in snapshot {
            c.yield(newValue)
        }
    }

    /// 订阅流: 返回 AsyncStream, 立即收到当前值
    public var values: AsyncStream<T> {
        AsyncStream { continuation in
            lock.lock()
            let id = UUID()
            continuations[id] = continuation
            let current = _value
            lock.unlock()

            continuation.yield(current)

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    /// map 派生
    public func map<U: Sendable>(_ transform: @escaping (T) -> U) -> Observable<U> {
        let derived = Observable<U>(initial: transform(value))
        // 订阅自己并把 transform 后值推下去
        Task { [weak derived] in
            for await v in self.values {
                derived?.next(transform(v))
            }
        }
        return derived
    }
}
