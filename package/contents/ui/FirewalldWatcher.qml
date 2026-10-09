// Follows the firewalld zone of one interface, the default zone, and whether
// firewalld is on the bus at all. Everything is read over D-Bus and refreshed
// on firewalld's own signals, so no process is started; a slow fallback timer
// catches a signal that went missing.
//
// Only getZoneOfInterface and getDefaultZone are called. Both belong to the
// FirewallD1.info polkit family, which is allow_active=yes. Plasma's D-Bus
// plugin never allows interactive authorisation anyway: a call that would need
// a password fails instead of opening a dialog.
import QtQuick
import org.kde.plasma.workspace.dbus as DBus
import "ZoneLogic.js" as ZoneLogic

Item {
    id: watcher

    property int busType: DBus.BusType.System
    // 0 disables the fallback check.
    property int fallbackInterval: 60000
    property string iface: ""

    readonly property bool running: firewalld.registered
    property var zoneState: ({ ok: false, zone: "", error: "unknown" })
    property string defaultZone: ""

    readonly property string _name: "org.fedoraproject.FirewallD1"
    readonly property string _path: "/org/fedoraproject/FirewallD1"
    readonly property string _zoneInterface: "org.fedoraproject.FirewallD1.zone"
    property int _zoneSerial: 0

    function refresh() {
        readDefaultZone()
        scheduleZone()
    }

    // Every zone query waits for this short delay first. firewalld sends
    // several signals for one move (InterfaceRemoved, InterfaceAdded,
    // ZoneOfInterfaceChanged and its old name ZoneChanged), and an iface
    // change often follows; together they make a single call.
    function scheduleZone() {
        debounce.restart()
    }

    function queryZone() {
        var serial = ++_zoneSerial
        if (!firewalld.registered) {
            setZoneState({ ok: false, zone: "", error: "stopped" })
            return
        }
        if (iface === "") {
            setZoneState({ ok: false, zone: "", error: "offline" })
            return
        }
        // A newer query, or firewalld leaving, makes this answer stale.
        call(_zoneInterface, "getZoneOfInterface", "(s)", [iface], function(reply) {
            if (serial === watcher._zoneSerial)
                watcher.setZoneState(ZoneLogic.zoneFromReply(ZoneLogic.dbusString(reply.value)))
        }, function(reply) {
            if (serial === watcher._zoneSerial)
                watcher.setZoneState(ZoneLogic.zoneFromError(reply.error.name, reply.error.message))
        })
    }

    function readDefaultZone() {
        if (!firewalld.registered) {
            defaultZone = ""
            return
        }
        call(_name, "getDefaultZone", "", [], function(reply) {
            watcher.defaultZone = ZoneLogic.dbusString(reply.value)
        }, function() {
            watcher.defaultZone = ""
        })
    }

    // Written only on a real change: main.qml drops the service list on every
    // zoneState change, and reading the same zone again must not.
    function setZoneState(state) {
        if (!ZoneLogic.sameZoneState(zoneState, state))
            zoneState = state
    }

    function call(interfaceName, member, signature, args, resolve, reject) {
        var message = {
            service: _name, path: _path, iface: interfaceName,
            member: member, signature: signature, arguments: args
        }
        if (busType === DBus.BusType.Session)
            DBus.SessionBus.asyncCall(message, resolve, reject)
        else
            DBus.SystemBus.asyncCall(message, resolve, reject)
    }

    onIfaceChanged: scheduleZone()

    DBus.DBusServiceWatcher {
        id: firewalld
        busType: watcher.busType
        watchedService: watcher._name
        onRegisteredChanged: {
            if (registered) {
                watcher.refresh()
                return
            }
            // Drops any answer still on its way from the instance that left.
            watcher._zoneSerial++
            watcher.setZoneState({ ok: false, zone: "", error: "stopped" })
            watcher.defaultZone = ""
        }
    }

    // firewalld emits many more signals on these two interfaces. Those without
    // a handler only cost a "No signal handler" line in the journal.
    DBus.SignalWatcher {
        busType: watcher.busType
        // Without a service the watcher receives nothing (Plasma 6.6.6).
        service: watcher._name
        path: watcher._path
        iface: watcher._name

        function dbusDefaultZoneChanged(zone) {
            watcher.defaultZone = ZoneLogic.dbusString(zone)
        }
        function dbusReloaded() {
            watcher.refresh()
        }
    }

    // The arguments say which interface moved where, but asking again is
    // simpler and cannot disagree with firewalld.
    DBus.SignalWatcher {
        busType: watcher.busType
        service: watcher._name
        path: watcher._path
        iface: watcher._zoneInterface

        function dbusInterfaceAdded() { watcher.scheduleZone() }
        function dbusInterfaceRemoved() { watcher.scheduleZone() }
        function dbusZoneOfInterfaceChanged() { watcher.scheduleZone() }
        function dbusZoneChanged() { watcher.scheduleZone() }
    }

    Timer {
        id: debounce
        interval: 50
        onTriggered: watcher.queryZone()
    }

    Timer {
        interval: Math.max(watcher.fallbackInterval, 1)
        running: firewalld.registered && watcher.fallbackInterval > 0
        repeat: true
        onTriggered: watcher.refresh()
    }

    Component.onCompleted: refresh()
}
