// Follows NetworkManager's primary connection and exposes the interface it
// goes out through. Everything is read over D-Bus and refreshed on
// PropertiesChanged, so no process is started; a slow fallback timer catches a
// signal that went missing.
import QtQuick
import org.kde.plasma.workspace.dbus as DBus
import "ZoneLogic.js" as ZoneLogic

Item {
    id: watcher

    property int busType: DBus.BusType.System
    // 0 disables the fallback check.
    property int fallbackInterval: 60000

    readonly property bool available: nmService.registered
    // Interface of the primary connection, empty without one.
    property string iface: ""

    readonly property string _name: "org.freedesktop.NetworkManager"
    readonly property string _path: "/org/freedesktop/NetworkManager"
    property int _serial: 0

    // Primary connection, then its first device, then that device's names.
    // Every run takes a number, and each step first checks it still belongs to
    // the latest run: a late answer from an older one would bring back an
    // interface that is no longer primary.
    function refresh() {
        var serial = ++_serial
        if (!nmService.registered) {
            iface = ""
            return
        }
        // watcher is null once the item is destroyed, with answers still due.
        function current() { return !!watcher && serial === watcher._serial }
        function fail() {
            if (current())
                watcher.iface = ""
        }
        getProperty(_path, _name, "PrimaryConnection", function(value) {
            if (!current())
                return
            var connection = ZoneLogic.dbusString(value)
            if (connection === "" || connection === "/") {
                watcher.iface = ""
                return
            }
            getProperty(connection, _name + ".Connection.Active", "Devices", function(devices) {
                if (!current())
                    return
                var device = ZoneLogic.firstString(devices)
                if (device === "") {
                    watcher.iface = ""
                    return
                }
                getProperty(device, _name + ".Device", "IpInterface", function(ipInterface) {
                    if (!current())
                        return
                    getProperty(device, _name + ".Device", "Interface", function(interfaceName) {
                        if (!current())
                            return
                        watcher.iface = ZoneLogic.deviceInterface(
                            ZoneLogic.dbusString(ipInterface),
                            ZoneLogic.dbusString(interfaceName))
                    }, fail)
                }, fail)
            }, fail)
        }, fail)
    }

    // resolve gets the property value, still wrapped; reject gets the reply.
    function getProperty(path, interfaceName, property, resolve, reject) {
        // Never call a service that is not on the bus: on a system that ships
        // a D-Bus activation file for it, the call would start it.
        if (!nmService.registered) {
            reject(null)
            return
        }
        var message = {
            service: _name, path: path,
            iface: "org.freedesktop.DBus.Properties", member: "Get",
            signature: "(ss)", arguments: [interfaceName, property]
        }
        var ok = function(reply) { resolve(reply.value) }
        if (busType === DBus.BusType.Session)
            DBus.SessionBus.asyncCall(message, ok, reject)
        else
            DBus.SystemBus.asyncCall(message, ok, reject)
    }

    DBus.DBusServiceWatcher {
        id: nmService
        busType: watcher.busType
        watchedService: watcher._name
        // Arriving: read everything. Leaving: refresh() empties iface and its
        // new number drops any answer still on its way.
        onRegisteredChanged: watcher.refresh()
    }

    DBus.SignalWatcher {
        busType: watcher.busType
        // Without a service the watcher receives nothing (Plasma 6.6.6).
        service: watcher._name
        path: watcher._path
        iface: "org.freedesktop.DBus.Properties"

        // NetworkManager announces many properties on this object
        // (Connectivity, ActiveConnections...). Only a new primary connection
        // changes what the widget shows.
        function dbusPropertiesChanged(interfaceName, changed, invalidated) {
            if (ZoneLogic.dbusString(interfaceName) === watcher._name
                    && changed.PrimaryConnection !== undefined)
                watcher.refresh()
        }
    }

    Timer {
        interval: Math.max(watcher.fallbackInterval, 1)
        running: nmService.registered && watcher.fallbackInterval > 0
        repeat: true
        onTriggered: watcher.refresh()
    }

    Component.onCompleted: refresh()
}
