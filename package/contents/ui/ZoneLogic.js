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
// Observed on firewalld 2.x / TUXEDO OS 24.04 (stream matters, stdout | stderr):
//   "home"       | ""                          exit 0    nominal
//   ""           | "no zone"                   exit 2    interface bound to no zone
//   ""           | "Error: INVALID_INTERFACE"  exit 104  empty interface name
//   ""           | "Error: Did not receive..." exit 254  transient D-Bus timeout
//   ""           | "FirewallD is not running"  exit 252  daemon stopped
// Only the nominal answer goes to stdout; every diagnostic goes to stderr, so
// both streams are searched. A zone name can never contain a space, hence
// matching "no zone" anywhere is unambiguous.
function parseZone(stdout, stderr, exitCode) {
    var out = (stdout || "").trim()
    var both = out + " " + (stderr || "").trim()

    if (both.indexOf("no zone") !== -1)
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

// Parses `firewall-cmd --zone=X --list-all`, whose layout comes from
// print_zone_policy_info() in firewall/command.py: a zone header, then one
// "  key: space separated values" line per attribute.
//
// One --list-all replaces --list-services plus --list-ports, and that matters:
// both go through an auth_admin_keep polkit action, and two commands fired at
// once produce two password dialogs, the second starting before the first
// authorisation is recorded.
// `ok` tells whether the answer was actually read: a declined password yields
// an empty output, and showing that as "no service is open" would misdescribe
// the firewall.
function parseListAll(stdout) {
    var result = { ok: false, services: [], ports: [] }
    var lines = (stdout || "").split("\n")

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        var colon = line.indexOf(":")
        if (colon === -1)
            continue
        // Exact key match: "source-ports" and "forward-ports" also end in
        // "ports" and would otherwise overwrite the real port list.
        var key = line.substring(0, colon)
        var value = line.substring(colon + 1).trim()
        if (key === "services") {
            result.services = parseList(value)
            result.ok = true
        } else if (key === "ports") {
            result.ports = parseList(value)
        }
    }
    return result
}

// Which firewall-cmd queries are free of a polkit prompt.
//
// firewalld ships two families of polkit actions (see
// /usr/share/polkit-1/actions/org.fedoraproject.FirewallD1.policy):
//   org.fedoraproject.FirewallD1.info         allow_active=yes
//   org.fedoraproject.FirewallD1.config.info  allow_active=auth_admin_keep
//
// Anything reaching the second family pops up a password dialog. Measured on
// firewalld 2.x: --get-active-zones, --get-default-zone and
// --get-zone-of-interface stay in the first family; --list-services,
// --list-ports and --state reach the second one.
//
// A widget that polls must therefore never run a query outside this list, or
// it asks for a password every tick. Reading the zone XML instead is not an
// option: /etc/firewalld is 750 root:root.
var FREE_QUERIES = [
    "--get-zone-of-interface",
    "--get-active-zones",
    "--get-default-zone"
]

function isFreeQuery(cmd) {
    for (var i = 0; i < FREE_QUERIES.length; i++)
        if ((cmd || "").indexOf(FREE_QUERIES[i]) !== -1)
            return true
    return false
}
