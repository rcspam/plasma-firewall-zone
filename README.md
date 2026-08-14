# Firewall Zone

A Plasma 6 panel widget showing the firewalld zone currently applied to the
primary network interface. Useful on laptops, where the zone changes with the
network: `home` behind your own router, `public` everywhere else.

Read-only by design. It runs no privileged command, installs no root helper and
adds no polkit rule.

## What it can and cannot show

firewalld splits its polkit actions in two families. `FirewallD1.info` is
`allow_active=yes`, `FirewallD1.config.info` is `auth_admin_keep` — the second
one pops up a password dialog. The widget polls **only** queries from the first
family: `--get-zone-of-interface`, `--get-active-zones`, `--get-default-zone`.

Listing the services and ports open in a zone falls in the second family, and
`/etc/firewalld` is `750 root:root`, so its XML is no help either. That view is
therefore behind an explicit button in the popup, which warns that it asks for a
password. Nothing in the polling loop ever authenticates — a guard in the code
rejects any privileged query added to it later.

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
