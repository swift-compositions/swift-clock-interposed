extension Clock.Interposed {
    public enum Error: Swift.Error, Hashable, Sendable {
        /// The interposition library is not in the process.
        case absent
        /// The library is in the process but was not there at launch, so calls are not routed through it.
        case unhooked
        /// The clock is not frozen, so it cannot be moved.
        case running
        /// The instant lies before where the clock stands; it never runs backwards.
        case backwards
        /// The instant is more nanoseconds from the freeze than the clock can count.
        case beyond
    }
}
