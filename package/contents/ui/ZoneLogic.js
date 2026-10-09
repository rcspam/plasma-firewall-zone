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

// Which of the four configurable colours the panel icon takes.
//
// Order matters. A stopped firewalld is the one state worth interrupting for,
// so it outranks everything, including a perfectly good zone still reported by
// the last successful read. Anything that is not a zone you trust reads as
// "closed", unknown zones included: guessing in favour of the cautious colour
// is the safer error.
function colourKey(state, firewallRunning) {
    if (!firewallRunning)
        return "down"
    if (!state || !state.ok)
        return "offline"
    return trustLevel(state.zone) === "trusted" ? "trusted" : "closed"
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

function errorText(code) {
    switch (code) {
    case "no-zone": return "Interface is not assigned to any zone"
    case "offline": return "No network connection"
    case "busy":    return "firewalld is not responding"
    case "stopped": return "firewalld is stopped"
    case "no-network-manager": return "NetworkManager is not running"
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

// The D-Bus plugin hands strings, object paths and variants over as wrapper
// objects: `typeof` says "object" and comparing with === against a string
// fails. String() unwraps every one of them (checked on Plasma 6.6.6).
function dbusString(value) {
    return value === undefined || value === null ? "" : String(value)
}

// D-Bus arrays come as array-like objects, not JS arrays: Array.isArray is
// false, but length and indices work. Elements are wrapped like any string.
function firstString(list) {
    return list && list.length > 0 ? dbusString(list[0]) : ""
}

// Answer of firewalld's getZoneOfInterface, already unwrapped. An interface
// bound to no zone, or unknown to firewalld, gets "".
function zoneFromReply(value) {
    if (value === "")
        return { ok: false, zone: "", error: "no-zone" }
    return { ok: true, zone: value, error: "" }
}

// Turns a failed D-Bus call into the error codes errorText() knows.
// firewalld raises org.fedoraproject.FirewallD1.Exception for everything and
// puts its own code at the start of the message, hence the substring tests.
function zoneFromError(name, message) {
    var error = "unknown"
    if ((message || "").indexOf("INVALID_INTERFACE") !== -1)
        error = "offline"
    else if (name === "org.freedesktop.DBus.Error.NoReply"
             || name === "org.freedesktop.DBus.Error.Timeout")
        error = "busy"
    else if (name === "org.freedesktop.DBus.Error.ServiceUnknown"
             || name === "org.freedesktop.DBus.Error.NameHasNoOwner"
             || (message || "").indexOf("NOT_RUNNING") !== -1)
        error = "stopped"
    return { ok: false, zone: "", error: error }
}

// NetworkManager names a device twice. IpInterface is what carries the
// traffic, and the one firewalld knows; it stays empty on a modem that is not
// up yet, where Interface is the best there is.
function deviceInterface(ipInterface, interfaceName) {
    return ipInterface !== "" ? ipInterface : interfaceName
}

// Without NetworkManager there is no primary interface to look up, and saying
// "no network connection" would be wrong.
function effectiveZoneState(networkAvailable, zoneState) {
    if (!networkAvailable)
        return { ok: false, zone: "", error: "no-network-manager" }
    return zoneState
}

function sameZoneState(a, b) {
    return !!a && !!b && a.ok === b.ok && a.zone === b.zone && a.error === b.error
}
