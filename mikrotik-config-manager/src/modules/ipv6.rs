use super::reference_error::{ModuleCode, ModuleError};
use mikrotik_config_manager::typed_config::Ipv6Settings;

// IPv6 повністю керується окремим TOML-профілем.
pub struct Ipv6 {
    enabled: bool,
    firewall: bool,
    lan_list: String,
    wan_list: String,
}
impl Ipv6 {
    pub fn parse(
        config: &Ipv6Settings,
        lan_list: &str,
        wan_list: &str,
    ) -> Result<Self, ModuleError> {
        let enabled = config.enabled;
        let firewall = config.firewall;
        if enabled && !firewall {
            return Err(ModuleError::new(
                ModuleCode::Ipv6FirewallRequired,
                "IPv6: увімкнення без Firewall заборонено",
            ));
        }
        Ok(Self {
            enabled,
            firewall,
            lan_list: lan_list.into(),
            wan_list: wan_list.into(),
        })
    }
    pub fn commands(&self) -> Vec<String> {
        if !self.enabled {
            return vec![
                "# IPV6: вимкнено; IPv6 Firewall не генерується".into(),
                "/ipv6 settings set disable-ipv6=yes".into(),
            ];
        }
        let mut out = vec![
            "# IPV6: увімкнено із захисними правилами".into(),
            "/ipv6 settings set disable-ipv6=no".into(),
        ];
        if self.firewall {
            out.extend([
                "/ipv6 firewall filter add chain=input action=accept connection-state=established,related,untracked comment=mcm-ipv6-input-established".into(),
                "/ipv6 firewall filter add chain=input action=drop connection-state=invalid comment=mcm-ipv6-input-invalid".into(),
                "/ipv6 firewall filter add chain=input action=accept protocol=icmpv6 comment=mcm-ipv6-input-icmpv6".into(),
                format!("/ipv6 firewall filter add chain=input action=accept protocol=udp dst-port=546 src-address=fe80::/10 in-interface-list={} comment=mcm-ipv6-dhcpv6-client", self.wan_list),
                format!("/ipv6 firewall filter add chain=input action=accept in-interface-list={} comment=mcm-ipv6-input-lan", self.lan_list),
                "/ipv6 firewall filter add chain=input action=drop comment=mcm-ipv6-input-final-drop".into(),
                "/ipv6 firewall filter add chain=forward action=accept connection-state=established,related,untracked comment=mcm-ipv6-forward-established".into(),
                "/ipv6 firewall filter add chain=forward action=drop connection-state=invalid comment=mcm-ipv6-forward-invalid".into(),
                "/ipv6 firewall filter add chain=forward action=accept protocol=icmpv6 comment=mcm-ipv6-forward-icmpv6".into(),
                format!("/ipv6 firewall filter add chain=forward action=accept in-interface-list={} out-interface-list={} comment=mcm-ipv6-forward-lan-wan", self.lan_list, self.wan_list),
                "/ipv6 firewall filter add chain=forward action=drop comment=mcm-ipv6-forward-final-drop".into(),
            ]);
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mikrotik_config_manager::typed_config::Ipv6Config;

    #[test]
    fn regression_12_ipv6_error_retains_typed_code() {
        // Результат не вимагає аналізу українського тексту повідомлення.
        let config = Ipv6Settings {
            enabled: true,
            firewall: false,
        };
        let error = Ipv6::parse(&config, "LAN", "WAN").err().unwrap();
        assert_eq!(error.code, ModuleCode::Ipv6FirewallRequired);
        assert_eq!(error.code.location(), ("ipv6.toml", "ipv6.firewall"));
    }

    #[test]
    fn disabled_has_no_ipv6_firewall() {
        let config = Ipv6Settings {
            enabled: false,
            firewall: true,
        };
        let output = Ipv6::parse(&config, "LAN", "WAN").unwrap().commands();
        assert_eq!(
            output
                .iter()
                .filter(|s| s.starts_with("/ipv6 firewall"))
                .count(),
            0
        );
        assert!(output.contains(&"/ipv6 settings set disable-ipv6=yes".into()));
    }

    #[test]
    fn enabled_requires_filter_and_lan_wan_rules() {
        let mut config = Ipv6Settings {
            enabled: true,
            firewall: false,
        };
        assert!(Ipv6::parse(&config, "LAN", "WAN").is_err());
        config.firewall = true;
        let output = Ipv6::parse(&config, "LAN", "WAN").unwrap().commands();
        assert!(output.iter().any(|s| s.contains("protocol=icmpv6")));
        assert!(output
            .iter()
            .any(|s| s.contains("in-interface-list=LAN out-interface-list=WAN")));
        assert!(output
            .iter()
            .any(|s| s.contains("comment=mcm-ipv6-forward-final-drop")));
    }

    #[test]
    fn typed_ipv6_rejects_unknown_and_string_boolean() {
        assert!(
            toml::from_str::<Ipv6Config>("[ipv6]\nenabled = \"false\"\nfirewall = true").is_err()
        );
        assert!(toml::from_str::<Ipv6Config>(
            "[ipv6]\nenabled = false\nfirewall = true\nunknown = 1"
        )
        .is_err());
        assert!(toml::from_str::<Ipv6Config>("[ipv6]\nenabled = false").is_err());
    }

    #[test]
    fn typed_ipv6_profiles_generate_identical_disabled_commands() {
        for file in ["routers/test/ipv6.toml", "routers/hap-ac/ipv6.toml"] {
            let text = std::fs::read_to_string(file).unwrap();
            let config: Ipv6Config = toml::from_str(&text).unwrap();
            assert!(!config.ipv6.enabled);
            assert_eq!(
                Ipv6::parse(&config.ipv6, "LAN", "WAN").unwrap().commands(),
                vec![
                    "# IPV6: вимкнено; IPv6 Firewall не генерується".to_string(),
                    "/ipv6 settings set disable-ipv6=yes".to_string(),
                ]
            );
        }
    }
}
