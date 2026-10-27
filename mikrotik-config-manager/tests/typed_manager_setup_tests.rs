use mikrotik_config_manager::typed_config::{
    read_typed, ManagerConfig, SystemConfig, WirelessConfig,
};
use std::path::Path;

#[test]
fn manager_strict_fields_and_profiles_remain_valid() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let config: ManagerConfig = read_typed(&root.join("config/manager.toml")).unwrap();
    assert!(!config.manager.language.is_empty());
    assert!(!config.manager.color.is_empty());

    assert!(toml::from_str::<ManagerConfig>(
        "[manager]\nlanguage = 42\ncolor = 'auto'\ndefault_router = ''"
    )
    .is_err());
    assert!(toml::from_str::<ManagerConfig>(
        "[manager]\nlanguage = 'uk'\ncolor = 'auto'\ndefault_router = ''\nextra = 1"
    )
    .is_err());
    assert!(toml::from_str::<ManagerConfig>("[manager]\nlanguage = 'uk'\ncolor = 'auto'").is_err());
}

#[test]
fn setup_uses_typed_users_and_wifi_references() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    for profile in ["test", "hap-ac"] {
        let dir = root.join("routers").join(profile);
        let system: SystemConfig = read_typed(&dir.join("system.toml")).unwrap();
        assert!(!system.users.is_empty());
        assert!(system.users.values().all(|user| !user.group.is_empty()));
        assert!(system.users.keys().all(|id| !id.is_empty()));
        let wireless: WirelessConfig = read_typed(&dir.join("wireless.toml")).unwrap();
        for radio in wireless.wireless.radios.values().filter(|r| r.enabled) {
            let id = radio.security.strip_prefix("@security.").unwrap();
            assert!(wireless.security.contains_key(id));
        }
    }
}
