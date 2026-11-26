#if canImport(Darwin)
    import Darwin
#endif

extension Clock.Interposed {
    /// The interposition library's functions, found by name in the running process. This code is built into the
    /// caller's own image, so its reads of the machine's uptime are among those the library replaces.
    struct Library: Sendable {
        let freeze: @convention(c) () -> Void
        let frozen: @convention(c) () -> Int32
        let advance: @convention(c) (UInt64) -> Void
        let elapsed: @convention(c) () -> UInt64
        let probe: @convention(c) () -> Void
    }
}

extension Clock.Interposed.Library {
    /// The library's functions, or nil when it is not in the process.
    static var found: Self? {
        #if canImport(Darwin)
            // WHY: RTLD_DEFAULT, which Swift does not import: every image of the process, in load order.
            let everywhere = unsafe UnsafeMutableRawPointer(bitPattern: -2)
            guard
                let freeze = unsafe dlsym(everywhere, "interposed_clock_freeze"),
                let frozen = unsafe dlsym(everywhere, "interposed_clock_frozen"),
                let advance = unsafe dlsym(everywhere, "interposed_clock_advance"),
                let elapsed = unsafe dlsym(everywhere, "interposed_clock_elapsed"),
                let probe = unsafe dlsym(everywhere, "interposed_clock_probe")
            else { return nil }
            return unsafe Self(
                freeze: unsafeBitCast(freeze, to: (@convention(c) () -> Void).self),
                frozen: unsafeBitCast(frozen, to: (@convention(c) () -> Int32).self),
                advance: unsafeBitCast(advance, to: (@convention(c) (UInt64) -> Void).self),
                elapsed: unsafeBitCast(elapsed, to: (@convention(c) () -> UInt64).self),
                probe: unsafeBitCast(probe, to: (@convention(c) () -> Void).self)
            )
        #else
            return nil
        #endif
    }

    /// Whether this image's reads of uptime are routed through the library: after a probe, its next read answers
    /// `UInt64.max` only when it is.
    func hooked() -> Bool {
        #if canImport(Darwin)
            probe()
            return mach_absolute_time() == .max
        #else
            return false
        #endif
    }
}
