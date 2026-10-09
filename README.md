# Firewall Zone

A Plasma 6 panel widget showing the firewalld zone currently applied to the
primary network interface. Useful on laptops, where the zone changes with the
network: `home` behind your own router, `public` everywhere else.

Read-only by design. It runs no privileged command, installs no root helper and
adds no polkit rule.

## What it can and cannot show

The widget reads everything over D-Bus and starts no process to do so. From
NetworkManager it takes the interface of the primary connection; from
firewalld, the zone of that interface and the default zone. Both services send
a signal on every change and the widget asks again at once. A check every 60 s
catches a signal that went missing.

With a full-tunnel VPN, NetworkManager's primary connection is the one carrying
the tunnel, so the widget shows the zone of the physical interface (for example
`wlo1`), not of `tun0`. Version 1.1 read `ip route` and showed the tunnel.

The firewalld calls it makes, `getZoneOfInterface` and `getDefaultZone`, belong
to the `FirewallD1.info` polkit family, which is `allow_active=yes`. No password
dialog can come out of them anyway: Plasma's D-Bus plugin never allows
interactive authorisation, so a call that would need it just fails.

Listing the services and ports open in a zone is another matter. It falls in
`FirewallD1.config.info`, which is `auth_admin_keep`, and `/etc/firewalld` is
`750 root:root`, so its XML is no help either. That view is therefore behind an
explicit button in the popup, which warns that it asks for a password.

| | refresh |
|---|---|
| zone, interface, default zone | at once, on firewalld and NetworkManager signals |
| open services and ports | when you ask, and shows when it was read |

Opening a port elsewhere — in `firewall-config`, or with `firewall-cmd` — is
therefore not picked up on its own. The popup timestamps its answer and offers a
Refresh button. Switching zone discards the lists outright, since they no longer
describe the zone you are in.

## The panel icon

A shield tinted from the widget's own monochrome SVG, not from the icon theme —
themes disagree wildly on what a "security-high" glyph looks like, and some
reduce it to a badge you cannot read at panel size.

| colour | meaning |
|---|---|
| green | firewalld running, interface in a trusted zone (`home`, `internal`, `work`, `trusted`) |
| orange | firewalld running, interface anywhere else — `public`, `block`, `drop`, or a zone the widget does not know |
| red | firewalld is not running |
| grey | no network connection, or NetworkManager not running |

A stopped firewall outranks the zone: it is the one state worth interrupting
for. Unknown zones take the cautious colour rather than the reassuring one.

The four colours are settings — right-click the widget, Configure, Colours.

Whether firewalld is up comes from the bus itself: the widget watches the name
`org.fedoraproject.FirewallD1`. `firewall-cmd --state` would have been the
obvious choice but reaches `FirewallD1.config`, so it asks for a password.

## Requirements

- Plasma 6.4 or later, for the D-Bus signal watcher. On an older Plasma, use
  release v1.1.
- firewalld
- NetworkManager

## Install

    git clone https://github.com/rcspam/plasma-firewall-zone.git
    cd plasma-firewall-zone
    kpackagetool6 --type Plasma/Applet --install package/

Then right-click your panel, choose "Add or Manage Widgets", search for
"Firewall Zone" and drag it onto the panel.

If it does not show up in the list, refresh KDE's service cache with
`kbuildsycoca6` and look again.

## Upgrade

From the clone:

    git pull
    rm -rf ~/.cache/plasmashell/qmlcache
    kpackagetool6 --type Plasma/Applet --upgrade package/
    kquitapp6 plasmashell && kstart plasmashell

Clearing the QML cache and restarting plasmashell is not optional: without it
the previously compiled QML stays in use and the update appears to do nothing.

## Remove

    kpackagetool6 --type Plasma/Applet --remove net.rcspam.firewallzone

## Tests

    tests/run.sh

runs the whole suite. The decision logic lives in
`package/contents/ui/ZoneLogic.js`, free of any QML dependency, and is covered
by `tests/tst_zonelogic.qml`. `tests/tst_commandrunner.qml` covers how the two
button commands are handed to Plasma's executable engine; it runs a few
harmless shell commands for real. The D-Bus watchers are tested in
`tests/dbus/` against fake NetworkManager and firewalld services
(`tests/dbus/fake_services.py`, Python with Gio), on a private session bus that
`run.sh` starts and tears down.

It needs Plasma 6.4, `python3-gi`, `gdbus` and `dbus-run-session` (package
`dbus-daemon` or `dbus-bin`, depending on the distribution). `run.sh` calls
`/usr/lib/qt6/bin/qmltestrunner`; set `QMLTESTRUNNER` to use another one. Extra
arguments are passed on to it.

`qmltestrunner -input tests/` alone still runs the unit tests and skips the
D-Bus ones.
