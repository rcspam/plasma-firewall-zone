// Runs shell commands through Plasma's executable engine and reports each
// reply once, under the command it answers.
//
// The source name is the command itself, the same from one run to the next.
// Disconnecting on reply lets the engine drop the source once control is back
// in the event loop, so the next run starts a fresh process. Never make the
// name unique per run: every executable DataSource in plasmashell keeps a key
// for each source the engine ever dropped, and each new key rebuilds its whole
// map. With an `env _=N` prefix polled every 10 s, plasmashell froze for close
// to a second on every poll after a few hours.
import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

Plasma5Support.DataSource {
    id: runner
    engine: "executable"
    connectedSources: []

    signal finished(string command, string stdout, string stderr, var exitCode)

    function run(cmd) {
        connectSource(cmd)
    }

    onNewData: function(source, data) {
        disconnectSource(source)
        finished(source, data["stdout"] || "", data["stderr"] || "", data["exit code"])
    }
}
