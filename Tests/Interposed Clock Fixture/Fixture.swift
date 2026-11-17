#if canImport(Darwin)
    import Darwin
    import Interposed_Clock
    #if canImport(QuartzCore)
        import QuartzCore
    #endif

    enum Fixture {}

    extension Fixture {
        static func line(_ key: String, _ value: Any) { print("\(key)=\(value)") }

        /// The four readings the library replaces.
        static func readings() -> [Double] {
            [Double(mach_absolute_time()), Double(mach_continuous_time()), Double(mach_approximate_time()), CACurrentMediaTime()]
        }

        /// Wall time in seconds, which nothing here replaces.
        static func wall() -> Double {
            var now = timeval()
            unsafe gettimeofday(&now, nil)
            return Double(now.tv_sec) + Double(now.tv_usec) / 1_000_000
        }

        /// Machine ticks as nanoseconds.
        static func nanoseconds(_ ticks: Double) -> Double {
            var timebase = mach_timebase_info_data_t()
            unsafe mach_timebase_info(&timebase)
            return ticks * Double(timebase.numer) / Double(timebase.denom)
        }

        static func attempt(_ key: String, _ body: () throws(Clock.Interposed.Error) -> Void) {
            do throws(Clock.Interposed.Error) {
                try body()
                line(key, "done")
            } catch {
                line(key, error)
            }
        }

        static func at(_ duration: Duration) -> Clock.Interposed.Instant { .origin.advanced(by: duration) }

        static func clock() {
            let before = readings()
            usleep(20_000)
            line("running", zip(before, readings()).allSatisfy { $0 < $1 })
            let clock: Clock.Interposed
            do throws(Clock.Interposed.Error) {
                clock = try Clock.Interposed()
            } catch {
                line("error", error)
                return
            }
            line("thawed", !clock.frozen && clock.elapsed == .zero)
            attempt("unfrozen") { () throws(Clock.Interposed.Error) in try clock.advance(by: .seconds(1)) }
            let passing = readings()
            usleep(20_000)
            line("through", zip(passing, readings()).allSatisfy { $0 < $1 })
            clock.freeze()
            let frozen = readings()
            let started = wall()
            usleep(40_000)
            line("still", frozen == readings())
            line("wall", wall() - started > 0.03)
            line("zero", clock.frozen && clock.elapsed == .zero && clock.now == .origin)
            clock.freeze()
            line("again", frozen == readings())
            attempt("second") { () throws(Clock.Interposed.Error) in try clock.advance(to: at(.seconds(1))) }
            let moved = readings()
            line("absolute", nanoseconds(moved[0] - frozen[0]))
            line("continuous", nanoseconds(moved[1] - frozen[1]))
            line("approximate", nanoseconds(moved[2] - frozen[2]))
            line("media", abs(moved[3] - frozen[3] - 1) < 0.000_001)
            line("elapsed", clock.elapsed == .seconds(1) && clock.now == at(.seconds(1)))
            usleep(40_000)
            line("held", moved == readings())
            attempt("backwards") { () throws(Clock.Interposed.Error) in try clock.advance(to: at(.milliseconds(999))) }
            attempt("negative") { () throws(Clock.Interposed.Error) in try clock.advance(by: .seconds(-1)) }
            attempt("beyond") { () throws(Clock.Interposed.Error) in try clock.advance(by: .seconds(Int64.max)) }
            line("unmoved", clock.elapsed == .seconds(1) && moved == readings())
            attempt("same") { () throws(Clock.Interposed.Error) in try clock.advance(by: .zero) }
            attempt("cut") { () throws(Clock.Interposed.Error) in
                try clock.advance(by: .seconds(1) + .nanoseconds(5) + Duration(secondsComponent: 0, attosecondsComponent: 999_999_999))
            }
            line("whole", clock.elapsed == .seconds(2) + .nanoseconds(5))
            attempt("other") { () throws(Clock.Interposed.Error) in
                let other = try Clock.Interposed()
                line("kept", other.frozen && other.elapsed == clock.elapsed)
                try other.advance(to: at(.seconds(3)))
                line("shared", clock.elapsed == .seconds(3))
            }
        }

        /// Loads the library after launch, when no call can be routed through it any more.
        static func late(library: String) {
            line("loaded", unsafe dlopen(library, RTLD_NOW) != nil)
            attempt("clock") { () throws(Clock.Interposed.Error) in _ = try Clock.Interposed() }
            let before = readings()
            usleep(20_000)
            line("running", zip(before, readings()).allSatisfy { $0 < $1 })
        }
    }
#endif
