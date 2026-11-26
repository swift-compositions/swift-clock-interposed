#if canImport(Darwin)
    import Foundation
    import Clock_Interposed

    extension Fixture {
        /// What woke, in the order it ran, each with where the clock stood when it did.
        @MainActor final class Wakes {
            var lines: [String] = []

            func note(_ name: String, _ clock: Clock.Interposed) {
                let (seconds, attoseconds) = clock.elapsed.components
                let line = "\(name)@\(seconds * 1000 + attoseconds / 1_000_000_000_000_000)"
                lines.append(line)
                Fixture.line("woke", line)
            }
        }

        /// Waits `milliseconds` of wall time without holding the main actor, so what is due on it runs meanwhile.
        static func wall(milliseconds: UInt32) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                Thread.detachNewThread {
                    usleep(milliseconds * 1000)
                    continuation.resume()
                }
            }
        }

        /// Sleeps on the clock from the main actor until `deadline` milliseconds from the freeze, and notes the wake
        /// or the cancellation. The sleep has begun when this returns.
        @MainActor @discardableResult
        static func nap(_ name: String, until deadline: Int64, on clock: Clock.Interposed, into wakes: Wakes) -> Task<Void, Never> {
            Task.immediate { @MainActor in
                do throws(CancellationError) {
                    try await clock.sleep(until: at(.milliseconds(deadline)))
                    wakes.note(name, clock)
                } catch {
                    wakes.note("\(name):cancelled", clock)
                }
            }
        }

        @MainActor static func sleeping() async {
            let clock: Clock.Interposed
            do throws(Clock.Interposed.Error) {
                clock = try Clock.Interposed()
            } catch {
                line("error", error)
                return
            }
            let wakes = Wakes()
            line("unfrozen", clock.now == .origin)
            nap("early", until: 100, on: clock, into: wakes)
            clock.freeze()
            let erased: any _Concurrency.Clock<Duration> = clock
            _ = Task.immediate { @MainActor in
                do {
                    try await erased.sleep(for: .milliseconds(300))
                    wakes.note("erased", clock)
                } catch {
                    wakes.note("erased:cancelled", clock)
                }
            }
            nap("second", until: 200, on: clock, into: wakes)
            nap("tie", until: 200, on: clock, into: wakes)
            await wall(milliseconds: 400)
            line("unadvanced", wakes.lines.isEmpty)

            func step(_ milliseconds: Int64) async {
                Fixture.attempt("advance") { () throws(Clock.Interposed.Error) in try clock.advance(to: at(.milliseconds(milliseconds))) }
                await wall(milliseconds: 60)
            }
            await step(99)
            line("before", wakes.lines.isEmpty)
            await step(100)
            await step(199)
            await step(200)
            await step(400)
            line("order", wakes.lines.joined(separator: ","))

            wakes.lines = []
            (0..<20).forEach { nap("m\($0)", until: 500, on: clock, into: wakes) }
            await step(500)
            line("many", wakes.lines == (0..<20).map { "m\($0)@500" })

            wakes.lines = []
            _ = Task.immediate { @MainActor in
                do throws(CancellationError) {
                    try await clock.sleep(until: clock.now)
                    try await clock.sleep(until: at(.milliseconds(10)))
                    wakes.lines.append("returned")
                } catch {
                    wakes.lines.append("cancelled")
                }
            }
            line("immediate", wakes.lines == ["returned"])

            wakes.lines = []
            let cancelled = nap("cancelled", until: 10_000, on: clock, into: wakes)
            cancelled.cancel()
            await wall(milliseconds: 60)
            line("cancelled", wakes.lines.joined(separator: ","))
            wakes.lines = []
            _ = Task.immediate { @MainActor in
                unsafe withUnsafeCurrentTask { unsafe $0?.cancel() }
                do throws(CancellationError) {
                    try await clock.sleep(until: at(.seconds(10)))
                } catch {
                    wakes.lines.append("refused")
                }
            }
            line("refused", wakes.lines == ["refused"])
            wakes.lines = []
            await step(20_000)
            line("withdrawn", wakes.lines.isEmpty ? "none" : wakes.lines.joined(separator: ","))
            line("elapsed", clock.elapsed == .seconds(20))
        }
    }
#endif
