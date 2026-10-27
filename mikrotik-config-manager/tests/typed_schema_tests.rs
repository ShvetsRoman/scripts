use mikrotik_config_manager::typed_config::{BridgeConfig, InterfacesConfig, WirelessConfig};

// Перевірка: невідомі поля й некоректні типи
// відхиляються суворими serde-схемами.
#[test]
fn typed_interfaces_reject_unknown_fields_and_wrong_types() {
    let valid = "[interfaces.ether1]\nname='WAN'\nenabled=true\ncomment='WAN'\n";
    assert!(toml::from_str::<InterfacesConfig>(valid).is_ok());
    for invalid in [
        valid.replace("enabled=true", "enabled='true'"),
        format!("{valid}legacy_field='old'\n"),
        valid.replace("name='WAN'\n", ""),
    ] {
        assert!(toml::from_str::<InterfacesConfig>(&invalid).is_err());
    }
}

#[test]
fn typed_bridge_rejects_unknown_port_fields_and_wrong_reference_types() {
    let valid = "[bridge.lan]\nname='bridge-lan'\nenabled=true\nprotocol_mode='rstp'\n[ports.ether2]\nbridge='@bridge.lan'\nenabled=true\nhw=true\n";
    assert!(toml::from_str::<BridgeConfig>(valid).is_ok());
    for invalid in [
        valid.replace("hw=true", "hw='true'"),
        format!("{valid}unknown='legacy'\n"),
        valid.replace("bridge='@bridge.lan'", "bridge=true"),
    ] {
        assert!(toml::from_str::<BridgeConfig>(&invalid).is_err());
    }
}

#[test]
fn typed_wireless_rejects_incomplete_security_and_legacy_radio_types() {
    let valid = "[wireless]\nenabled=false\ndriver='legacy'\n[security.home]\nname='wifi'\nauthentication='wpa2-psk'\npassword_source='manual'\n";
    assert!(toml::from_str::<WirelessConfig>(valid).is_ok());
    for invalid in [
        valid.replace("password_source='manual'\n", ""),
        valid.replace("authentication='wpa2-psk'", "authentication=false"),
        format!("{valid}unknown='legacy'\n"),
    ] {
        assert!(toml::from_str::<WirelessConfig>(&invalid).is_err());
    }
}
