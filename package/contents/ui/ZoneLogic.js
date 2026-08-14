// Pure decision logic for the Firewall Zone widget.
// Deliberately free of any QML dependency so it can be unit-tested with
// qmltestrunner. Keep it that way: main.qml must hold no business rule.
.pragma library

// Trust level drives the icon. Zone names are firewalld's built-in ones.
function trustLevel(zone) {
    switch (zone) {
    case "home":
    case "internal":
    case "trusted":
    case "work":
        return "trusted"
    case "public":
    case "external":
    case "dmz":
        return "closed"
    case "block":
    case "drop":
        return "blocked"
    default:
        return "unknown"
    }
}

function iconFor(state) {
    if (!state || !state.ok)
        return "network-disconnect"
    switch (trustLevel(state.zone)) {
    case "trusted": return "security-high"
    case "closed":  return "security-medium"
    case "blocked": return "security-low"
    default:        return "network-wired"
    }
}

// Parses `firewall-cmd --get-zone-of-interface=<iface>`.
// Observed on firewalld 2.x / TUXEDO OS 24.04:
//   "home"                        exit 0    nominal
//   "no zone"                     exit 2    interface bound to no zone
//   "Error: INVALID_INTERFACE"    exit 104  empty or unknown interface (offline)
//   "Error: Did not receive..."   exit != 0 transient D-Bus timeout under load
//   "FirewallD is not running"    exit 252  daemon stopped
function parseZone(stdout, stderr, exitCode) {
    var out = (stdout || "").trim()
    var both = out + " " + (stderr || "").trim()

    if (out === "no zone")
        return { ok: false, zone: "", error: "no-zone" }
    if (both.indexOf("INVALID_INTERFACE") !== -1)
        return { ok: false, zone: "", error: "offline" }
    if (both.indexOf("Did not receive a reply") !== -1)
        return { ok: false, zone: "", error: "busy" }
    if (both.indexOf("FirewallD is not running") !== -1)
        return { ok: false, zone: "", error: "stopped" }
    if (exitCode === 0 && out.length > 0)
        return { ok: true, zone: out, error: "" }
    return { ok: false, zone: "", error: "unknown" }
}

function errorText(code) {
    switch (code) {
    case "no-zone": return "Interface is not assigned to any zone"
    case "offline": return "No network connection"
    case "busy":    return "firewalld is not responding"
    case "stopped": return "firewalld is stopped"
    default:        return "Firewall state unknown"
    }
}

// Parses the space-separated output of --list-services and --list-ports.
function parseList(stdout) {
    var s = (stdout || "").trim()
    return s.length === 0 ? [] : s.split(/\s+/)
}
