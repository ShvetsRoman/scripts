use super::lists::Lists;
use super::network::{subnet, Network};
use super::reference_error::{ModuleCode, ModuleError};
use super::token;
use mikrotik_config_manager::typed_config::ServicesConfig;
use std::net::Ipv4Addr;

// Порти керування описані тут один раз і використовуються Firewall.
pub struct Services {
    pub ssh_port: u16,
    pub winbox_port: u16,
    pub winbox_enabled: bool,
    commands: Vec<String>,
}
impl Services {
    pub fn parse(
        config: &ServicesConfig,
        lists: &Lists,
        network: &Network,
    ) -> Result<Self, ModuleError> {
        let ssh = &config.services.ssh;
        let winbox = &config.services.winbox;
        let ssh_port = ssh.port;
        let winbox_port = winbox.port;
        if ssh_port == 0 || winbox_port == 0 {
            return Err(ModuleError::new(
                ModuleCode::ServicesPortsZero,
                "Порт SSH або WinBox не може бути нульовим",
            ));
        }
        if ssh.enabled && winbox.enabled && ssh_port == winbox_port {
            return Err(ModuleError::new(
                ModuleCode::ServicesPortsConflict,
                "Порти одночасно активних SSH і WinBox повинні відрізнятися",
            ));
        }
        let winbox_enabled = winbox.enabled;
        if config.discovery.interface_list != "@lists.lan" {
            return Err(ModuleError::new(
                ModuleCode::ServicesDiscoveryReference,
                "Neighbor Discovery дозволено лише для логічного LAN list",
            ));
        }
        token(&lists.lan, "discovery.list")
            .map_err(|error| ModuleError::from_token(ModuleCode::ServicesDiscoveryToken, error))?;
        // WARNING не блокує план. Усі параметри лишаються декларативними.
        let warnings = security_warnings(config);
        for warning in &warnings {
            eprintln!("[WARNING] {warning}");
        }
        // /ip service address= — додаткове обмеження джерела незалежно від Firewall.
        // Вимкнення limit_to_lan є свідомим рішенням у TOML, не прихованим fallback.
        let lan_network = format!(
            "{}/{}",
            Ipv4Addr::from(subnet(network.lan_ip, network.prefix)),
            network.prefix
        );
        let ssh_address = if ssh.limit_to_lan {
            lan_network.as_str()
        } else {
            "0.0.0.0/0"
        };
        let winbox_address = if winbox.limit_to_lan {
            lan_network.as_str()
        } else {
            "0.0.0.0/0"
        };
        let mut commands = vec![
            "# SERVICES: спершу перевірити доступ, лише план".into(),
            format!(
                "/ip service set [find name=ssh] disabled={} port={ssh_port} address={ssh_address}",
                if ssh.enabled { "no" } else { "yes" }
            ),
            format!(
                "/ip service set [find name=winbox] disabled={} port={winbox_port} address={winbox_address}",
                if winbox_enabled { "no" } else { "yes" }
            ),
        ];
        // Вимикаємо або вмикаємо кожну службу за її enabled із TOML.
        for (name, enabled) in [
            ("telnet", config.services.telnet.enabled),
            ("ftp", config.services.ftp.enabled),
            ("www", config.services.www.enabled),
            ("www-ssl", config.services.www_ssl.enabled),
            ("api", config.services.api.enabled),
            ("api-ssl", config.services.api_ssl.enabled),
            ("reverse-proxy", config.services.reverse_proxy.enabled),
        ] {
            commands.push(format!(
                "/ip service set [find name={name}] disabled={}",
                if enabled { "no" } else { "yes" }
            ));
        }
        commands.push(format!(
            "/ip neighbor discovery-settings set discover-interface-list={}",
            lists.lan
        ));
        Ok(Self {
            ssh_port,
            winbox_port,
            winbox_enabled,
            commands,
        })
    }
    pub fn commands(&self) -> Vec<String> {
        self.commands.clone()
    }
}

// Потенційні ризики повідомляємо, але не забороняємо налаштування.
fn security_warnings(config: &ServicesConfig) -> Vec<&'static str> {
    let services = &config.services;
    let mut warnings = Vec::new();
    if !services.ssh.limit_to_lan {
        warnings.push("SSH address не обмежено LAN — перевірте політику доступу");
    }
    if !services.winbox.limit_to_lan {
        warnings.push("WinBox address не обмежено LAN — перевірте політику доступу");
    }
    if !services.ssh.enabled {
        warnings.push("SSH вимкнено — перевірте альтернативний доступ до маршрутизатора");
    }
    if !services.winbox.enabled {
        warnings.push("WinBox вимкнено — переконайтеся, що керування доступне іншим способом");
    }
    if services.telnet.enabled {
        warnings.push("Telnet увімкнено — з’єднання не шифрується");
    }
    if services.ftp.enabled {
        warnings.push("FTP увімкнено — облікові дані можуть передаватися без шифрування");
    }
    if services.www.enabled {
        warnings.push("WWW (HTTP) увімкнено — рекомендовано HTTPS і обмеження доступу");
    }
    if services.api.enabled {
        warnings.push("API увімкнено — рекомендовано обмежити доступ із недовірених мереж");
    }
    if services.www_ssl.enabled {
        warnings.push("WWW-SSL увімкнено — перевірте сертифікат і обмеження доступу");
    }
    if services.api_ssl.enabled {
        warnings.push("API-SSL увімкнено — перевірте сертифікат і обмеження доступу");
    }
    if services.reverse_proxy.enabled {
        warnings.push("Reverse Proxy увімкнено — перевірте доступність із WAN");
    }
    warnings
}

#[cfg(test)]
mod policy_tests {
    use super::security_warnings;
    use mikrotik_config_manager::typed_config::ServicesConfig;

    fn config() -> ServicesConfig {
        toml::from_str(include_str!("../../routers/test/services.toml")).unwrap()
    }

    #[test]
    fn default_services_have_no_warnings() {
        assert!(security_warnings(&config()).is_empty());
    }

    #[test]
    fn insecure_services_produce_warnings_without_rejection() {
        let mut cfg = config();
        cfg.services.ssh.enabled = false;
        cfg.services.telnet.enabled = true;
        cfg.services.ftp.enabled = true;
        cfg.services.www.enabled = true;
        cfg.services.api.enabled = true;
        cfg.services.reverse_proxy.enabled = true;
        let messages = security_warnings(&cfg);
        assert!(messages.iter().any(|w| w.contains("SSH")));
        assert!(messages.iter().any(|w| w.contains("Telnet")));
        assert!(messages.iter().any(|w| w.contains("FTP")));
        assert!(messages.iter().any(|w| w.contains("WWW")));
        assert!(messages.iter().any(|w| w.contains("API")));
        assert!(messages.iter().any(|w| w.contains("Reverse Proxy")));
    }
}
