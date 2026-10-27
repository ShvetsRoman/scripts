// Регресійні тести суворої serde-моделі без секретів Wi-Fi.
use mikrotik_config_manager::typed_config::{read_typed, WirelessConfig};

#[test]
fn wireless_profiles_keep_radios_and_secret_references() {
    let test: WirelessConfig =
        read_typed(std::path::Path::new("routers/test/wireless.toml")).unwrap();
    assert!(!test.wireless.enabled);
    assert_eq!(test.wireless.driver, "none");
    assert!(test.wireless.radios.is_empty());
    let home: WirelessConfig =
        read_typed(std::path::Path::new("routers/hap-ac/wireless.toml")).unwrap();
    assert!(home.wireless.enabled);
    assert_eq!(home.wireless.radios.len(), 2);
    assert_eq!(home.wireless.radios["wlan1"].security, "@security.wifi");
    assert_eq!(home.wireless.radios["wlan2"].bridge, "@bridge.lan");
    assert_eq!(home.security["wifi"].password_source, "manual");
}

#[test]
fn wireless_schema_rejects_wrong_types_and_unknown_fields() {
    assert!(
        toml::from_str::<WirelessConfig>("[wireless]\nenabled = \"yes\"\ndriver = \"none\"\n")
            .is_err()
    );
    assert!(toml::from_str::<WirelessConfig>(
        "[wireless]\nenabled = false\ndriver = \"none\"\nunknown = 1\n"
    )
    .is_err());
    assert!(toml::from_str::<WirelessConfig>("[wireless]\nenabled = true\ndriver = \"legacy\"\n[security.wifi]\nname = \"wifi\"\nauthentication = \"wpa2-psk\"\npassword_source = 123\n").is_err());
}
