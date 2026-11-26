#if canImport(Darwin)
    import Darwin
    import Dispatch

    /// The process the tests launch: an interposed clock needs a process of its own, with the library in it from
    /// launch. Each mode prints `key=value` lines for its test to read.
    let arguments = CommandLine.arguments
    switch arguments.dropFirst().first {
    case "clock":
        Fixture.clock()

    case "sleep":
        _ = Task { @MainActor in
            await Fixture.sleeping()
            exit(0)
        }
        dispatchMain()

    case "late":
        Fixture.late(library: arguments[2])

    default:
        Fixture.line("error", "no mode")
    }
#endif
