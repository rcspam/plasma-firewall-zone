import QtQuick
import QtTest
import "../package/contents/ui/ZoneLogic.js" as ZoneLogic

TestCase {
    name: "ZoneLogic"

    function test_parseZone_nominal() {
        var r = ZoneLogic.parseZone("home\n", "", 0)
        compare(r.ok, true)
        compare(r.zone, "home")
        compare(r.error, "")
    }

    // firewall-cmd prints "no zone" on stderr, not stdout. Both spellings are
    // accepted so a future firewalld release moving it back cannot break us.
    function test_parseZone_interface_without_zone_on_stderr() {
        var r = ZoneLogic.parseZone("", "no zone\n", 2)
        compare(r.ok, false)
        compare(r.error, "no-zone")
    }

    function test_parseZone_interface_without_zone_on_stdout() {
        var r = ZoneLogic.parseZone("no zone\n", "", 2)
        compare(r.ok, false)
        compare(r.error, "no-zone")
    }

    function test_parseZone_offline() {
        var r = ZoneLogic.parseZone("", "Error: INVALID_INTERFACE\n", 104)
        compare(r.ok, false)
        compare(r.error, "offline")
    }

    function test_parseZone_dbus_timeout() {
        var r = ZoneLogic.parseZone("", "Error: Did not receive a reply. Possible causes include: the remote application did not send a reply\n", 1)
        compare(r.ok, false)
        compare(r.error, "busy")
    }

    function test_parseZone_firewalld_stopped() {
        var r = ZoneLogic.parseZone("", "FirewallD is not running\n", 252)
        compare(r.ok, false)
        compare(r.error, "stopped")
    }

    function test_trustLevel() {
        compare(ZoneLogic.trustLevel("home"), "trusted")
        compare(ZoneLogic.trustLevel("internal"), "trusted")
        compare(ZoneLogic.trustLevel("public"), "closed")
        compare(ZoneLogic.trustLevel("block"), "blocked")
        compare(ZoneLogic.trustLevel("drop"), "blocked")
        compare(ZoneLogic.trustLevel("wintermute"), "unknown")
    }

    function test_iconFor() {
        compare(ZoneLogic.iconFor({ ok: true, zone: "home", error: "" }), "security-high")
        compare(ZoneLogic.iconFor({ ok: true, zone: "public", error: "" }), "security-medium")
        compare(ZoneLogic.iconFor({ ok: true, zone: "drop", error: "" }), "security-low")
        compare(ZoneLogic.iconFor({ ok: false, zone: "", error: "offline" }), "network-disconnect")
    }

    function test_parseList() {
        compare(ZoneLogic.parseList("dhcpv6-client kdeconnect mdns\n").length, 3)
        compare(ZoneLogic.parseList("\n").length, 0)
        compare(ZoneLogic.parseList("").length, 0)
    }

    // Output of `firewall-cmd --zone=X --list-all`, as produced by
    // print_zone_policy_info() in firewall/command.py. One query instead of two
    // means one password prompt instead of two.
    readonly property string listAllSample:
        "home (active)\n" +
        "  target: default\n" +
        "  icmp-block-inversion: no\n" +
        "  interfaces: wlo1\n" +
        "  sources: \n" +
        "  services: dhcpv6-client kdeconnect mdns samba-client syncthing\n" +
        "  ports: 8384/tcp 22000/tcp\n" +
        "  protocols: \n" +
        "  forward: yes\n" +
        "  masquerade: no\n" +
        "  forward-ports: \n" +
        "  source-ports: \n" +
        "  icmp-blocks: \n" +
        "  rich rules: \n"

    function test_parseListAll_extracts_services_and_ports() {
        var r = ZoneLogic.parseListAll(listAllSample)
        compare(r.services.length, 5)
        compare(r.services[0], "dhcpv6-client")
        compare(r.ports.length, 2)
        compare(r.ports[1], "22000/tcp")
    }

    // "source-ports:" and "forward-ports:" also end in "ports:" — matching them
    // would silently report the wrong list.
    function test_parseListAll_ignores_lookalike_keys() {
        var s = "public\n  forward-ports: 80:proxy:8080\n  source-ports: 53/udp\n  ports: \n  services: ssh\n"
        var r = ZoneLogic.parseListAll(s)
        compare(r.ports.length, 0)
        compare(r.services.length, 1)
        compare(r.services[0], "ssh")
    }

    function test_parseListAll_handles_empty_and_garbage() {
        var r = ZoneLogic.parseListAll("")
        compare(r.services.length, 0)
        compare(r.ports.length, 0)
        var g = ZoneLogic.parseListAll("Error: INVALID_ZONE\n")
        compare(g.services.length, 0)
        compare(g.ports.length, 0)
    }

    // A declined password gives an empty answer. Reporting that as "no service
    // is open" would be a lie about the firewall, so the parser has to say
    // whether it actually read anything.
    function test_parseListAll_reports_whether_it_read_anything() {
        compare(ZoneLogic.parseListAll(listAllSample).ok, true)
        compare(ZoneLogic.parseListAll("").ok, false)
        compare(ZoneLogic.parseListAll("Error: NOT_AUTHORIZED\n").ok, false)
        // A zone with nothing open still answers, with empty values.
        compare(ZoneLogic.parseListAll("drop\n  target: DROP\n  services: \n  ports: \n").ok, true)
    }

    // The panel icon is tinted from one of four keys. Which one wins matters:
    // a stopped firewall is the alarming case and must not be masked by the
    // zone the interface happens to sit in.
    function test_colourKey_firewall_down_wins() {
        compare(ZoneLogic.colourKey({ ok: true, zone: "home", error: "" }, false), "down")
        compare(ZoneLogic.colourKey({ ok: false, zone: "", error: "offline" }, false), "down")
    }

    function test_colourKey_trusted_zones() {
        compare(ZoneLogic.colourKey({ ok: true, zone: "home", error: "" }, true), "trusted")
        compare(ZoneLogic.colourKey({ ok: true, zone: "internal", error: "" }, true), "trusted")
        compare(ZoneLogic.colourKey({ ok: true, zone: "work", error: "" }, true), "trusted")
    }

    // Everything that is not a zone you trust reads as "closed": public on a
    // café network, but also block, drop and any zone this widget has never
    // heard of. Erring towards the cautious colour is deliberate.
    function test_colourKey_closed_zones() {
        compare(ZoneLogic.colourKey({ ok: true, zone: "public", error: "" }, true), "closed")
        compare(ZoneLogic.colourKey({ ok: true, zone: "external", error: "" }, true), "closed")
        compare(ZoneLogic.colourKey({ ok: true, zone: "block", error: "" }, true), "closed")
        compare(ZoneLogic.colourKey({ ok: true, zone: "drop", error: "" }, true), "closed")
        compare(ZoneLogic.colourKey({ ok: true, zone: "docker", error: "" }, true), "closed")
    }

    function test_colourKey_offline() {
        compare(ZoneLogic.colourKey({ ok: false, zone: "", error: "offline" }, true), "offline")
        compare(ZoneLogic.colourKey({ ok: false, zone: "", error: "no-zone" }, true), "offline")
        compare(ZoneLogic.colourKey({ ok: false, zone: "", error: "busy" }, true), "offline")
    }

    function test_parseServiceState() {
        compare(ZoneLogic.parseServiceState("active\n"), true)
        compare(ZoneLogic.parseServiceState("inactive\n"), false)
        compare(ZoneLogic.parseServiceState("failed\n"), false)
        compare(ZoneLogic.parseServiceState(""), false)
        // "activating" is not yet serving requests, but it is on its way up and
        // must not flash the alarming colour on every boot.
        compare(ZoneLogic.parseServiceState("activating\n"), true)
    }

    // Guards the whole point of the widget: a polling query that reaches
    // firewalld's config.info polkit action prompts for a password every tick.
    function test_isFreeQuery_rejects_prompting_commands() {
        verify(ZoneLogic.isFreeQuery("firewall-cmd --get-zone-of-interface=wlo1"))
        verify(ZoneLogic.isFreeQuery("firewall-cmd --get-active-zones"))
        verify(ZoneLogic.isFreeQuery("firewall-cmd --get-default-zone"))
        verify(!ZoneLogic.isFreeQuery("firewall-cmd --zone=home --list-services"))
        verify(!ZoneLogic.isFreeQuery("firewall-cmd --zone=home --list-ports"))
        verify(!ZoneLogic.isFreeQuery("firewall-cmd --state"))
        verify(!ZoneLogic.isFreeQuery("firewall-cmd --permanent --list-all"))
        verify(ZoneLogic.isFreeQuery("systemctl is-active firewalld"))
        verify(!ZoneLogic.isFreeQuery("systemctl restart firewalld"))
    }

    function test_errorText_is_never_empty() {
        var codes = ["no-zone", "offline", "busy", "stopped", "unknown", "nimportequoi"]
        for (var i = 0; i < codes.length; i++)
            verify(ZoneLogic.errorText(codes[i]).length > 0)
    }
}
