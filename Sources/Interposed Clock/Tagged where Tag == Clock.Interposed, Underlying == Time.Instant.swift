public import Tagged
public import Time

extension Tagged where Tag == Clock.Interposed, Underlying == Time.Instant {
    /// Where the process's clock was frozen, from which every instant of it counts: `now` stands here until the
    /// freeze and until the first advance.
    public static var origin: Self { Self(Time.Instant(secondsSinceUnixEpoch: 0)) }
}
