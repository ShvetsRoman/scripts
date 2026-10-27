use mikrotik_config_manager::typed_config::{read_typed, ServicesConfig};
use std::path::Path;

#[test]
fn service_profiles_keep_management_and_discovery() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    for profile in ["test", "hap-ac"] {
        let cfg: ServicesConfig =
            read_typed(&root.join("routers").join(profile).join("services.toml")).unwrap();
        assert_ne!(cfg.services.ssh.port, cfg.services.winbox.port);
        assert_eq!(cfg.discovery.interface_list, "@lists.lan");
    }
}

#[test]
fn service_schema_rejects_wrong_bool_and_unknown_keys() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let text = std::fs::read_to_string(root.join("routers/test/services.toml")).unwrap();
    assert!(toml::from_str::<ServicesConfig>(
        &text.replace("enabled = true", "enabled = \"true\"")
    )
    .is_err());
    assert!(toml::from_str::<ServicesConfig>(&format!("{text}\n[extra]\nvalue = 1\n")).is_err());
}

#[test]
fn service_lan_limit_is_explicit_and_strictly_boolean() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    for profile in ["test", "hap-ac"] {
        let text =
            std::fs::read_to_string(root.join("routers").join(profile).join("services.toml"))
                .unwrap();
        let cfg: ServicesConfig = toml::from_str(&text).unwrap();
        let original = format!("limit_to_lan = {}", cfg.services.ssh.limit_to_lan);
        let without = text.replacen(&original, "", 1);
        assert!(toml::from_str::<ServicesConfig>(&without).is_err());
        let invalid = text.replacen(&original, "limit_to_lan = \"true\"", 1);
        assert!(toml::from_str::<ServicesConfig>(&invalid).is_err());
    }
}
