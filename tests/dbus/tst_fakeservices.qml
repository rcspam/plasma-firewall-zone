// Checks the fake services themselves, so that a failure in the watcher tests
// points at the watchers and not at their test double.
import QtQuick
import QtTest
import org.kde.plasma.workspace.dbus as DBus

TestCase {
    id: tc
    name: "FakeServices"

    readonly property string nm: "org.freedesktop.NetworkManager"
    readonly property string fw: "org.fedoraproject.FirewallD1"
    readonly property string props: "org.freedesktop.DBus.Properties"

    TestControl { id: ctl }
    DBus.DBusServiceWatcher { id: nmWatch; busType: DBus.BusType.Session; watchedService: tc.nm }
    DBus.DBusServiceWatcher { id: fwWatch; busType: DBus.BusType.Session; watchedService: tc.fw }

    function initTestCase() {
        if (!ctl.registered)
            skip(ctl.missingMessage)
    }

    function init() {
        ctl.call(tc, "Reset", "", [])
    }

    function zoneOf(name) {
        return ctl.ask(tc, fw, "/org/fedoraproject/FirewallD1", fw + ".zone",
                       "getZoneOfInterface", "(s)", [name])
    }

    function nmGet(path, iface, property) {
        return ctl.ask(tc, nm, path, props, "Get", "(ss)", [iface, property])
    }

    function primaryInterface() {
        var connection = String(nmGet("/org/freedesktop/NetworkManager", nm, "PrimaryConnection").value)
        if (connection === "/")
            return ""
        var device = String(nmGet(connection, nm + ".Connection.Active", "Devices").value[0])
        return String(nmGet(device, nm + ".Device", "IpInterface").value) + "/"
             + String(nmGet(device, nm + ".Device", "Interface").value)
    }

    function test_firewalld_answers_from_the_reset_state() {
        compare(String(zoneOf("wlo1").value), "home")
        compare(String(zoneOf("enp3s0").value), "public")
        compare(String(zoneOf("wlo9").value), "")
        verify(zoneOf("").error.indexOf("INVALID_INTERFACE") !== -1)
        compare(String(ctl.ask(tc, fw, "/org/fedoraproject/FirewallD1", fw,
                               "getDefaultZone", "", []).value), "public")
    }

    function test_set_zone_and_default_zone() {
        ctl.call(tc, "SetZone", "(ssas)", ["wlo1", "work", []])
        compare(String(zoneOf("wlo1").value), "work")
        ctl.call(tc, "SetZone", "(ssas)", ["wlo1", "", []])
        compare(String(zoneOf("wlo1").value), "")
        ctl.call(tc, "SetDefaultZone", "(s)", ["drop"])
        compare(String(ctl.ask(tc, fw, "/org/fedoraproject/FirewallD1", fw,
                               "getDefaultZone", "", []).value), "drop")
    }

    function test_network_manager_primary_connection() {
        compare(primaryInterface(), "wlo1/wlo1")
        ctl.call(tc, "SetPrimary", "(ssb)", ["", "wwan0", false])
        compare(primaryInterface(), "/wwan0")
        ctl.call(tc, "SetPrimary", "(ssb)", ["", "", false])
        compare(primaryInterface(), "")
    }

    function test_fail_delay_and_count() {
        compare(ctl.count(tc, "getZoneOfInterface"), 0)
        ctl.call(tc, "FailNext", "(sss)", ["getZoneOfInterface", "org.freedesktop.DBus.Error.NoReply", "late"])
        compare(zoneOf("wlo1").error, "org.freedesktop.DBus.Error.NoReply: late")
        compare(String(zoneOf("wlo1").value), "home")
        ctl.call(tc, "DelayNext", "(su)", ["getZoneOfInterface", 300])
        var started = Date.now()
        compare(String(zoneOf("wlo1").value), "home")
        verify(Date.now() - started >= 250)
        compare(ctl.count(tc, "getZoneOfInterface"), 3)
    }

    function test_stop_and_start_services() {
        ctl.call(tc, "StopService", "(s)", [nm])
        tryCompare(nmWatch, "registered", false)
        compare(fwWatch.registered, true)
        ctl.call(tc, "StopService", "(s)", [fw])
        tryCompare(fwWatch, "registered", false)
        ctl.call(tc, "Reset", "", [])
        tryCompare(nmWatch, "registered", true)
        tryCompare(fwWatch, "registered", true)
    }
}
