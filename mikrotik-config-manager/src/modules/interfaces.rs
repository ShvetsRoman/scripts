use super::reference_error::{ModuleCode, ModuleError};
use super::token;
use mikrotik_config_manager::typed_config::InterfaceResource;
use std::collections::{BTreeMap, HashSet};

// Керуємо фізичними Ethernet/SFP за незмінним default-name.
// [find default-name=...] повертає порожній набір для відсутнього порту:
// жоден інший ресурс випадково не буде змінено.
pub struct Interfaces {
    renames: Vec<(String, String)>,
    states: Vec<(String, bool)>,
}

impl Interfaces {
    pub fn parse(
        resources: &BTreeMap<String, InterfaceResource>,
        management: &str,
        wan: &str,
    ) -> Result<Self, ModuleError> {
        let mut renames = Vec::new();
        let mut states = Vec::new();
        let mut sources = HashSet::new();
        let mut targets = HashSet::new();
        for (source, resource) in resources {
            // Wi-Fi налаштовується окремим модулем; тут лише Ethernet/SFP.
            if source.starts_with("wlan") {
                continue;
            }
            physical(source)
                .map_err(|e| ModuleError::from_physical(ModuleCode::InterfacePhysical, e))?;
            token(&resource.name, "interface.name")
                .map_err(|e| ModuleError::from_token(ModuleCode::InterfaceName, e))?;
            if !sources.insert(source.clone()) || !targets.insert(resource.name.clone()) {
                return Err(ModuleError::new(
                    ModuleCode::InterfaceDuplicate,
                    "Повторювані назви фізичних інтерфейсів",
                ));
            }
            if !resource.enabled && (source == management || source == wan) {
                return Err(ModuleError::new(
                    ModuleCode::InterfaceCriticalDisabled,
                    format!("Не можна вимикати критичний порт {source} (WAN/Management)"),
                ));
            }
            states.push((source.clone(), resource.enabled));
            if source == management && source != &resource.name {
                return Err(ModuleError::new(
                    ModuleCode::InterfaceManagementRename,
                    "Не можна перейменувати активний фізичний Management",
                ));
            }
            if source != &resource.name {
                renames.push((source.clone(), resource.name.clone()));
            }
        }
        renames.sort();
        states.sort();
        // Забороняємо перейменування у заводське ім’я іншого порту:
        // це може зробити послідовність команд неоднозначною.
        for (_, target) in &renames {
            if sources.contains(target) {
                return Err(ModuleError::new(
                    ModuleCode::InterfaceRenameCollision,
                    "Колізія нової назви з фізичним портом",
                ));
            }
        }
        Ok(Self { renames, states })
    }

    pub fn resolved(&self, name: &str) -> String {
        self.renames
            .iter()
            .find(|(old, _)| old == name)
            .map(|(_, new)| new.clone())
            .unwrap_or_else(|| name.to_string())
    }

    pub fn commands(&self) -> Vec<String> {
        let mut out = vec![
            "# INTERFACES: безпечний пошук за default-name; повторний set не створює дублікатів"
                .into(),
        ];
        for (old, new) in &self.renames {
            out.push(format!(
                "/interface ethernet set [find default-name={old}] name={new}"
            ));
        }
        // Стан задаємо симетрично: yes вимикає, no вмикає інтерфейс.
        // Це також стосується SFP, який у RouterOS 7 є Ethernet-ресурсом.
        for (port, enabled) in &self.states {
            out.push(format!(
                "/interface ethernet set [find default-name={port}] disabled={}",
                if *enabled { "no" } else { "yes" }
            ));
        }
        out
    }
}

// Окремий тип для неправильного заводського ідентифікатора.
// Повідомлення залишається ідентичним попередньому контракту CLI.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct PhysicalInterfaceError {
    value: String,
}

impl std::fmt::Display for PhysicalInterfaceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Неприпустимий default-name: {}", self.value)
    }
}

impl std::error::Error for PhysicalInterfaceError {}

fn physical(value: &str) -> Result<(), PhysicalInterfaceError> {
    let valid_ether = value.strip_prefix("ether").is_some_and(|number| {
        !number.is_empty() && !number.starts_with('0') && number.chars().all(|c| c.is_ascii_digit())
    });
    let valid_sfp = value.strip_prefix("sfp").is_some_and(|number| {
        !number.is_empty() && !number.starts_with('0') && number.chars().all(|c| c.is_ascii_digit())
    });
    if !valid_ether && !valid_sfp {
        return Err(PhysicalInterfaceError {
            value: value.to_owned(),
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn resource(name: &str, enabled: bool) -> InterfaceResource {
        InterfaceResource {
            name: name.into(),
            enabled,
            comment: String::new(),
        }
    }

    #[test]
    fn invalid_physical_interface_preserves_typed_source() {
        use std::error::Error;
        let resources = BTreeMap::from([("ether00".into(), resource("Port", true))]);
        let error = match Interfaces::parse(&resources, "ether1", "ether2") {
            Err(error) => error,
            Ok(_) => panic!("invalid physical identifier was accepted"),
        };
        assert_eq!(error.code, ModuleCode::InterfacePhysical);
        assert_eq!(error.to_string(), "Неприпустимий default-name: ether00");
        let source = error.source().expect("physical interface cause");
        assert!(source.downcast_ref::<PhysicalInterfaceError>().is_some());
    }

    #[test]
    fn changes_both_states_and_supports_sfp() {
        let resources = BTreeMap::from([
            ("ether5".into(), resource("ESF", false)),
            ("sfp1".into(), resource("SFP", true)),
        ]);
        let commands = Interfaces::parse(&resources, "ether1", "ether2")
            .unwrap()
            .commands();
        assert!(commands
            .iter()
            .any(|c| c.contains("default-name=ether5") && c.contains("name=ESF")));
        assert!(commands
            .iter()
            .any(|c| c.contains("default-name=ether5") && c.contains("disabled=yes")));
        assert!(commands
            .iter()
            .any(|c| c.contains("default-name=sfp1") && c.contains("disabled=no")));
    }

    #[test]
    fn protects_wan_and_management() {
        for port in ["ether1", "ether2"] {
            let resources = BTreeMap::from([(port.into(), resource(port, false))]);
            assert!(Interfaces::parse(&resources, "ether1", "ether2").is_err());
        }
    }

    #[test]
    fn repeated_plan_is_identical_and_does_not_add_resources() {
        let resources = BTreeMap::from([("ether5".into(), resource("ESF", false))]);
        let interfaces = Interfaces::parse(&resources, "ether1", "ether2").unwrap();
        assert_eq!(interfaces.commands(), interfaces.commands());
        assert!(interfaces
            .commands()
            .iter()
            .all(|line| !line.contains(" add ")));
    }

    #[test]
    fn declared_high_numbered_ports_only_are_emitted() {
        let resources = BTreeMap::from([
            ("ether12".into(), resource("LAN12", true)),
            ("sfp3".into(), resource("SPARE_SFP", false)),
        ]);
        let cmds = Interfaces::parse(&resources, "ether1", "ether2")
            .unwrap()
            .commands();
        assert!(cmds
            .iter()
            .any(|c| c.contains("default-name=ether12") && c.contains("name=LAN12")));
        assert!(cmds
            .iter()
            .any(|c| c.contains("default-name=sfp3") && c.contains("disabled=yes")));
        assert!(!cmds
            .iter()
            .any(|c| c.contains("default-name=sfp1") || c.contains("default-name=ether3")));
    }

    #[test]
    fn wifi_is_not_managed_as_ethernet() {
        let resources = BTreeMap::from([("wlan1".into(), resource("WiFi", true))]);
        let commands = Interfaces::parse(&resources, "ether1", "ether2")
            .unwrap()
            .commands();
        assert_eq!(commands.len(), 1);
    }
}

#[cfg(test)]
mod typed_physical_error_regression_tests {
    use super::*;

    #[test]
    fn malformed_factory_identifier_has_typed_error_and_original_text() {
        let err = physical("ether0").expect_err("ether0 має залишатися забороненим");
        assert_eq!(err.value, "ether0");
        assert_eq!(err.to_string(), "Неприпустимий default-name: ether0");
        assert!(physical("sfp1").is_ok());
        assert!(physical("ether12").is_ok());
    }
}
