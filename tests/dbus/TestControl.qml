// Drives tests/dbus/fake_services.py from a test case. D-Bus calls are
// asynchronous on the QML side, so both helpers wait for the answer with the
// test case's own tryVerify before returning it.
import QtQuick
import org.kde.plasma.workspace.dbus as DBus

DBus.DBusServiceWatcher {
    id: control
    busType: DBus.BusType.Session
    watchedService: "net.rcspam.firewallzone.TestControl"

    readonly property string missingMessage:
        "fake D-Bus services are not running, start the tests with tests/run.sh"

    // Any call on the session bus. Returns {value, error}, error being
    // "name: message" or "" on success. Values come wrapped, see dbusString().
    function ask(test, service, path, iface, member, signature, args) {
        var box = { done: false, value: undefined, error: "" }
        DBus.SessionBus.asyncCall({
            service: service, path: path, iface: iface,
            member: member, signature: signature, arguments: args
        }, function(reply) {
            box.value = reply.value
            box.done = true
        }, function(reply) {
            box.error = reply.error.name + ": " + reply.error.message
            box.done = true
        })
        test.tryVerify(function() { return box.done }, 3000, member + " got no answer")
        return box
    }

    // A method of the control interface, which must succeed.
    function call(test, member, signature, args) {
        var box = ask(test, watchedService, "/net/rcspam/firewallzone/TestControl",
                      watchedService, member, signature, args)
        test.compare(box.error, "", member + " failed")
        return box.value
    }

    function count(test, member) {
        return Number(String(call(test, "CallCount", "(s)", [member])))
    }
}
