extension Clock.Interposed.Sleepers {
    /// A pending sleep: its deadline, its place in the order sleeps began, and how to resume it.
    struct Sleeper {
        let deadline: Clock.Interposed.Instant
        let order: UInt64
        /// Resumed with true when the sleep is woken in its turn, which then wakes the next.
        let continuation: CheckedContinuation<Bool, Never>
    }
}
