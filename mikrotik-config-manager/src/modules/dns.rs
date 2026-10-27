use super::network::Network;
use super::reference_error::{ModuleCode, ModuleError};
use mikrotik_config_manager::typed_config::DnsSettings;
use std::net::Ipv4Addr;

pub struct Dns {
    enabled: bool,
    servers: Vec<Ipv4Addr>,
    pub allow_remote_requests: bool,
}

impl Dns {
    // Типізована декларація DNS: без рядкових мап і проміжних адаптерів.
    pub fn parse(settings: &DnsSettings, _lan: &Network) -> Result<Self, ModuleError> {
        let mut servers = Vec::new();
        for item in &settings.servers {
            let ip: Ipv4Addr = item.trim().parse().map_err(|_| {
                ModuleError::new(ModuleCode::DnsInvalidAddress, "Некоректна адреса DNS")
            })?;
            servers.push(ip);
        }
        if servers.is_empty() {
            return Err(ModuleError::new(
                ModuleCode::DnsEmptyServers,
                "DNS: потрібно щонайменше один статичний сервер",
            ));
        }
        if servers.len()
            != servers
                .iter()
                .collect::<std::collections::HashSet<_>>()
                .len()
        {
            return Err(ModuleError::new(
                ModuleCode::DnsDuplicateServers,
                "DNS: дубльовані адреси серверів",
            ));
        }
        Ok(Self {
            enabled: settings.enabled,
            servers,
            allow_remote_requests: settings.allow_remote_requests,
        })
    }

    pub fn enabled(&self) -> bool {
        self.enabled
    }

    pub fn commands(&self) -> Vec<String> {
        if !self.enabled {
            return vec!["# DNS: вимкнено в конфігурації".into()];
        }
        vec![
            "# DNS: доступ клієнтів до cache контролює INPUT Firewall".into(),
            format!(
                "/ip dns set servers={} allow-remote-requests={}",
                self.servers
                    .iter()
                    .map(ToString::to_string)
                    .collect::<Vec<_>>()
                    .join(","),
                if self.allow_remote_requests {
                    "yes"
                } else {
                    "no"
                }
            ),
        ]
    }
}

#[cfg(test)]
mod typed_dns_tests {

    // Перевіряємо дані схеми до виклику генератора, незалежно від мережевого оточення.
    #[test]
    fn serde_rejects_invalid_dns_server_type() {
        let err = toml::from_str::<mikrotik_config_manager::typed_config::DnsConfig>(
            "[dns]\nenabled = true\nservers = \"1.1.1.1\"\nallow_remote_requests = true\n",
        )
        .unwrap_err();
        assert!(err.to_string().contains("sequence"));
    }

    // Перевірка списку без штучного обмеження у чотири адреси.
    #[test]
    fn serde_accepts_more_than_four_dns_servers() {
        let config: mikrotik_config_manager::typed_config::DnsConfig = toml::from_str(
            r#"[dns]
enabled = true
servers = ["1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4", "9.9.9.9"]
allow_remote_requests = true
"#,
        )
        .unwrap();
        assert_eq!(config.dns.servers.len(), 5);
    }

    #[test]
    fn serde_preserves_dns_order_and_flags() {
        let config: mikrotik_config_manager::typed_config::DnsConfig = toml::from_str(
            "[dns]\nenabled = true\nservers = [\"1.1.1.3\", \"1.0.0.3\"]\nallow_remote_requests = false\n",
        )
        .unwrap();
        assert_eq!(config.dns.servers, vec!["1.1.1.3", "1.0.0.3"]);
        assert!(!config.dns.allow_remote_requests);
    }
}
