#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if canImport(Darwin)
  typealias Primitive = os_unfair_lock
#elseif canImport(Glibc)
  typealias Primitive = pthread_mutex_t
#else
  typealias Primitive = Int
#endif

final class LockedBuffer<State>: ManagedBuffer<State, Primitive> {
  deinit {
    _ = self.withUnsafeMutablePointerToElements { lock in
      #if canImport(Darwin)
        lock.deinitialize(count: 1)
      #elseif canImport(Glibc)
        let result = pthread_mutex_destroy(lock)
        precondition(result == 0, "pthread_mutex_destroy failed")
      #endif
    }
  }
}

struct ManagedCriticalState<State> {
  let buffer: ManagedBuffer<State, Primitive>

  init(_ initial: State) {
    buffer = LockedBuffer.create(minimumCapacity: 1) { buffer in
      buffer.withUnsafeMutablePointerToElements { lock in
        #if canImport(Darwin)
          lock.initialize(to: os_unfair_lock())
        #elseif canImport(Glibc)
          let result = pthread_mutex_init(lock, nil)
          precondition(result == 0, "pthread_mutex_init failed")
        #endif
      }
      return initial
    }
  }

  @discardableResult
  func withCriticalRegion<R>(
    _ critical: (inout State) throws -> R
  ) rethrows -> R {
    try buffer.withUnsafeMutablePointers { header, lock in
      #if canImport(Darwin)
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
      #elseif canImport(Glibc)
        pthread_mutex_lock(lock)
        defer {
          let result = pthread_mutex_unlock(lock)
          precondition(result == 0, "pthread_mutex_unlock failed")
        }
      #endif
      return try critical(&header.pointee)
    }
  }

  func apply(criticalState newState: State) {
    self.withCriticalRegion { actual in
      actual = newState
    }
  }

  var criticalState: State {
    self.withCriticalRegion { $0 }
  }
}

extension ManagedCriticalState: @unchecked Sendable where State: Sendable { }
