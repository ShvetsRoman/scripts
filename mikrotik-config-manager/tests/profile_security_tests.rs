//! Безпека профілів: типізована конфігурація, секрети та перевірка полів.
use mikrotik_config_manager::typed_config::{
    read_typed, ConnectionConfig, ManagerConfig, SystemConfig, WirelessConfig,
};
use std::path::Path;

#[test]
fn both_profiles_keep_strict_typed_connection_and_secrets_external() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    for profile in ["test", "hap-ac"] {
        let dir = root.join("routers").join(profile);
        let connection: ConnectionConfig = read_typed(&dir.join("connection.toml")).unwrap();
        assert!(!connection.connection.host.is_empty());
        assert!(!connection.connection.user.is_empty());
        assert!(connection.connection.port > 0);
        let system: SystemConfig = read_typed(&dir.join("system.toml")).unwrap();
        assert!(!system.users.is_empty());
        let wireless: WirelessConfig = read_typed(&dir.join("wireless.toml")).unwrap();
        for radio in wireless
            .wireless
            .radios
            .values()
            .filter(|radio| radio.enabled)
        {
            let reference = radio.security.strip_prefix("@security.").unwrap();
            assert!(wireless.security.contains_key(reference));
        }
        for file in [
            "connection.toml",
            "system.toml",
            "wireless.toml",
            "wireguard.toml",
        ] {
            let source = std::fs::read_to_string(dir.join(file)).unwrap();
            assert!(!source.lines().any(|line| {
                let key = line.split_once('=').map(|(key, _)| key.trim());
                matches!(key, Some("private_key" | "preshared_key" | "password"))
            }));
        }
    }
}

#[test]
fn manager_schema_and_connection_reject_unknown_or_invalid_fields() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let manager: ManagerConfig = read_typed(&root.join("config/manager.toml")).unwrap();
    assert!(!manager.manager.language.is_empty());
    let valid = "[connection]\nhost = '192.0.2.1'\nport = 22\nuser = 'admin'\nidentity_file = '~/.ssh/id_ed25519'\n";
    assert!(toml::from_str::<ConnectionConfig>(valid).is_ok());
    assert!(
        toml::from_str::<ConnectionConfig>(&valid.replace("port = 22", "port = '22'")).is_err()
    );
    assert!(toml::from_str::<ConnectionConfig>(&format!("{valid}extra = 1\n")).is_err());
    assert!(toml::from_str::<ConnectionConfig>(&valid.replace("user = 'admin'\n", "")).is_err());
    assert!(toml::from_str::<ManagerConfig>(
        "[manager]\nlanguage = 'uk'\ncolor = 'auto'\ndefault_router = ''\nunknown = true"
    )
    .is_err());
}
