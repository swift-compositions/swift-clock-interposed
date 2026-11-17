public import Clock_Concurrency
public import Tagged
public import Time

extension Clock {
    /// The process's clock as every image of the process reads the machine's uptime, which this clock can freeze and
    /// then move only by `advance`, however long the wall clock runs.
    ///
    /// It works through the `Interposed Clock Interposition` library, which must be in the process from launch: link
    /// that product into the executable, or start the executable with `DYLD_INSERT_LIBRARIES` naming it. Every value
    /// is a handle on the one clock of the process. As a clock of Swift's own, `now` is where it stands and a sleep
    /// returns when an advance reaches its deadline, never by the wall clock.
    public struct Interposed: Clock.Nonsending, Sendable {
        let library: Library

        /// A handle on the process's clock. Fails with `.absent` when the library is not in the process and with
        /// `.unhooked` when it was loaded after launch, so calls are not routed through it; it freezes nothing.
        public init() throws(Error) {
            guard let library = Library.found else { throw .absent }
            guard library.hooked() else { throw .unhooked }
            self.library = library
        }
    }
}

extension Clock.Interposed {
    public typealias Instant = Tagged<Clock.Interposed, Time.Instant>

    /// The sleeps of the one process clock, shared by every handle on it.
    static let sleepers = Sleepers()

    /// Whether the clock is frozen. Nothing thaws it: once frozen it stays so until the process ends.
    public var frozen: Bool { library.frozen() != 0 }

    /// Freezes the process's clock at the instant the machine's clock reads now: from here on every read of uptime
    /// in the process stands still until `advance` moves it. Freezing a frozen clock does nothing.
    public func freeze() { library.freeze() }

    /// How far the clock was moved on since it was frozen, in whole nanoseconds; zero before the freeze.
    public var elapsed: Duration { .nanoseconds(library.elapsed()) }

    /// Where the clock stands: `elapsed` from `Instant.origin`, the freeze.
    public var now: Instant { .origin.advanced(by: elapsed) }

    // swift-linter:disable:next compound identifier
    // REASON: Swift.Clock requires minimumResolution by this name.
    /// One nanosecond, what the clock counts in.
    public var minimumResolution: Duration { .nanoseconds(1) }

    /// Moves the frozen clock on until it stands at `deadline`, cut to whole nanoseconds, and resumes every sleep
    /// this reaches. Fails with `.running` before the freeze, `.backwards` for a deadline before `now` and `.beyond`
    /// for one past what the clock can count, and then moves nothing.
    public func advance(to deadline: Instant) throws(Error) {
        try advance(toElapsed: Instant.origin.duration(to: deadline))
    }

    /// `advance(to:)` of `now` moved on by `duration`.
    public func advance(by duration: Duration) throws(Error) {
        let (sum, over) = try Self.nanoseconds(elapsed).addingReportingOverflow(try Self.nanoseconds(duration))
        guard !over else { throw .beyond }
        try advance(toElapsed: .nanoseconds(sum))
    }

    func advance(toElapsed target: Duration) throws(Error) {
        guard frozen else { throw .running }
        let wanted = try Self.nanoseconds(target)
        let now = library.elapsed()
        guard wanted >= now else { throw .backwards }
        Self.sleepers.advance(by: wanted - now, on: library)
    }

    /// A duration as whole nanoseconds, the rest cut; `.backwards` below zero and `.beyond` past what fits.
    static func nanoseconds(_ duration: Duration) throws(Error) -> UInt64 {
        let (seconds, attoseconds) = duration.components
        guard seconds >= 0, attoseconds >= 0 else { throw .backwards }
        let (whole, wide) = UInt64(seconds).multipliedReportingOverflow(by: 1_000_000_000)
        let (sum, long) = whole.addingReportingOverflow(UInt64(attoseconds / 1_000_000_000))
        guard !wide, !long else { throw .beyond }
        return sum
    }
}

extension Clock.Interposed {
    /// Suspends until the clock has been advanced to `deadline` or past it.
    ///
    /// A deadline the clock has already reached returns at once, without suspending. Otherwise the sleep holds no
    /// thread and waits for the advance that reaches it; the wall clock never wakes it. The sleeps one advance
    /// reaches are resumed one after another, earliest deadline first and, for equal ones, in the order they began,
    /// each as the one before it resumes on its own actor. A task cancelled before or while it sleeps throws
    /// `CancellationError` at once, the clock unmoved. The tolerance is not used.
    nonisolated(nonsending)
        public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws(CancellationError)
    {
        try await sleep(until: deadline, tolerance: tolerance, isolation: #isolation)
    }

    /// `sleep(until:tolerance:)` resuming on `isolation`, the caller's actor, so the sleeps of one actor run in the
    /// order they are woken. Clock.Nonsending requires the caller's isolation as `isolated (any Actor)?`.
    public func sleep(until deadline: Instant, tolerance: Duration?, isolation: isolated (any Actor)?) async throws(CancellationError) {
        if let actor = isolation {
            try await Self.sleepers.wait(until: deadline, on: actor, reading: library)
        } else {
            try await Self.sleepers.wait(until: deadline, reading: library)
        }
    }
}
