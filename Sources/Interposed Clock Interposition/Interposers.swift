#if canImport(QuartzCore)
    import Darwin
    import QuartzCore

    @c(interposed_clock_CACurrentMediaTime)
    func media() -> Double {
        guard frozen() else { return CACurrentMediaTime() }
        return unsafe real(ticks()) * real(numerator) / real(denominator) / 1e9
    }

    /// A count as a `Double` through the standard library's one conversion that is not generic, so it needs no
    /// witness table from the runtime. Counts here are far below `Int.max`.
    @inline(__always)
    func real(_ count: UInt64) -> Double { Double(Int(bitPattern: UInt(count))) }

    /// The dynamic linker reads this section when the library is in the process at launch and binds every other
    /// image's calls to each second function to the first. Calls made inside this library keep reaching the
    /// machine's own functions.
    @used @section("__DATA,__interpose")
    let interposers:
        (
            (@convention(c) () -> UInt64, @convention(c) () -> UInt64),
            (@convention(c) () -> UInt64, @convention(c) () -> UInt64),
            (@convention(c) () -> UInt64, @convention(c) () -> UInt64),
            (@convention(c) () -> Double, @convention(c) () -> Double)
        ) = (
            (absolute, mach_absolute_time),
            (continuous, mach_continuous_time),
            (approximate, mach_approximate_time),
            (media, CACurrentMediaTime)
        )
#elseif canImport(Darwin)
    import Darwin

    /// The dynamic linker reads this section when the library is in the process at launch and binds every other
    /// image's calls to each second function to the first. Calls made inside this library keep reaching the
    /// machine's own functions.
    @used @section("__DATA,__interpose")
    let interposers:
        (
            (@convention(c) () -> UInt64, @convention(c) () -> UInt64),
            (@convention(c) () -> UInt64, @convention(c) () -> UInt64),
            (@convention(c) () -> UInt64, @convention(c) () -> UInt64)
        ) = (
            (absolute, mach_absolute_time),
            (continuous, mach_continuous_time),
            (approximate, mach_approximate_time)
        )
#endif
