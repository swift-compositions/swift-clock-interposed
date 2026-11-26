#if canImport(Darwin)
    import Darwin
    import Synchronization

    // WHY: the replacements below read the clock's state from the first read of uptime in the process, before the
    // Swift runtime has initialized anything lazily and before any thread has thread-local storage. So each value is
    // a global integer with a literal initializer, which the compiler places in the image's data, initialized by
    // the dynamic linker and never through `swift_once`; each is read and written atomically through its address;
    // and none is checked for exclusive access, which would need the runtime and thread-local storage.

    // SAFETY: read and written only atomically through its address, by `load`, `store`, `add` and `claim`, or
    // written before `phase` becomes 2 with release ordering and read only after it is seen as 2 with acquire.
    // 0 while the machine's clock runs through, 1 while a freeze is under way, 2 once frozen.
    @exclusivity(unchecked) nonisolated(unsafe) var phase: UInt64 = 0

    // SAFETY: read and written only atomically through its address, by `load`, `store`, `add` and `claim`, or
    // written before `phase` becomes 2 with release ordering and read only after it is seen as 2 with acquire.
    // The nanoseconds the clock was moved on since it was frozen.
    @exclusivity(unchecked) nonisolated(unsafe) var elapsed: UInt64 = 0

    // SAFETY: read and written only atomically through its address, by `load`, `store`, `add` and `claim`, or
    // written before `phase` becomes 2 with release ordering and read only after it is seen as 2 with acquire.
    // The machine's ticks when the clock was frozen.
    @exclusivity(unchecked) nonisolated(unsafe) var origin: UInt64 = 0

    // SAFETY: read and written only atomically through its address, by `load`, `store`, `add` and `claim`, or
    // written before `phase` becomes 2 with release ordering and read only after it is seen as 2 with acquire.
    // The machine's timebase, nanoseconds per tick as `numerator` over `denominator`.
    @exclusivity(unchecked) nonisolated(unsafe) var numerator: UInt64 = 1
    // SAFETY: as `numerator`.
    @exclusivity(unchecked) nonisolated(unsafe) var denominator: UInt64 = 1

    // SAFETY: read and written only atomically through its address, by `load`, `store`, `add` and `claim`, or
    // written before `phase` becomes 2 with release ordering and read only after it is seen as 2 with acquire.
    // The thread whose next `mach_absolute_time` answers `UInt64.max`, or 0.
    @exclusivity(unchecked) nonisolated(unsafe) var prober: UInt64 = 0

    @inline(__always)
    func load(_ storage: UnsafeMutablePointer<UInt64>) -> UInt64 {
        unsafe UnsafeMutableRawPointer(storage).assumingMemoryBound(to: Atomic<UInt64>.self).pointee.load(ordering: .acquiring)
    }

    @inline(__always)
    func store(_ value: UInt64, _ storage: UnsafeMutablePointer<UInt64>) {
        unsafe UnsafeMutableRawPointer(storage).assumingMemoryBound(to: Atomic<UInt64>.self).pointee.store(value, ordering: .releasing)
    }

    @inline(__always)
    func add(_ value: UInt64, _ storage: UnsafeMutablePointer<UInt64>) {
        _ = unsafe UnsafeMutableRawPointer(storage).assumingMemoryBound(to: Atomic<UInt64>.self).pointee.wrappingAdd(value, ordering: .acquiringAndReleasing)
    }

    @inline(__always)
    func claim(_ storage: UnsafeMutablePointer<UInt64>, from expected: UInt64, to desired: UInt64) -> Bool {
        unsafe UnsafeMutableRawPointer(storage).assumingMemoryBound(to: Atomic<UInt64>.self).pointee
            .compareExchange(expected: expected, desired: desired, ordering: .acquiringAndReleasing).exchanged
    }

    @inline(__always)
    func frozen() -> Bool { unsafe load(&phase) == 2 }

    /// The frozen clock in the machine's ticks: where it was frozen, plus what it was moved on.
    @inline(__always)
    func ticks() -> UInt64 {
        let product = unsafe load(&elapsed).multipliedFullWidth(by: denominator)
        return unsafe origin &+ numerator.dividingFullWidth(product).quotient
    }

    /// Takes the process's clock off the machine's, at the instant the machine's clock reads now. Calling it again,
    /// from any thread, does nothing.
    @c(interposed_clock_freeze)
    func freeze() {
        guard unsafe claim(&phase, from: 0, to: 1) else {
            while unsafe load(&phase) != 2 { sched_yield() }
            return
        }
        var timebase = mach_timebase_info_data_t()
        unsafe mach_timebase_info(&timebase)
        unsafe numerator = UInt64(timebase.numer)
        unsafe denominator = UInt64(timebase.denom)
        unsafe origin = mach_absolute_time()
        unsafe store(0, &elapsed)
        unsafe store(2, &phase)
    }

    /// 1 once the clock is frozen, 0 before.
    @c(interposed_clock_frozen)
    func isFrozen() -> Int32 { frozen() ? 1 : 0 }

    /// Moves the frozen clock on by so many nanoseconds; before the freeze it does nothing.
    @c(interposed_clock_advance)
    func advance(_ nanoseconds: UInt64) {
        guard frozen() else { return }
        unsafe add(nanoseconds, &elapsed)
    }

    /// The nanoseconds the clock was moved on since it was frozen; 0 before.
    @c(interposed_clock_elapsed)
    func moved() -> UInt64 { frozen() ? unsafe load(&elapsed) : 0 }

    /// Makes the calling thread's next `mach_absolute_time` answer `UInt64.max` when, and only when, that call is
    /// routed through this library, so a caller learns whether its own calls are. One thread probes at a time.
    @c(interposed_clock_probe)
    func probe() { unsafe store(UInt64(UInt(bitPattern: pthread_self())), &prober) }

    @c(interposed_clock_mach_absolute_time)
    func absolute() -> UInt64 {
        let probing = unsafe load(&prober)
        if probing != 0, unsafe probing == UInt64(UInt(bitPattern: pthread_self())) {
            unsafe store(0, &prober)
            return .max
        }
        return frozen() ? ticks() : mach_absolute_time()
    }

    @c(interposed_clock_mach_continuous_time)
    func continuous() -> UInt64 { frozen() ? ticks() : mach_continuous_time() }

    @c(interposed_clock_mach_approximate_time)
    func approximate() -> UInt64 { frozen() ? ticks() : mach_approximate_time() }
#endif
