import Lock

extension Clock.Interposed {
    /// The pending sleeps and the clock they wait on, under one lock, so a sleep and an advance never miss each other.
    final class Sleepers: Sendable {
        let state = Lock(State())
    }
}

extension Clock.Interposed.Sleepers {
    /// Waits until the clock reaches `deadline`, or until the task is cancelled, on `actor`, the caller's, so the
    /// sleep registers in the caller's turn and resumes on the caller's actor, waking the next there. The operation
    /// names `actor` to be isolated to it: a closure that does not runs on the global executor, where sleeps begun in
    /// order register, and resume, out of it.
    func wait<A: Actor>(
        until deadline: Clock.Interposed.Instant,
        on actor: isolated A,
        reading library: Clock.Interposed.Library
    ) async throws(CancellationError) {
        guard let order = try begin(deadline, library) else { return }
        let turn = await withTaskCancellationHandler(
            operation: {
                _ = actor
                return await withCheckedContinuation { register(deadline, order, library, $0) }
            },
            onCancel: { withdraw(order) },
            isolation: actor
        )
        try end(turn)
    }

    /// `wait(until:on:reading:)` for a caller on no actor.
    func wait(until deadline: Clock.Interposed.Instant, reading library: Clock.Interposed.Library) async throws(CancellationError) {
        guard let order = try begin(deadline, library) else { return }
        let turn = await withTaskCancellationHandler(
            operation: { await withCheckedContinuation { register(deadline, order, library, $0) } },
            onCancel: { withdraw(order) }
        )
        try end(turn)
    }

    /// Whether the clock, read through `library`, has reached `deadline`.
    func reached(_ deadline: Clock.Interposed.Instant, _ library: Clock.Interposed.Library) -> Bool {
        Clock.Interposed.Instant.origin.duration(to: deadline) <= .nanoseconds(library.elapsed())
    }

    /// The sleep's place in the order, or nil for a deadline already reached; a cancelled task throws.
    func begin(_ deadline: Clock.Interposed.Instant, _ library: Clock.Interposed.Library) throws(CancellationError) -> UInt64? {
        if Task.isCancelled { throw CancellationError() }
        guard !reached(deadline, library) else { return nil }
        return state.withLock { state in
            defer { state.next &+= 1 }
            return state.next
        }
    }

    /// Wakes the next sleep when this one was woken in its turn, then throws if the task was cancelled.
    func end(_ turn: Bool) throws(CancellationError) {
        if turn { wake() }
        if Task.isCancelled { throw CancellationError() }
    }

    /// Keeps the sleep until an advance reaches it, or resumes it now when the clock has reached it or the task is
    /// cancelled.
    func register(
        _ deadline: Clock.Interposed.Instant,
        _ order: UInt64,
        _ library: Clock.Interposed.Library,
        _ continuation: CheckedContinuation<Bool, Never>
    ) {
        let now = state.withLock { state -> Bool in
            guard !Task.isCancelled, !reached(deadline, library) else { return true }
            state.waiting.append(Sleeper(deadline: deadline, order: order, continuation: continuation))
            return false
        }
        if now { continuation.resume(returning: false) }
    }

    /// Takes a cancelled sleep out, wherever it waits, and resumes it out of turn.
    func withdraw(_ order: UInt64) {
        let withdrawn = state.withLock { state -> CheckedContinuation<Bool, Never>? in
            if let index = state.waiting.firstIndex(where: { $0.order == order }) {
                return state.waiting.remove(at: index).continuation
            }
            if let index = state.due.firstIndex(where: { $0.order == order }) {
                return state.due.remove(at: index).continuation
            }
            return nil
        }
        withdrawn?.resume(returning: false)
    }

    /// Moves the process's clock on by `nanoseconds` and queues every sleep it reaches, earliest deadline first and,
    /// among equal deadlines, in the order they began, after those already queued, whose deadlines are all earlier;
    /// then resumes the first unless a resumed sleep is yet to.
    func advance(by nanoseconds: UInt64, on library: Clock.Interposed.Library) {
        let first = state.withLock { state -> Sleeper? in
            library.advance(nanoseconds)
            let reached = state.waiting.filter { self.reached($0.deadline, library) }
            state.waiting.removeAll { self.reached($0.deadline, library) }
            state.due += reached.sorted { ($0.deadline, $0.order) < ($1.deadline, $1.order) }
            guard !state.waking, !state.due.isEmpty else { return nil }
            state.waking = true
            return state.due.removeFirst()
        }
        first?.continuation.resume(returning: true)
    }

    /// Resumes the next queued sleep, or notes that none is waking.
    func wake() {
        let next = state.withLock { state -> Sleeper? in
            guard !state.due.isEmpty else {
                state.waking = false
                return nil
            }
            return state.due.removeFirst()
        }
        next?.continuation.resume(returning: true)
    }
}
