// Тематичні інтеграційні тести. Робочий код не змінено.
#[allow(dead_code)]
mod support;
use std::path::Path;
use support::*;

#[test]
fn example_profiles_exist() {
    for name in [
        "config/manager.toml",
        "routers/test/connection.toml",
        "routers/test/network.toml",
        "routers/test/dhcp.toml",
        "routers/test/dns.toml",
        "routers/test/firewall.toml",
        "locales/uk.lang",
        "locales/en.lang",
    ] {
        assert!(Path::new(name).is_file(), "{name}");
    }
}

#[test]
fn binary_version() {
    let output = cli(&["--version"]);
    assert!(output.status.success());
    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        env!("CARGO_PKG_VERSION")
    );
}

#[test]
fn language_override() {
    let output = cli(&["--lang", "en", "help"]);
    assert!(output.status.success());
    assert!(String::from_utf8_lossy(&output.stdout).contains("Commands:"));
}

#[test]
fn apply_is_blocked() {
    assert!(!cli(&["apply", "test"]).status.success());
}

#[test]
fn unknown_module_fails() {
    assert!(!cli(&["plan", "test", "unknown"]).status.success());
}

#[test]
fn separate_real_and_test_profiles() {
    for profile in ["hap-ac", "test"] {
        let output = cli(&["plan", profile]);
        assert!(
            output.status.success(),
            "{profile}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        let plan = String::from_utf8_lossy(&output.stdout);
        assert!(plan.contains("/ip dhcp-client add"));
        assert!(plan.contains("/ip firewall nat add"));
        assert!(!plan.contains("/import"));
    }
}
#[test]
fn apply_remains_blocked_for_both_profiles() {
    assert!(!cli(&["apply", "hap-ac"]).status.success());
    assert!(!cli(&["apply", "test"]).status.success());
}

#[test]
fn version_matches_cargo_metadata() {
    // Єдине джерело версії: [package].version із Cargo.toml.
    for args in [vec!["--version"], vec!["version"]] {
        let output = cli(&args);
        assert!(output.status.success());
        assert_eq!(
            String::from_utf8_lossy(&output.stdout).trim(),
            env!("CARGO_PKG_VERSION")
        );
    }
    let help = cli(&["help"]);
    assert!(help.status.success());
    assert!(String::from_utf8_lossy(&help.stdout).contains(env!("CARGO_PKG_VERSION")));
}

#[test]
fn declarative_profiles_use_resource_tables() {
    for profile in ["hap-ac", "test"] {
        let root = format!("routers/{profile}");
        let cases = [
            ("interfaces.toml", "[interfaces.ether1]"),
            ("bridge.toml", "[bridge.lan]"),
            ("bridge.toml", "[ports."),
            ("lists.toml", "[lists.wan]"),
            ("lists.toml", "members = [\"@wan\"]"),
            ("dhcp.toml", "[pool.lan]"),
            ("dhcp.toml", "[server.lan]"),
            ("dhcp.toml", "[leases]"),
        ];
        for (file, needle) in cases {
            let body = std::fs::read_to_string(format!("{root}/{file}")).unwrap();
            assert!(body.contains(needle), "{root}/{file}: очікували {needle}");
        }
    }
}

#[test]
fn declaration_is_not_routeros_apply() {
    for profile in ["hap-ac", "test"] {
        for module in [
            "all",
            "interfaces",
            "bridge",
            "lists",
            "network",
            "dhcp",
            "leases",
            "dns",
            "wan",
            "nat",
            "firewall",
        ] {
            let output = cli(&["plan", profile, module]);
            assert!(
                output.status.success(),
                "{profile}/{module}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            let text = String::from_utf8_lossy(&output.stdout);
            assert!(!text.contains("/import"));
        }
        assert!(!cli(&["apply", profile]).status.success());
    }
}

#[test]
fn test_profile_has_no_radio_commands() {
    let output = cli(&["plan", "test", "wireless"]);
    assert!(output.status.success());
    let plan = String::from_utf8_lossy(&output.stdout);
    assert!(!plan.contains("/interface wireless"));
    assert!(!plan.contains("/interface wifi"));
}
