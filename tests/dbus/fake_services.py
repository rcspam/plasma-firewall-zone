#!/usr/bin/env python3
"""Fake NetworkManager and firewalld on the session bus, for the D-Bus tests.

Each service owns its name on a connection of its own, as two daemons would,
so stopping one never disturbs the other. A third name exposes the control
interface the QML tests drive to change state and emit signals.

Only what the widget reads is implemented. State follows the real services as
observed on NetworkManager 1.46 and firewalld 2.1.
"""
import signal

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

NM_NAME = "org.freedesktop.NetworkManager"
NM_PATH = "/org/freedesktop/NetworkManager"
FW_NAME = "org.fedoraproject.FirewallD1"
FW_PATH = "/org/fedoraproject/FirewallD1"
FW_ZONE = "org.fedoraproject.FirewallD1.zone"
CTL_NAME = "net.rcspam.firewallzone.TestControl"
CTL_PATH = "/net/rcspam/firewallzone/TestControl"

PROPS_XML = """<node><interface name="org.freedesktop.DBus.Properties">
  <method name="Get">
    <arg type="s" direction="in"/><arg type="s" direction="in"/>
    <arg type="v" direction="out"/>
  </method>
  <signal name="PropertiesChanged">
    <arg type="s"/><arg type="a{sv}"/><arg type="as"/>
  </signal>
</interface></node>"""

FW_XML = """<node>
<interface name="org.fedoraproject.FirewallD1">
  <method name="getDefaultZone"><arg type="s" direction="out"/></method>
  <signal name="DefaultZoneChanged"><arg type="s"/></signal>
  <signal name="Reloaded"/>
</interface>
<interface name="org.fedoraproject.FirewallD1.zone">
  <method name="getZoneOfInterface">
    <arg type="s" direction="in"/><arg type="s" direction="out"/>
  </method>
  <signal name="InterfaceAdded"><arg type="s"/><arg type="s"/></signal>
  <signal name="InterfaceRemoved"><arg type="s"/><arg type="s"/></signal>
  <signal name="ZoneOfInterfaceChanged"><arg type="s"/><arg type="s"/></signal>
  <signal name="ZoneChanged"><arg type="s"/><arg type="s"/></signal>
</interface></node>"""

CTL_XML = """<node><interface name="net.rcspam.firewallzone.TestControl">
  <method name="Reset"/>
  <method name="SetPrimary">
    <arg type="s" direction="in"/><arg type="s" direction="in"/>
    <arg type="b" direction="in"/>
  </method>
  <method name="EmitNetworkManagerProperties"><arg type="as" direction="in"/></method>
  <method name="SetZone">
    <arg type="s" direction="in"/><arg type="s" direction="in"/>
    <arg type="as" direction="in"/>
  </method>
  <method name="SetDefaultZone"><arg type="s" direction="in"/></method>
  <method name="Reload"/>
  <method name="StopService"><arg type="s" direction="in"/></method>
  <method name="StartService"><arg type="s" direction="in"/></method>
  <method name="DelayNext">
    <arg type="s" direction="in"/><arg type="u" direction="in"/>
  </method>
  <method name="FailNext">
    <arg type="s" direction="in"/><arg type="s" direction="in"/>
    <arg type="s" direction="in"/>
  </method>
  <method name="CallCount">
    <arg type="s" direction="in"/><arg type="u" direction="out"/>
  </method>
</interface></node>"""

DO_NOT_QUEUE = 4


class Failure(Exception):
    def __init__(self, name, message):
        super().__init__(message)
        self.name = name
        self.message = message


def new_connection():
    address = Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, None)
    flags = (Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
             | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION)
    return Gio.DBusConnection.new_for_address_sync(address, flags, None, None)


def bus_call(conn, member, name):
    conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                   "org.freedesktop.DBus", member,
                   GLib.Variant("(su)", (name, DO_NOT_QUEUE)) if member == "RequestName"
                   else GLib.Variant("(s)", (name,)),
                   None, Gio.DBusCallFlags.NONE, -1, None)


class Fake:
    def __init__(self):
        self.nm = new_connection()
        self.fw = new_connection()
        self.ctl = new_connection()
        self.owners = {NM_NAME: self.nm, FW_NAME: self.fw}
        self.props = {}
        self.serial = 0

        props = Gio.DBusNodeInfo.new_for_xml(PROPS_XML).interfaces[0]
        self.props_info = props
        for info in Gio.DBusNodeInfo.new_for_xml(FW_XML).interfaces:
            self.fw.register_object(FW_PATH, info, self.on_firewalld, None, None)
        ctl = Gio.DBusNodeInfo.new_for_xml(CTL_XML).interfaces[0]
        self.ctl.register_object(CTL_PATH, ctl, self.on_control, None, None)

        self.reset()
        # Taken last: the tests wait for this name before they start.
        bus_call(self.ctl, "RequestName", CTL_NAME)

    # State ---------------------------------------------------------------

    def reset(self):
        self.zones = {"wlo1": "home", "enp3s0": "public"}
        self.default_zone = "public"
        self.delays = {}
        self.failures = {}
        self.calls = {}
        self.set_nm_object(NM_PATH, NM_NAME, {"PrimaryConnection": GLib.Variant("o", "/")})
        self.set_primary("wlo1", "wlo1", False)
        for name in self.owners:
            self.start(name)

    def set_nm_object(self, path, interface, values):
        if path not in self.props:
            self.nm.register_object(path, self.props_info, self.on_network_manager, None, None)
            self.props[path] = {}
        self.props[path].setdefault(interface, {}).update(values)

    # A new connection and device object each time, as NetworkManager does:
    # a reply about an older connection then reads that older device, which is
    # what lets the tests catch a stale answer being used.
    def set_primary(self, ip_interface, interface_name, emit):
        if not ip_interface and not interface_name:
            primary = "/"
        else:
            self.serial += 1
            primary = "%s/ActiveConnection/%d" % (NM_PATH, self.serial)
            device = "%s/Devices/%d" % (NM_PATH, self.serial)
            self.set_nm_object(primary, NM_NAME + ".Connection.Active",
                               {"Devices": GLib.Variant("ao", [device])})
            self.set_nm_object(device, NM_NAME + ".Device",
                               {"IpInterface": GLib.Variant("s", ip_interface),
                                "Interface": GLib.Variant("s", interface_name)})
        self.set_nm_object(NM_PATH, NM_NAME, {"PrimaryConnection": GLib.Variant("o", primary)})
        if emit:
            self.emit_nm_properties(["PrimaryConnection"])

    def emit_nm_properties(self, names):
        current = self.props[NM_PATH][NM_NAME]
        changed = {n: current.get(n, GLib.Variant("s", "")) for n in names}
        self.nm.emit_signal(None, NM_PATH, "org.freedesktop.DBus.Properties",
                            "PropertiesChanged",
                            GLib.Variant("(sa{sv}as)", (NM_NAME, changed, [])))

    def start(self, name):
        bus_call(self.owners[name], "RequestName", name)

    def stop(self, name):
        bus_call(self.owners[name], "ReleaseName", name)

    # Calls from the widget -------------------------------------------------

    # Counts, fails or delays a call as the tests asked. The reply is computed
    # when the call arrives and sent later, so a delayed reply describes the
    # state at the time it was asked.
    def answer(self, member, invocation, compute):
        self.calls[member] = self.calls.get(member, 0) + 1
        failure = self.failures.pop(member, None)
        delay = self.delays.pop(member, 0)
        if failure is None:
            try:
                value = compute()
                send = lambda: invocation.return_value(value)
            except Failure as error:
                failure = (error.name, error.message)
        if failure is not None:
            send = lambda: invocation.return_dbus_error(*failure)
        if delay:
            GLib.timeout_add(delay, lambda: send() and False)
        else:
            send()

    def on_network_manager(self, conn, sender, path, interface, member, params, invocation):
        def get():
            wanted_interface, prop = params.unpack()
            try:
                value = self.props[path][wanted_interface][prop]
            except KeyError:
                raise Failure("org.freedesktop.DBus.Error.InvalidArgs",
                              "No such interface or property")
            return GLib.Variant("(v)", (value,))
        self.answer(member, invocation, get)

    def on_firewalld(self, conn, sender, path, interface, member, params, invocation):
        def get_default_zone():
            return GLib.Variant("(s)", (self.default_zone,))

        def get_zone_of_interface():
            (name,) = params.unpack()
            if not name:
                raise Failure("org.fedoraproject.FirewallD1.Exception",
                              "INVALID_INTERFACE: ''")
            return GLib.Variant("(s)", (self.zones.get(name, ""),))

        compute = {"getDefaultZone": get_default_zone,
                   "getZoneOfInterface": get_zone_of_interface}[member]
        self.answer(member, invocation, compute)

    # Control interface -----------------------------------------------------

    def on_control(self, conn, sender, path, interface, member, params, invocation):
        args = params.unpack()
        result = None
        if member == "Reset":
            self.reset()
        elif member == "SetPrimary":
            self.set_primary(*args)
        elif member == "EmitNetworkManagerProperties":
            self.emit_nm_properties(args[0])
        elif member == "SetZone":
            name, zone, signals = args
            if zone:
                self.zones[name] = zone
            else:
                self.zones.pop(name, None)
            for signal_name in signals:
                self.fw.emit_signal(None, FW_PATH, FW_ZONE, signal_name,
                                    GLib.Variant("(ss)", (zone, name)))
        elif member == "SetDefaultZone":
            self.default_zone = args[0]
            self.fw.emit_signal(None, FW_PATH, FW_NAME, "DefaultZoneChanged",
                                GLib.Variant("(s)", (args[0],)))
        elif member == "Reload":
            self.fw.emit_signal(None, FW_PATH, FW_NAME, "Reloaded", None)
        elif member == "StopService":
            self.stop(args[0])
        elif member == "StartService":
            self.start(args[0])
        elif member == "DelayNext":
            self.delays[args[0]] = args[1]
        elif member == "FailNext":
            self.failures[args[0]] = (args[1], args[2])
        elif member == "CallCount":
            result = GLib.Variant("(u)", (self.calls.get(args[0], 0),))
        invocation.return_value(result)


def main():
    loop = GLib.MainLoop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: loop.quit() or False)
    Fake()
    loop.run()


if __name__ == "__main__":
    main()
