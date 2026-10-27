use super::reference_error::{ValidationCode, ValidationError};
use mikrotik_config_manager::typed_config::{
    BridgeConfig, DhcpConfig, InterfacesConfig, ListsConfig, WirelessConfig,
};
use std::collections::HashSet;

// Перевіряємо назви декларативних ресурсів без проміжної рядкової мапи.
fn unique_names<'a>(
    label: &str,
    names: impl Iterator<Item = &'a str>,
) -> Result<(), ValidationError> {
    let mut seen = HashSet::new();
    for name in names {
        if name.is_empty() || !seen.insert(name) {
            return Err(ValidationError {
                code: ValidationCode::DuplicateOrEmptyName,
                detail: format!("{label}: повторена або порожня назва {name}"),
            });
        }
    }
    Ok(())
}

pub fn validate_names(
    interfaces: &InterfacesConfig,
    bridge: &BridgeConfig,
    lists: &ListsConfig,
    dhcp: &DhcpConfig,
    wireless: &WirelessConfig,
) -> Result<(), ValidationError> {
    unique_names(
        "Interfaces",
        interfaces
            .interfaces
            .values()
            .map(|entry| entry.name.as_str()),
    )?;
    unique_names(
        "Bridge",
        bridge.bridge.values().map(|entry| entry.name.as_str()),
    )?;
    unique_names(
        "Interface Lists",
        lists.lists.values().map(|entry| entry.name.as_str()),
    )?;
    unique_names("DHCP Pool", std::iter::once(dhcp.pool.lan.name.as_str()))?;
    unique_names(
        "DHCP Server",
        std::iter::once(dhcp.server.lan.name.as_str()),
    )?;
    unique_names(
        "Wi-Fi Security",
        wireless.security.values().map(|entry| entry.name.as_str()),
    )?;

    // Порти мосту вказують на існуючі логічні ID фізичних інтерфейсів.
    for id in bridge.ports.keys() {
        if !interfaces.interfaces.contains_key(id) {
            return Err(ValidationError {
                code: ValidationCode::UnknownBridgePort,
                detail: format!("Bridge: невідомий інтерфейс {id}"),
            });
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use mikrotik_config_manager::typed_config::read_typed;
    use std::path::PathBuf;

    fn profile(
        router: &str,
    ) -> (
        InterfacesConfig,
        BridgeConfig,
        ListsConfig,
        DhcpConfig,
        WirelessConfig,
    ) {
        let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("routers")
            .join(router);
        (
            read_typed(&dir.join("interfaces.toml")).unwrap(),
            read_typed(&dir.join("bridge.toml")).unwrap(),
            read_typed(&dir.join("lists.toml")).unwrap(),
            read_typed(&dir.join("dhcp.toml")).unwrap(),
            read_typed(&dir.join("wireless.toml")).unwrap(),
        )
    }

    #[test]
    fn typed_names_accept_both_profiles() {
        for router in ["test", "hap-ac"] {
            let (i, b, l, d, w) = profile(router);
            validate_names(&i, &b, &l, &d, &w).unwrap();
        }
    }

    #[test]
    fn typed_names_reject_duplicate_and_unknown_bridge_port() {
        let (mut i, mut b, l, d, w) = profile("hap-ac");
        let copied_name = i.interfaces.values().next().unwrap().name.clone();
        let other = i.interfaces.values_mut().nth(1).unwrap();
        other.name = copied_name;
        assert!(
            validate_names(&i, &b, &l, &d, &w).unwrap_err().code
                == ValidationCode::DuplicateOrEmptyName
        );
        let (i, _, _, _, _) = profile("hap-ac");
        let original = b.ports.values().next().unwrap();
        let bridge_name = original.bridge.clone();
        let enabled = original.enabled;
        let hw = original.hw;
        b.ports.insert(
            "unknown-physical-id".into(),
            mikrotik_config_manager::typed_config::BridgePort {
                bridge: bridge_name,
                enabled,
                hw,
            },
        );
        assert!(
            validate_names(&i, &b, &l, &d, &w).unwrap_err().code
                == ValidationCode::UnknownBridgePort
        );
    }
}
