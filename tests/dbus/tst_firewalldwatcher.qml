// FirewalldWatcher against the fake firewalld of fake_services.py.
import QtQuick
import QtTest
import org.kde.plasma.workspace.dbus as DBus
import "../../package/contents/ui"

TestCase {
    id: tc
    name: "FirewalldWatcher"

    readonly property string fw: "org.fedoraproject.FirewallD1"

    TestControl { id: ctl }

    SignalSpy {
        id: zoneSpy
        signalName: "zoneStateChanged"
    }

    Component {
        id: watcherComponent
        FirewalldWatcher {
            busType: DBus.BusType.Session
            fallbackInterval: 0
            iface: "wlo1"
        }
    }

    // Skipped here, before each function: Qt 6.10 only skips the first test
    // function when skip() is called from initTestCase().
    function init() {
        if (!ctl.registered)
            skip(ctl.missingMessage)
        ctl.call(tc, "Reset", "", [])
    }

    function make(properties) {
        return createTemporaryObject(watcherComponent, tc, properties || {})
    }

    function zoneIs(w, zone) {
        tryVerify(function() { return w.zoneState.ok && w.zoneState.zone === zone },
                  2000, "zone should become " + zone + ", is " + JSON.stringify(w.zoneState))
    }

    function errorIs(w, code) {
        tryVerify(function() { return !w.zoneState.ok && w.zoneState.error === code },
                  2000, "error should become " + code + ", is " + JSON.stringify(w.zoneState))
    }

    function setZone(iface, zone, signals) {
        ctl.call(tc, "SetZone", "(ssas)", [iface, zone, signals])
    }

    function test_initial_state() {
        var w = make()
        verify(w.running)
        zoneIs(w, "home")
        tryCompare(w, "defaultZone", "public", 2000)
    }

    function test_zone_signals_data() {
        return [
            { tag: "InterfaceAdded" },
            { tag: "InterfaceRemoved" },
            { tag: "ZoneOfInterfaceChanged" },
            { tag: "ZoneChanged" }
        ]
    }

    function test_zone_signals(data) {
        var w = make()
        zoneIs(w, "home")
        setZone("wlo1", "work", [data.tag])
        zoneIs(w, "work")
    }

    function test_default_zone_changed() {
        var w = make()
        tryCompare(w, "defaultZone", "public", 2000)
        ctl.call(tc, "SetDefaultZone", "(s)", ["drop"])
        tryCompare(w, "defaultZone", "drop", 1000)
    }

    // An interface bound to the default zone changes zone with it, and the
    // fake sends no zone signal for that, only DefaultZoneChanged.
    function test_default_zone_change_rereads_zone() {
        var w = make()
        zoneIs(w, "home")
        setZone("wlo1", "drop", [])
        ctl.call(tc, "SetDefaultZone", "(s)", ["drop"])
        zoneIs(w, "drop")
    }

    function test_reloaded_reads_again() {
        var w = make()
        zoneIs(w, "home")
        setZone("wlo1", "trusted", [])
        ctl.call(tc, "Reload", "", [])
        zoneIs(w, "trusted")
    }

    function test_firewalld_leaves_and_returns() {
        var w = make()
        zoneIs(w, "home")
        tryCompare(w, "defaultZone", "public", 2000)
        ctl.call(tc, "StopService", "(s)", [fw])
        tryCompare(w, "running", false, 2000)
        errorIs(w, "stopped")
        compare(w.defaultZone, "")
        ctl.call(tc, "StartService", "(s)", [fw])
        zoneIs(w, "home")
        tryCompare(w, "defaultZone", "public", 2000)
    }

    // The query for wlo1 is held back. The interface changes to enp3s0 before
    // it lands; its late "work" answer is about wlo1 and must be dropped.
    function test_iface_change_during_delayed_reply() {
        var w = make()
        zoneIs(w, "home")
        setZone("wlo1", "work", [])
        ctl.call(tc, "DelayNext", "(su)", ["getZoneOfInterface", 400])
        w.refresh()
        wait(150)
        w.iface = "enp3s0"
        zoneIs(w, "public")
        wait(500)
        compare(w.zoneState.zone, "public")
    }

    function test_empty_iface_asks_nothing() {
        var w = make()
        zoneIs(w, "home")
        wait(100)
        var before = ctl.count(tc, "getZoneOfInterface")
        w.iface = ""
        errorIs(w, "offline")
        wait(200)
        compare(ctl.count(tc, "getZoneOfInterface"), before)
    }

    function test_error_is_translated() {
        var w = make()
        zoneIs(w, "home")
        ctl.call(tc, "FailNext", "(sss)", ["getZoneOfInterface",
                 "org.fedoraproject.FirewallD1.Exception", "INVALID_INTERFACE: 'wlo1'"])
        w.refresh()
        errorIs(w, "offline")
    }

    // firewalld sends several signals for one move. They must end in one call.
    function test_signal_burst_gives_one_call() {
        var w = make()
        zoneIs(w, "home")
        wait(100)
        var before = ctl.count(tc, "getZoneOfInterface")
        setZone("wlo1", "work", ["InterfaceRemoved", "InterfaceAdded",
                                 "ZoneOfInterfaceChanged", "ZoneChanged"])
        zoneIs(w, "work")
        wait(200)
        compare(ctl.count(tc, "getZoneOfInterface") - before, 1)
    }

    function test_change_without_signal_caught_by_fallback() {
        var w = make({ fallbackInterval: 300 })
        zoneIs(w, "home")
        setZone("wlo1", "block", [])
        zoneIs(w, "block")
    }

    // main.qml clears the service list on every zoneState change, so the same
    // answer read again must leave zoneState alone.
    function test_identical_answer_keeps_zone_state() {
        var w = make()
        zoneIs(w, "home")
        wait(100)
        zoneSpy.target = w
        zoneSpy.clear()
        var before = ctl.count(tc, "getZoneOfInterface")
        ctl.call(tc, "Reload", "", [])
        wait(300)
        verify(ctl.count(tc, "getZoneOfInterface") > before)
        compare(zoneSpy.count, 0)
    }

    function test_starts_before_firewalld() {
        ctl.call(tc, "StopService", "(s)", [fw])
        var w = make()
        compare(w.running, false)
        errorIs(w, "stopped")
        compare(w.defaultZone, "")
        ctl.call(tc, "StartService", "(s)", [fw])
        zoneIs(w, "home")
        tryCompare(w, "defaultZone", "public", 2000)
        // Signals must work after a late start too, the fallback is off here.
        setZone("wlo1", "work", ["ZoneOfInterfaceChanged"])
        zoneIs(w, "work")
    }

    // Covers an error answer right after the service returns: the call fails
    // once, and the fallback check brings the zone back.
    function test_firewalld_not_ready_on_return() {
        var w = make({ fallbackInterval: 500 })
        zoneIs(w, "home")
        ctl.call(tc, "StopService", "(s)", [fw])
        errorIs(w, "stopped")
        var before = ctl.count(tc, "getZoneOfInterface")
        ctl.call(tc, "FailNext", "(sss)", ["getZoneOfInterface",
                 "org.fedoraproject.FirewallD1.Exception", "NOT_RUNNING"])
        ctl.call(tc, "StartService", "(s)", [fw])
        tryCompare(w, "running", true, 2000)
        wait(200)
        compare(ctl.count(tc, "getZoneOfInterface"), before + 1)
        compare(w.zoneState.error, "stopped")
        zoneIs(w, "home")
    }

    // A reply that lands after the watcher is gone must not touch it.
    function test_reply_after_destroy_is_harmless() {
        failOnWarning(/TypeError/)
        var w = make()
        zoneIs(w, "home")
        ctl.call(tc, "DelayNext", "(su)", ["getZoneOfInterface", 300])
        w.refresh()
        wait(100)
        w.destroy()
        wait(500)
    }
}
