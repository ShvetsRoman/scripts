use super::reference_error::{ModuleCode, ModuleError};
use super::token;
use mikrotik_config_manager::typed_config::{InterfacesConfig, WirelessConfig};
use std::collections::HashSet;

// Wi-Fi не застосовується автоматично. Профілі логічно посилаються на
// security ID і bridge ID; фактичні назви шукаються в таблицях ресурсів.
pub struct Wireless {
    commands: Vec<String>,
}

// Відповідність логічного ID у TOML до заводського default-name RouterOS.
// Значення name в interfaces.toml — це цільове ім'я, а не default-name.
// Номер радіо визначає TOML; жорсткого списку wlan1/wlan2 немає.
fn factory_radio_names(id: &str) -> Result<(String, String), ModuleError> {
    let index = id.strip_prefix("wlan").filter(|number| {
        !number.is_empty()
            && !number.starts_with('0')
            && number.bytes().all(|byte| byte.is_ascii_digit())
            && number.parse::<u32>().is_ok_and(|index| index > 0)
    });
    match index {
        Some(index) => Ok((format!("wlan{index}"), format!("wifi{index}"))),
        None => Err(ModuleError::new(
            ModuleCode::WifiFactoryId,
            format!("Невідомий фізичний Wi-Fi ID {id}: потрібен явний опис відповідності"),
        )),
    }
}

// Чіткий заводський ідентифікатор: wlanN або wifiN, без shell/RouterOS вставок.
// Для конкретного роутера N визначається декларацією та фактичним обладнанням.
fn valid_factory_name(name: &str, driver: &str) -> bool {
    let prefix = if driver == "legacy" { "wlan" } else { "wifi" };
    name.strip_prefix(prefix).is_some_and(|number| {
        !number.is_empty()
            && !number.starts_with('0')
            && number.chars().all(|c| c.is_ascii_digit())
            && number.parse::<u16>().is_ok_and(|n| n > 0)
    })
}

impl Wireless {
    pub fn parse(
        config: &WirelessConfig,
        interfaces: &InterfacesConfig,
        bridge: &str,
    ) -> Result<Self, ModuleError> {
        let enabled = config.wireless.enabled;
        let driver = config.wireless.driver.as_str();
        if !enabled {
            if driver != "none" {
                return Err(ModuleError::new(
                    ModuleCode::WifiDisabledDriver,
                    "Вимкнений Wi-Fi повинен мати driver=none",
                ));
            }
            if !config.wireless.radios.is_empty() {
                return Err(ModuleError::new(
                    ModuleCode::WifiDisabledRadios,
                    "Для вимкненого Wi-Fi не можна описувати радіо",
                ));
            }
            return Ok(Self {
                commands: vec!["# WIRELESS: відсутній (CHR VirtualBox)".into()],
            });
        }
        if driver != "legacy" && driver != "wifi-qcom-ac" {
            return Err(ModuleError::new(
                ModuleCode::WifiDriver,
                "Непідтримуваний Wi-Fi драйвер",
            ));
        }
        let mut commands = vec![
            format!("# WIRELESS: драйвер {driver}; перевірити встановлений RouterOS пакет"),
            "# SECURITY: пароль навмисно НЕ записано в план; Wi-Fi потребує ручного секрету".into(),
        ];
        let radios: Vec<_> = config.wireless.radios.keys().cloned().collect();
        if radios.is_empty() {
            return Err(ModuleError::new(
                ModuleCode::WifiNoRadios,
                "Не знайдено Wi-Fi радіо",
            ));
        }
        let mut security_names = HashSet::new();
        let mut emitted_security = HashSet::new();
        let mut factory_sources = HashSet::new();
        for id in radios {
            // Логічний ID не залежить від назви профілю. Для старих TOML
            // зберігаємо усталений default-name поточного драйвера.
            let (legacy_factory, wifi_factory) = factory_radio_names(&id)?;
            let radio = &config.wireless.radios[&id];
            let factory = if let Some(explicit) = &radio.default_name {
                // Забороняємо підстановки, пробіли та інші небезпечні символи CLI.
                if !valid_factory_name(explicit, driver) {
                    return Err(ModuleError::new(
                        ModuleCode::WifiFactoryName,
                        format!("Некоректний Wi-Fi default_name: {id}"),
                    ));
                }
                explicit.as_str()
            } else if driver == "legacy" {
                legacy_factory.as_str()
            } else {
                wifi_factory.as_str()
            };
            // Колізія фізичних портів не допускається навіть у вимкненій декларації.
            if !factory_sources.insert(factory.to_string()) {
                return Err(ModuleError::new(
                    ModuleCode::WifiFactoryDuplicate,
                    format!("Повтор Wi-Fi default_name: {factory}"),
                ));
            }
            if !radio.enabled {
                continue;
            }
            if radio.interface != format!("@interfaces.{id}") {
                return Err(ModuleError::new(
                    ModuleCode::WifiInterface,
                    "Некоректне Wi-Fi interface ID",
                ));
            }
            if radio.bridge != "@bridge.lan" {
                return Err(ModuleError::new(
                    ModuleCode::WifiBridge,
                    "Невідомий Wi-Fi Bridge ID",
                ));
            }
            let props = interfaces.interfaces.get(id.as_str()).ok_or_else(|| {
                ModuleError::new(ModuleCode::WifiInterface, "Невідомий Wi-Fi interface ID")
            })?;
            if !props.enabled {
                return Err(ModuleError::new(
                    ModuleCode::WifiRadioDisabled,
                    "Wi-Fi радіо вимкнене в interfaces.toml",
                ));
            }
            let name = props.name.as_str();
            token(name, "wireless.interface.name")
                .map_err(|e| ModuleError::from_token(ModuleCode::WifiToken, e))?;
            let ssid = radio.ssid.as_str();
            // Не приймаємо спецсимволи RouterOS CLI без повного механізму екранування.
            token(ssid, "wireless.ssid")
                .map_err(|e| ModuleError::from_token(ModuleCode::WifiToken, e))?;
            let sec_ref = radio.security.as_str();
            let sec_id = sec_ref.strip_prefix("@security.").ok_or_else(|| {
                ModuleError::new(ModuleCode::WifiSecurity, "Некоректне Wi-Fi Security ID")
            })?;
            token(sec_id, "wireless.security")
                .map_err(|e| ModuleError::from_token(ModuleCode::WifiToken, e))?;
            let sec = config.security.get(sec_id).ok_or_else(|| {
                ModuleError::new(ModuleCode::WifiSecurity, "Невідомий Wi-Fi Security ID")
            })?;
            let sec_name = sec.name.as_str();
            token(sec_name, "wireless.security.name")
                .map_err(|e| ModuleError::from_token(ModuleCode::WifiToken, e))?;
            if sec.password_source != "manual" {
                return Err(ModuleError::new(
                    ModuleCode::WifiPasswordSource,
                    "Пароль Wi-Fi дозволено налаштовувати лише окремо",
                ));
            }
            if sec.authentication != "wpa2-psk" {
                return Err(ModuleError::new(
                    ModuleCode::WifiAuthentication,
                    "Для цього профілю підтримується лише WPA2-PSK",
                ));
            }
            if emitted_security.insert(sec_id.to_string()) {
                if !security_names.insert(sec_name.to_string()) {
                    return Err(ModuleError::new(
                        ModuleCode::WifiSecurityDuplicate,
                        "Повтор назви Wi-Fi Security Profile",
                    ));
                }
                if driver == "legacy" {
                    commands.push(format!("/interface wireless security-profiles add name={sec_name} mode=dynamic-keys authentication-types=wpa2-psk comment=mcm-wifi-security"));
                } else {
                    commands.push(format!("/interface wifi security add name={sec_name} authentication-types=wpa2-psk comment=mcm-wifi-security"));
                }
            }
            let band = radio.band.as_str();
            let width = radio.channel_width.as_str();
            let frequency = radio.frequency.as_str();
            let country = radio.country.as_str();
            for (label, v) in [
                ("band", band),
                ("channel_width", width),
                ("frequency", frequency),
                ("country", country),
            ] {
                if !v
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.' | '/'))
                    || v.is_empty()
                {
                    return Err(ModuleError::new(
                        ModuleCode::WifiChannel,
                        format!("Некоректне значення {label}"),
                    ));
                }
            }
            if driver == "legacy" {
                commands.push(format!("/interface wireless set [find default-name={factory}] name={name} mode=ap-bridge ssid={ssid} band={band} channel-width={width} frequency={frequency} country={country} security-profile={sec_name} disabled=no"));
            } else {
                // /interface wifi має інші назви channel/band; не копіюємо legacy параметри.
                commands.push(format!("/interface wifi set [find default-name={factory}] name={name} configuration.mode=ap configuration.ssid={ssid} configuration.country={country} security={sec_name} disabled=no"));
                commands.push(format!("# WIFI: перевірити channel.width, band={band}, width={width}, frequency={frequency} за встановленим драйвером"));
            }
            commands.push(format!("/interface bridge port add bridge={bridge} interface={name} comment=mcm-wifi-bridge"));
        }
        Ok(Self { commands })
    }
    pub fn commands(&self) -> Vec<String> {
        self.commands.clone()
    }
}

#[cfg(test)]
mod profile_independence_tests {
    use super::Wireless;
    use mikrotik_config_manager::typed_config::{read_typed, InterfacesConfig, WirelessConfig};
    use std::path::Path;

    #[test]
    fn configured_wifi_is_not_limited_by_profile_name() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let w: WirelessConfig = read_typed(&root.join("routers/hap-ac/wireless.toml")).unwrap();
        let i: InterfacesConfig = read_typed(&root.join("routers/hap-ac/interfaces.toml")).unwrap();
        // Декларація не отримує назву профілю: однакова конфігурація має однаковий план.
        let commands = Wireless::parse(&w, &i, "bridge-lan").unwrap().commands();
        assert!(commands
            .iter()
            .any(|cmd| cmd.starts_with("/interface wireless set ")));
        assert!(commands.iter().all(|cmd| !cmd.contains("WIFI_PASSWORD")));
    }

    #[test]
    fn both_driver_commands_remain_distinct() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let mut w: WirelessConfig = read_typed(&root.join("routers/hap-ac/wireless.toml")).unwrap();
        let i: InterfacesConfig = read_typed(&root.join("routers/hap-ac/interfaces.toml")).unwrap();
        let legacy = Wireless::parse(&w, &i, "bridge-lan").unwrap().commands();
        w.wireless.driver = "wifi-qcom-ac".to_owned();
        let modern = Wireless::parse(&w, &i, "bridge-lan").unwrap().commands();
        assert!(legacy
            .iter()
            .any(|cmd| cmd.starts_with("/interface wireless set ")));
        assert!(modern
            .iter()
            .any(|cmd| cmd.starts_with("/interface wifi set ")));
        assert!(modern.iter().any(|cmd| cmd.contains("default-name=wifi1")));
        assert!(modern.iter().any(|cmd| cmd.contains("default-name=wifi2")));
        assert!(legacy
            .iter()
            .all(|cmd| !cmd.contains("/interface wifi set ")));
    }

    #[test]
    fn wifi_disabled_without_radios_keeps_previous_comment() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let w: WirelessConfig = read_typed(&root.join("routers/test/wireless.toml")).unwrap();
        let i: InterfacesConfig = read_typed(&root.join("routers/test/interfaces.toml")).unwrap();
        assert_eq!(
            Wireless::parse(&w, &i, "bridge-lan").unwrap().commands(),
            vec!["# WIRELESS: відсутній (CHR VirtualBox)".to_owned()]
        );
    }
}

#[cfg(test)]
mod physical_mapping_tests {
    use super::{factory_radio_names, Wireless};
    use mikrotik_config_manager::typed_config::{read_typed, InterfacesConfig, WirelessConfig};
    use std::path::Path;

    #[test]
    fn maps_logical_ids_to_correct_driver_factory_names() {
        assert_eq!(
            factory_radio_names("wlan1").unwrap(),
            ("wlan1".to_string(), "wifi1".to_string())
        );
        assert_eq!(
            factory_radio_names("wlan2").unwrap(),
            ("wlan2".to_string(), "wifi2".to_string())
        );
        assert_eq!(
            factory_radio_names("wlan3").unwrap(),
            ("wlan3".to_string(), "wifi3".to_string())
        );
        assert_eq!(
            factory_radio_names("wlan12").unwrap(),
            ("wlan12".to_string(), "wifi12".to_string())
        );
        for bad in [
            "wifi1",
            "ether1",
            "wlan0",
            "wlan01",
            "../wlan1",
            "wlan1;reboot",
        ] {
            assert!(
                factory_radio_names(bad).is_err(),
                "unexpected accepted ID: {bad}"
            );
        }
    }

    #[test]
    fn renamed_interfaces_keep_factory_selection_for_both_drivers() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let mut wireless: WirelessConfig =
            read_typed(&root.join("routers/hap-ac/wireless.toml")).unwrap();
        let mut interfaces: InterfacesConfig =
            read_typed(&root.join("routers/hap-ac/interfaces.toml")).unwrap();
        interfaces.interfaces.get_mut("wlan1").unwrap().name = "guest24".into();
        interfaces.interfaces.get_mut("wlan2").unwrap().name = "guest5".into();
        let legacy = Wireless::parse(&wireless, &interfaces, "bridge-lan")
            .unwrap()
            .commands();
        assert!(legacy
            .iter()
            .any(|c| c.contains("default-name=wlan1") && c.contains("name=guest24")));
        assert!(legacy
            .iter()
            .any(|c| c.contains("default-name=wlan2") && c.contains("name=guest5")));
        wireless.wireless.driver = "wifi-qcom-ac".into();
        let modern = Wireless::parse(&wireless, &interfaces, "bridge-lan")
            .unwrap()
            .commands();
        assert!(modern
            .iter()
            .any(|c| c.contains("default-name=wifi1") && c.contains("name=guest24")));
        assert!(modern
            .iter()
            .any(|c| c.contains("default-name=wifi2") && c.contains("name=guest5")));
    }

    #[test]
    fn unknown_radio_and_broken_logical_reference_fail_closed() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let mut wireless: WirelessConfig =
            read_typed(&root.join("routers/hap-ac/wireless.toml")).unwrap();
        let interfaces: InterfacesConfig =
            read_typed(&root.join("routers/hap-ac/interfaces.toml")).unwrap();
        let mut unexpected = wireless.wireless.radios.remove("wlan2").unwrap();
        unexpected.enabled = false;
        wireless.wireless.radios.insert("wlan3".into(), unexpected);
        // Вимкнене радіо не створює команд і не вимагає фізичного інтерфейсу.
        let disabled_commands = Wireless::parse(&wireless, &interfaces, "bridge-lan")
            .unwrap()
            .commands();
        assert!(disabled_commands
            .iter()
            .all(|cmd| !cmd.contains("default-name=wlan3")));
        // Активне радіо має посилатися на явно описаний interfaces.wlan3.
        wireless.wireless.radios.get_mut("wlan3").unwrap().enabled = true;
        assert!(Wireless::parse(&wireless, &interfaces, "bridge-lan").is_err());
        wireless.wireless.radios.remove("wlan3");
        wireless.wireless.radios.get_mut("wlan1").unwrap().interface = "@interfaces.wlan2".into();
        assert!(Wireless::parse(&wireless, &interfaces, "bridge-lan").is_err());
    }
}

#[cfg(test)]
mod declared_factory_tests {
    use super::Wireless;
    use mikrotik_config_manager::typed_config::{read_typed, InterfacesConfig, WirelessConfig};
    use std::path::Path;

    fn configs() -> (WirelessConfig, InterfacesConfig) {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        (
            read_typed(&root.join("routers/hap-ac/wireless.toml")).unwrap(),
            read_typed(&root.join("routers/hap-ac/interfaces.toml")).unwrap(),
        )
    }

    #[test]
    fn explicit_physical_names_override_standard_mapping_without_changing_logical_ids() {
        let (mut wifi, interfaces) = configs();
        wifi.wireless.radios.get_mut("wlan1").unwrap().default_name = Some("wlan3".into());
        let commands = Wireless::parse(&wifi, &interfaces, "bridge-lan")
            .unwrap()
            .commands();
        assert!(commands
            .iter()
            .any(|cmd| cmd.contains("default-name=wlan3")));
        assert!(commands
            .iter()
            .any(|cmd| cmd.contains("default-name=wlan2")));
        wifi.wireless.driver = "wifi-qcom-ac".into();
        wifi.wireless.radios.get_mut("wlan1").unwrap().default_name = Some("wifi3".into());
        let modern = Wireless::parse(&wifi, &interfaces, "bridge-lan")
            .unwrap()
            .commands();
        assert!(modern.iter().any(|cmd| cmd.contains("default-name=wifi3")));
        assert!(modern.iter().any(|cmd| cmd.contains("default-name=wifi2")));
    }

    #[test]
    fn invalid_and_duplicate_factory_names_are_rejected() {
        let (mut wifi, interfaces) = configs();
        for bad in [
            "wifi3",
            "wlan0",
            "wlan01",
            "wlan1] reset",
            "wlan-1",
            "wlan65536",
        ] {
            wifi.wireless.radios.get_mut("wlan1").unwrap().default_name = Some(bad.into());
            assert!(
                Wireless::parse(&wifi, &interfaces, "bridge-lan").is_err(),
                "accepted: {bad}"
            );
        }
        wifi.wireless.radios.get_mut("wlan1").unwrap().default_name = Some("wlan2".into());
        assert!(Wireless::parse(&wifi, &interfaces, "bridge-lan").is_err());
    }

    #[test]
    fn explicit_mapping_is_a_strict_optional_serde_string() {
        let (wifi, _) = configs();
        assert_eq!(wifi.wireless.radios["wlan1"].default_name, None);
        let contents = std::fs::read_to_string(
            Path::new(env!("CARGO_MANIFEST_DIR")).join("routers/hap-ac/wireless.toml"),
        )
        .unwrap();
        let with_string = contents.replace(
            "\n[wireless.wlan1]\n",
            "\n[wireless.wlan1]\ndefault_name = \"wlan3\"",
        );
        let parsed: WirelessConfig = toml::from_str(&with_string).unwrap();
        assert_eq!(
            parsed.wireless.radios["wlan1"].default_name.as_deref(),
            Some("wlan3")
        );
        let with_number = contents.replace(
            "\n[wireless.wlan1]\n",
            "\n[wireless.wlan1]\ndefault_name = 3",
        );
        assert!(toml::from_str::<WirelessConfig>(&with_number).is_err());
        let with_unknown = contents.replace(
            "\n[wireless.wlan1]\n",
            "\n[wireless.wlan1]\nfactory_name = \"wlan3\"",
        );
        assert!(toml::from_str::<WirelessConfig>(&with_unknown).is_err());
    }
}

// Регресійні перевірки генерації Wireless.
#[cfg(test)]
mod final_audit_tests {
    use super::Wireless;
    use mikrotik_config_manager::typed_config::{read_typed, InterfacesConfig, WirelessConfig};
    use std::path::Path;

    fn base() -> (WirelessConfig, InterfacesConfig) {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("routers/hap-ac");
        (
            read_typed(&root.join("wireless.toml")).unwrap(),
            read_typed(&root.join("interfaces.toml")).unwrap(),
        )
    }

    #[test]
    fn original_profiles_keep_implicit_factory_names_without_secrets() {
        let (wifi, interfaces) = base();
        let commands = Wireless::parse(&wifi, &interfaces, "bridge-lan")
            .unwrap()
            .commands();
        assert!(commands.iter().any(|c| c.contains("default-name=wlan1")));
        assert!(commands.iter().any(|c| c.contains("default-name=wlan2")));
        assert!(commands
            .iter()
            .all(|c| !c.contains("WIFI_PASSWORD") && !c.contains("wpa2-pre-shared-key")));
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("routers/test");
        let no_wifi: WirelessConfig = read_typed(&root.join("wireless.toml")).unwrap();
        let no_interfaces: InterfacesConfig = read_typed(&root.join("interfaces.toml")).unwrap();
        let plan = Wireless::parse(&no_wifi, &no_interfaces, "bridge-lan")
            .unwrap()
            .commands();
        assert_eq!(plan.len(), 1);
        assert!(plan[0].starts_with("# WIRELESS:"));
    }

    #[test]
    fn physical_names_reject_injection_and_driver_mismatch() {
        let (mut wifi, interfaces) = base();
        for bad in ["wifi1", "wlan0", "wlan1;reset", "wlan1]", "wlan65536"] {
            wifi.wireless.radios.get_mut("wlan1").unwrap().default_name = Some(bad.into());
            assert!(
                Wireless::parse(&wifi, &interfaces, "bridge-lan").is_err(),
                "accepted {bad}"
            );
        }
        wifi.wireless.driver = "wifi-qcom-ac".into();
        wifi.wireless.radios.get_mut("wlan1").unwrap().default_name = Some("wifi3".into());
        let commands = Wireless::parse(&wifi, &interfaces, "bridge-lan")
            .unwrap()
            .commands();
        assert!(commands.iter().any(|c| c.contains("default-name=wifi3")));
    }

    #[test]
    fn disabling_one_radio_does_not_emit_its_configuration() {
        let (mut wifi, interfaces) = base();
        wifi.wireless.radios.get_mut("wlan2").unwrap().enabled = false;
        let commands = Wireless::parse(&wifi, &interfaces, "bridge-lan")
            .unwrap()
            .commands();
        assert!(commands.iter().any(|c| c.contains("default-name=wlan1")));
        assert!(commands.iter().all(|c| !c.contains("default-name=wlan2")));
    }
}
