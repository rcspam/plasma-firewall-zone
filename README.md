# Firewall Zone

A Plasma 6 panel widget showing the firewalld zone currently applied to the
primary network interface. Useful on laptops, where the zone changes with the
network: `home` behind your own router, `public` everywhere else.

Read-only by design. It runs no privileged command, installs no root helper and
adds no polkit rule.

## Requirements

- Plasma 6
- firewalld, running
- `iproute2`

## Install

    kpackagetool6 --type Plasma/Applet --install package/

Then add "Firewall Zone" from the widget explorer.

## Upgrade

    rm -rf ~/.cache/plasmashell/qmlcache
    kpackagetool6 --type Plasma/Applet --upgrade package/
    kquitapp6 plasmashell && kstart plasmashell

## Remove

    kpackagetool6 --type Plasma/Applet --remove net.rcspam.firewallzone

## Tests

The decision logic lives in `package/contents/ui/ZoneLogic.js`, free of any QML
dependency, and is covered by `tests/tst_zonelogic.qml`:

    qmltestrunner -input tests/

On distributions where `qmltestrunner` in `PATH` is the qtchooser wrapper still
pointing at Qt 5, call the Qt 6 binary directly:

    /usr/lib/qt6/bin/qmltestrunner -input tests/
