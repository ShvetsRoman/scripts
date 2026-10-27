use crate::config::router_dir;
use mikrotik_config_manager::typed_config::{
    read_typed, BridgeConfig, DhcpConfig, DnsConfig, FirewallConfig, InterfacesConfig, Ipv6Config,
    ListsConfig, NatConfig, NetworkConfig, ServicesConfig, SystemConfig, WirelessConfig,
};
use std::collections::HashSet;
use std::path::Path;
mod bridge;
mod consistency;
mod cross_errors;
mod dhcp;
mod dns;
mod finalization;
mod firewall;
mod interfaces;
mod ipv4_math;
mod ipv6;
mod leases;
mod lists;
mod nat;
mod network;
mod plan_prepare;
mod plan_render;
mod plan_validation;
pub mod reference_error;

// Тільки для регресійних тестів CLI: внутрішній модуль залишається приватним.
#[cfg(test)]
pub(crate) use plan_validation::{PlanValidationCode, PlanValidationError};
mod security;
mod services;
mod shared_errors;
mod static_audit;
mod system;
mod validation;
mod wan;
mod wireguard;
mod wireless;

// Порядок портів у TOML не має значення; дублікати й відсутні порти — помилка.
fn same_bridge_ports(bridge: &[String], lan: &[String]) -> bool {
    let a: HashSet<&str> = bridge.iter().map(String::as_str).collect();
    let b: HashSet<&str> = lan.iter().map(String::as_str).collect();
    a.len() == bridge.len() && b.len() == lan.len() && a == b
}

// Єдине розв’язання логічного ID, без рядкової мапи або fallback.
fn resolved_interface_name(
    config: &InterfacesConfig,
    id: &str,
) -> Result<String, shared_errors::SharedError> {
    let entry = config.interfaces.get(id).ok_or_else(|| {
        shared_errors::SharedError::new(
            shared_errors::SharedCode::UnknownInterface,
            format!("Невідомий логічний ID {id}"),
        )
    })?;
    if !entry.enabled {
        return Err(shared_errors::SharedError::new(
            shared_errors::SharedCode::DisabledInterface,
            format!("Інтерфейс {id} вимкнений"),
        ));
    }
    Ok(entry.name.clone())
}

// Перехід від типізованого посилання до нормалізованого ID без fallback.
fn normalized_wan_id<'a>(
    raw: &str,
    normalized: &'a str,
) -> Result<&'a str, shared_errors::SharedError> {
    let id = raw
        .strip_prefix("@interfaces.")
        .filter(|id| !id.is_empty())
        .ok_or_else(|| {
            shared_errors::SharedError::new(
                shared_errors::SharedCode::InvalidWanReference,
                "WAN: некоректне посилання на фізичний інтерфейс",
            )
        })?;
    if id != normalized {
        return Err(shared_errors::SharedError::new(
            shared_errors::SharedCode::WanIdMismatch,
            "WAN: логічний ID не збігається з нормалізованим",
        ));
    }
    Ok(normalized)
}

// Обробка єдиної декларативної моделі. Логічні ID існують лише всередині TOML,
// а генератор отримує вже розв'язані назви ресурсів RouterOS.
// Фізичні інтерфейси визначає лише TOML, а не назва моделі.
fn valid_physical_id(id: &str) -> bool {
    ["ether", "sfp", "wlan"].iter().any(|prefix| {
        id.strip_prefix(prefix).is_some_and(|number| {
            !number.is_empty()
                && !number.starts_with('0')
                && number.bytes().all(|byte| byte.is_ascii_digit())
                && number.parse::<u32>().is_ok_and(|index| index > 0)
        })
    })
}

pub fn plan(
    root: &Path,
    router: &str,
    selected: Option<&str>,
) -> Result<String, reference_error::PlanError> {
    let prepared = plan_prepare::prepare(root, router)?;
    let lines = plan_render::compose(router, selected, prepared.components())?;
    plan_validation::check(&lines, selected.is_none() || selected == Some("all"))?;
    Ok(lines.join("\n"))
}
pub(super) fn token(value: &str, label: &str) -> Result<(), shared_errors::TokenError> {
    if value.is_empty()
        || !value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || c == '.')
    {
        return Err(shared_errors::TokenError {
            code: shared_errors::TokenCode::InvalidCharactersOrEmpty,
            label: label.to_owned(),
        });
    }
    Ok(())
}

#[cfg(test)]
mod bridge_port_comparison_tests {
    use super::same_bridge_ports;
    #[test]
    fn comparison_ignores_order_but_rejects_missing_and_duplicate_ports() {
        let bridge = vec!["LAN-1-Ethernet".into(), "LAN-2-Ethernet".into()];
        let reordered = vec!["LAN-2-Ethernet".into(), "LAN-1-Ethernet".into()];
        let missing = vec!["LAN-1-Ethernet".into()];
        let duplicate = vec!["LAN-1-Ethernet".into(), "LAN-1-Ethernet".into()];
        assert!(same_bridge_ports(&bridge, &reordered));
        assert!(!same_bridge_ports(&bridge, &missing));
        assert!(!same_bridge_ports(&bridge, &duplicate));
    }
}

#[cfg(test)]
mod typed_wan_reference_regression_tests {
    use super::normalized_wan_id;

    #[test]
    fn wan_profiles_use_strict_typed_interface_refs() {
        use mikrotik_config_manager::typed_config::{read_typed, NetworkConfig};
        use std::path::Path;
        for profile in ["test", "hap-ac"] {
            let path = Path::new("routers").join(profile).join("network.toml");
            let cfg: NetworkConfig = read_typed(&path).unwrap();
            let id = cfg.wan.interface.strip_prefix("@interfaces.").unwrap();
            assert_eq!(normalized_wan_id(&cfg.wan.interface, id).unwrap(), id);
            assert!(!id.is_empty());
        }
    }

    #[test]
    fn normalizes_wan_declaration_and_rejects_wrong_reference() {
        assert_eq!(
            normalized_wan_id("@interfaces.ether1", "ether1").unwrap(),
            "ether1"
        );
        assert_eq!(
            normalized_wan_id("@interfaces.sfp1", "sfp1").unwrap(),
            "sfp1"
        );
        for value in [
            "ether1",
            "@bridge.lan",
            "@interfaces.",
            "@interfaces.ether2",
        ] {
            assert!(normalized_wan_id(value, "ether1").is_err(), "{value}");
        }
    }
}

#[cfg(test)]
mod typed_logical_id_regression_tests {
    use super::*;
    #[test]
    fn profile_interface_ids_resolve_without_string_maps() {
        for profile in ["test", "hap-ac"] {
            let path = Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("routers")
                .join(profile)
                .join("interfaces.toml");
            let config: InterfacesConfig = read_typed(&path).unwrap();
            for (id, resource) in &config.interfaces {
                if resource.enabled {
                    assert_eq!(resolved_interface_name(&config, id).unwrap(), resource.name);
                } else {
                    assert!(resolved_interface_name(&config, id).is_err());
                }
            }
            assert!(resolved_interface_name(&config, "missing-id").is_err());
        }
    }
    #[test]
    fn disabled_interface_must_not_resolve() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("routers/test/interfaces.toml");
        let mut config: InterfacesConfig = read_typed(&path).unwrap();
        let id = config.interfaces.keys().next().unwrap().clone();
        config.interfaces.get_mut(&id).unwrap().enabled = false;
        assert!(resolved_interface_name(&config, &id)
            .unwrap_err()
            .to_string()
            .contains("вимкнений"));
    }
}

// Регресійні контракти Stage 1: незалежність профілів, детермінованість PLAN
// і передача типізованої помилки через Result без аналізу тексту.
#[cfg(test)]
mod stage1_architecture_contract_tests {
    use super::*;

    #[test]
    fn every_declared_profile_has_identical_default_and_all_plan() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let routers = std::fs::read_dir(root.join("routers")).unwrap();
        let mut checked = 0;
        for entry in routers {
            let entry = entry.unwrap();
            if !entry.file_type().unwrap().is_dir() {
                continue;
            }
            let router = entry.file_name().into_string().unwrap();
            if !entry.path().join("interfaces.toml").exists() {
                continue;
            }
            let initial = plan(root, &router, None).unwrap();
            assert_eq!(initial, plan(root, &router, Some("all")).unwrap());
            assert_eq!(initial, plan(root, &router, None).unwrap());
            checked += 1;
        }
        assert!(checked > 0, "немає TOML-профілів для перевірки");
    }

    #[test]
    fn invalid_selection_is_a_typed_plan_error() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let router = std::fs::read_dir(root.join("routers"))
            .unwrap()
            .filter_map(Result::ok)
            .find(|entry| entry.path().join("interfaces.toml").exists())
            .unwrap()
            .file_name()
            .into_string()
            .unwrap();
        let error: reference_error::PlanError =
            plan(root, &router, Some("invalid-module-stage1")).unwrap_err();
        assert!(matches!(
            error,
            reference_error::PlanError::Configuration(_)
        ));
    }
}

// Stage 3: перевіряємо відносний порядок без Golden RSC і без фіксованих IP.
#[cfg(test)]
mod stage3_plan_determinism_tests {
    use super::*;

    // Команди вибраного модуля повинні утворювати впорядковану підпослідовність
    // повного PLAN. Зіставляємо рядки точно, без нормалізації чи парсингу тексту.
    fn ordered_subsequence(full: &[&str], selected: &[&str]) -> bool {
        let mut remaining = full.iter();
        selected
            .iter()
            .all(|line| remaining.by_ref().any(|candidate| candidate == line))
    }

    #[test]
    fn selective_plan_preserves_full_plan_command_order_for_every_profile() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let mut profiles = 0;
        let modules = [
            "interfaces",
            "bridge",
            "network",
            "lists",
            "dhcp",
            "leases",
            "dns",
            "wan",
            "nat",
            "firewall",
            "wireless",
            "system",
            "services",
            "security",
            "wireguard",
        ];
        for entry in std::fs::read_dir(root.join("routers")).unwrap() {
            let entry = entry.unwrap();
            if !entry.path().join("interfaces.toml").is_file() {
                continue;
            }
            let router = entry.file_name().into_string().unwrap();
            let full = plan(root, &router, None).unwrap();
            let full_lines: Vec<&str> = full.lines().skip(1).collect();
            for module in modules {
                let selected = plan(root, &router, Some(module)).unwrap();
                let selected_lines: Vec<&str> = selected.lines().skip(1).collect();
                assert!(
                    ordered_subsequence(&full_lines, &selected_lines),
                    "Порушений порядок PLAN: профіль {router}, модуль {module}"
                );
                assert_eq!(selected, plan(root, &router, Some(module)).unwrap());
            }
            profiles += 1;
        }
        assert!(profiles > 0, "Немає профілів для Stage 3");
    }

    #[test]
    fn unknown_selected_module_keeps_precise_typed_code() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        for entry in std::fs::read_dir(root.join("routers")).unwrap() {
            let entry = entry.unwrap();
            if !entry.path().join("interfaces.toml").is_file() {
                continue;
            }
            let router = entry.file_name().into_string().unwrap();
            let error = plan(root, &router, Some("not-a-supported-module")).unwrap_err();
            assert!(matches!(
                error,
                reference_error::PlanError::Configuration(reference_error::ConfigurationError {
                    code: reference_error::ConfigurationCode::UnknownModule,
                    ..
                })
            ));
        }
    }
}
