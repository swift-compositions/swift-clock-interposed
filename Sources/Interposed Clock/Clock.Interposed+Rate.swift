public import Rate

extension Clock.Interposed {
    /// Moves the clock to the start of a tick at `rate`, counted from `origin`: the exact start, cut to whole
    /// nanoseconds, so no error builds up from tick to tick. Fails as `advance(to:)` does.
    public func advance(to tick: Integer, at rate: Rate, from origin: Instant = .origin) throws(Error) {
        guard let elapsed = rate.elapsed(at: tick) else { throw .beyond }
        try advance(to: origin.advanced(by: elapsed))
    }
}
