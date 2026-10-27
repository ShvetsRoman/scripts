use super::dhcp::Dhcp;
use super::network::Network;
use super::reference_error::{ModuleCode, ModuleError};
use super::token;
use mikrotik_config_manager::typed_config::LeaseSection;
use std::collections::HashSet;
use std::net::Ipv4Addr;

struct Lease {
    address: Ipv4Addr,
    mac: String,
    comment: String,
}

// Простий TOML-сумісний перелік lease_01_* без сторонніх залежностей.
pub struct Leases {
    enabled: bool,
    server: String,
    entries: Vec<Lease>,
}
impl Leases {
    pub fn parse(config: &LeaseSection, lan: &Network, dhcp: &Dhcp) -> Result<Self, ModuleError> {
        let enabled = config.enabled;
        let count = config.devices.len();
        if count > 128 {
            return Err(ModuleError::new(
                ModuleCode::LeasesLimit,
                "Забагато DHCP reservations",
            ));
        }
        if count > 0 && (!enabled || !dhcp.enabled) {
            return Err(ModuleError::new(
                ModuleCode::LeasesDhcpDisabled,
                "Reservations потребують увімкнений DHCP",
            ));
        }
        let mut addresses = HashSet::new();
        let mut macs = HashSet::new();
        let mut entries = Vec::new();
        for (id, resource) in &config.devices {
            if !id.starts_with("lease_")
                || id.len() != 8
                || !id[6..].bytes().all(|b| b.is_ascii_digit())
            {
                return Err(ModuleError::new(
                    ModuleCode::LeasesId,
                    format!("Некоректний lease ID {id}"),
                ));
            }
            let prefix = id.as_str();
            let address: Ipv4Addr = resource.address.parse().map_err(|_| {
                ModuleError::new(
                    ModuleCode::LeasesAddress,
                    format!("Некоректна IP адреса для {prefix}"),
                )
            })?;
            let mac = resource.mac.to_ascii_uppercase();
            let comment = resource.comment.clone();
            token(&comment, "lease comment")
                .map_err(|error| ModuleError::from_token(ModuleCode::LeasesComment, error))?;
            if !valid_mac(&mac) {
                return Err(ModuleError::new(
                    ModuleCode::LeasesMac,
                    format!("Некоректна MAC адреса {prefix}"),
                ));
            }
            if !lan.contains(address)
                || address == lan.lan_ip
                || !lan_host(address, lan)
                || (address >= dhcp.first && address <= dhcp.last)
            {
                return Err(ModuleError::new(
                    ModuleCode::LeasesLanRange,
                    format!("Lease {prefix} поза LAN, зайнята роутером чи в динамічному пулі"),
                ));
            }
            if !addresses.insert(address) || !macs.insert(mac.clone()) {
                return Err(ModuleError::new(
                    ModuleCode::LeasesDuplicate,
                    format!("Дубль IP/MAC у {prefix}"),
                ));
            }
            entries.push(Lease {
                address,
                mac,
                comment,
            });
        }
        Ok(Self {
            enabled,
            server: dhcp.server_name.clone(),
            entries,
        })
    }
    pub fn commands(&self) -> Vec<String> {
        if !self.enabled {
            return vec!["# Статичні DHCP leases: вимкнено".into()];
        }
        let mut lines = vec!["# STATIC LEASES: перевірити існуючі прив'язки перед імпортом".into()];
        lines.extend(self.entries.iter().map(|lease| {
            format!(
                "/ip dhcp-server lease add address={} mac-address={} server={} comment={}",
                lease.address, lease.mac, self.server, lease.comment
            )
        }));
        lines
    }
}
fn valid_mac(mac: &str) -> bool {
    let parts: Vec<_> = mac.split(':').collect();
    parts.len() == 6
        && parts
            .iter()
            .all(|p| p.len() == 2 && p.bytes().all(|b| b.is_ascii_hexdigit()))
        && mac != "00:00:00:00:00:00"
        && mac != "FF:FF:FF:FF:FF:FF"
}
fn lan_host(address: Ipv4Addr, lan: &Network) -> bool {
    super::ipv4_math::valid_host(address, lan.prefix)
        && super::ipv4_math::subnet(address, lan.prefix)
            == super::ipv4_math::subnet(lan.lan_ip, lan.prefix)
}
