//! Сувора типізація і перевірка параметрів WireGuard.
use mikrotik_config_manager::typed_config::WireguardConfig;

const VALID: &str = r#"
[wireguard]
enabled = false
name = "wg-home"
listen_port = 51820
address = "10.77.0.1/24"
allow_wan = false
allow_lan = false
allow_ssh = false
allow_winbox = false
allow_internet = false
"#;

#[test]
fn independent_vpn_permissions_are_required_and_boolean() {
    for name in [
        "allow_wan",
        "allow_lan",
        "allow_ssh",
        "allow_winbox",
        "allow_internet",
    ] {
        let missing = VALID.replace(&format!("{name} = false\n"), "");
        assert!(
            toml::from_str::<WireguardConfig>(&missing).is_err(),
            "{name} cannot be omitted"
        );
        let invalid = VALID.replace(&format!("{name} = false"), &format!("{name} = \"false\""));
        assert!(
            toml::from_str::<WireguardConfig>(&invalid).is_err(),
            "{name} must be boolean"
        );
    }
}

#[test]
fn unknown_wireguard_fields_remain_rejected() {
    let invalid = VALID.replace(
        "allow_winbox = false",
        "unknown_flag = true\nallow_winbox = false",
    );
    assert!(toml::from_str::<WireguardConfig>(&invalid).is_err());
}
