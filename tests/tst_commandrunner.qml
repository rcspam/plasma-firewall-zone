// CommandRunner talks to Plasma's executable engine, so this test runs a few
// harmless shell commands for real and needs plasma5support installed.
import QtQuick
import QtTest
import "../package/contents/ui"

TestCase {
    id: tc
    name: "CommandRunner"

    Component {
        id: runnerComponent
        CommandRunner {}
    }

    SignalSpy {
        id: replies
        signalName: "finished"
    }

    function makeRunner() {
        var runner = createTemporaryObject(runnerComponent, tc)
        replies.target = runner
        replies.clear()
        return runner
    }

    // Pause after each reply, as between two polls: the engine only drops a
    // finished source once control is back in the event loop.
    function runAndWait(runner, cmd) {
        var expected = replies.count + 1
        runner.run(cmd)
        tryCompare(replies, "count", expected, 5000)
        wait(50)
    }

    // The same command twice must start two processes, not replay the first
    // reply. Nanosecond timestamps make a replayed reply easy to spot.
    function test_same_command_runs_again() {
        var runner = makeRunner()
        var cmd = "date +%s%N"
        runAndWait(runner, cmd)
        runAndWait(runner, cmd)
        compare(replies.signalArguments[0][0], cmd)
        compare(replies.signalArguments[1][0], cmd)
        verify(replies.signalArguments[0][1] !== replies.signalArguments[1][1])
    }

    // Every executable DataSource in plasmashell keeps a key for each source
    // name the engine ever dropped, and each new key rebuilds its whole map.
    // A command repeated on every poll must therefore keep a single name.
    function test_repeated_command_leaves_one_entry() {
        var runner = makeRunner()
        for (var i = 0; i < 5; i++)
            runAndWait(runner, "echo one-entry")
        var keys = Object.keys(runner.data).filter(function(k) {
            return k.indexOf("one-entry") !== -1
        })
        compare(keys.length, 1)
    }
}
