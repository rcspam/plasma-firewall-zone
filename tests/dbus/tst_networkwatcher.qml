// NetworkWatcher against the fake NetworkManager of fake_services.py.
import QtQuick
import QtTest
import org.kde.plasma.workspace.dbus as DBus
import "../../package/contents/ui"

TestCase {
    id: tc
    name: "NetworkWatcher"

    readonly property string nm: "org.freedesktop.NetworkManager"

    TestControl { id: ctl }

    Component {
        id: watcherComponent
        NetworkWatcher {
            busType: DBus.BusType.Session
            fallbackInterval: 0
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

    function setPrimary(ipInterface, interfaceName, emit) {
        ctl.call(tc, "SetPrimary", "(ssb)", [ipInterface, interfaceName, emit])
    }

    function test_initial_state() {
        var w = make()
        verify(w.available)
        tryCompare(w, "iface", "wlo1", 2000)
    }

    function test_primary_connection_change() {
        var w = make()
        tryCompare(w, "iface", "wlo1", 2000)
        setPrimary("enp3s0", "enp3s0", true)
        tryCompare(w, "iface", "enp3s0", 1000)
    }

    function test_connection_lost() {
        var w = make()
        tryCompare(w, "iface", "wlo1", 2000)
        setPrimary("", "", true)
        tryCompare(w, "iface", "", 1000)
    }

    function test_falls_back_to_interface_name() {
        var w = make()
        tryCompare(w, "iface", "wlo1", 2000)
        setPrimary("", "wwan0", true)
        tryCompare(w, "iface", "wwan0", 1000)
    }

    function test_network_manager_leaves_and_returns() {
        var w = make()
        tryCompare(w, "iface", "wlo1", 2000)
        ctl.call(tc, "StopService", "(s)", [nm])
        tryCompare(w, "available", false, 2000)
        compare(w.iface, "")
        ctl.call(tc, "StartService", "(s)", [nm])
        tryCompare(w, "available", true, 2000)
        tryCompare(w, "iface", "wlo1", 2000)
    }

    // The first Get of a manual refresh is held back. Meanwhile the primary
    // connection moves and its signal starts a newer chain. When the old reply
    // finally lands, it names the old connection and must be dropped.
    function test_stale_reply_is_dropped() {
        var w = make()
        tryCompare(w, "iface", "wlo1", 2000)
        ctl.call(tc, "DelayNext", "(su)", ["Get", 400])
        w.refresh()
        setPrimary("enp3s0", "enp3s0", true)
        tryCompare(w, "iface", "enp3s0", 1000)
        wait(700)
        compare(w.iface, "enp3s0")
    }

    function test_change_without_signal_caught_by_fallback() {
        var w = make({ fallbackInterval: 300 })
        tryCompare(w, "iface", "wlo1", 2000)
        setPrimary("enp3s0", "enp3s0", false)
        tryCompare(w, "iface", "enp3s0", 2000)
    }

    function test_unrelated_property_change_is_ignored() {
        var w = make()
        tryCompare(w, "iface", "wlo1", 2000)
        wait(100)
        var before = ctl.count(tc, "Get")
        ctl.call(tc, "EmitNetworkManagerProperties", "(as)", [["Connectivity", "ActiveConnections"]])
        wait(300)
        compare(ctl.count(tc, "Get"), before)
    }

    function test_starts_before_network_manager() {
        ctl.call(tc, "StopService", "(s)", [nm])
        var w = make()
        compare(w.available, false)
        compare(w.iface, "")
        ctl.call(tc, "StartService", "(s)", [nm])
        tryCompare(w, "iface", "wlo1", 2000)
        // Signals must work after a late start too, the fallback is off here.
        setPrimary("enp3s0", "enp3s0", true)
        tryCompare(w, "iface", "enp3s0", 1000)
    }

    function test_error_mid_chain_clears_then_recovers() {
        var w = make()
        tryCompare(w, "iface", "wlo1", 2000)
        ctl.call(tc, "FailNext", "(sss)", ["Get", "org.freedesktop.DBus.Error.UnknownObject", "gone"])
        w.refresh()
        tryCompare(w, "iface", "", 1000)
        setPrimary("enp3s0", "enp3s0", true)
        tryCompare(w, "iface", "enp3s0", 1000)
    }

    // A reply that lands after the watcher is gone must not touch it.
    function test_reply_after_destroy_is_harmless() {
        failOnWarning(/TypeError/)
        var w = make()
        tryCompare(w, "iface", "wlo1", 2000)
        ctl.call(tc, "DelayNext", "(su)", ["Get", 300])
        w.refresh()
        w.destroy()
        wait(500)
    }
}
