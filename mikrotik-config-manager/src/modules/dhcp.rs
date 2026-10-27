use super::network::{subnet, Network};
use super::reference_error::{ModuleCode, ModuleError};
use super::token;
use mikrotik_config_manager::typed_config::DhcpConfig;
use std::net::Ipv4Addr;

// Опис пулу та DHCP-сервера не містить налаштувань конкретного роутера.
pub struct Dhcp {
    pub enabled: bool,
    pub server_name: String,
    pub first: Ipv4Addr,
    pub last: Ipv4Addr,
    pool_name: String,
    gateway: Ipv4Addr,
    pub dns_servers: Vec<Ipv4Addr>,
    lease_time: String,
    interface: String,
    network: String,
}

impl Dhcp {
    pub fn parse(cfg: &DhcpConfig, lan: &Network) -> Result<Self, ModuleError> {
        let enabled = cfg.server.lan.enabled;
        let pool_name = cfg.pool.lan.name.clone();
        let server_name = cfg.server.lan.name.clone();
        token(&pool_name, "pool_name")
            .map_err(|detail| ModuleError::from_token(ModuleCode::DhcpInvalidName, detail))?;
        token(&server_name, "server_name")
            .map_err(|detail| ModuleError::from_token(ModuleCode::DhcpInvalidName, detail))?;
        let first: Ipv4Addr = cfg.pool.lan.start.as_str().parse().map_err(|_| {
            ModuleError::new(ModuleCode::DhcpInvalidPoolStart, "Некоректний pool_start")
        })?;
        let last: Ipv4Addr = cfg.pool.lan.end.as_str().parse().map_err(|_| {
            ModuleError::new(ModuleCode::DhcpInvalidPoolEnd, "Некоректний pool_end")
        })?;
        let gateway: Ipv4Addr =
            cfg.network.lan.gateway.as_str().parse().map_err(|_| {
                ModuleError::new(ModuleCode::DhcpInvalidGateway, "Некоректний gateway")
            })?;
        let mask = u32::MAX << (32 - lan.prefix);
        let network = subnet(lan.lan_ip, lan.prefix);
        let broadcast = network | !mask;
        if u32::from(first) > u32::from(last)
            || !lan.contains(first)
            || !lan.contains(last)
            || u32::from(first) <= network
            || u32::from(last) >= broadcast
            || (u32::from(first) <= u32::from(lan.lan_ip)
                && u32::from(lan.lan_ip) <= u32::from(last))
            || gateway != lan.lan_ip
        {
            return Err(ModuleError::new(
                ModuleCode::DhcpPoolOutsideLan,
                "DHCP pool/gateway поза LAN або включає адресу роутера",
            ));
        }
        // У DHCP Network можна передати IP локального DNS роутера або зовнішні DNS.
        let dns_servers = cfg
            .network
            .lan
            .dns_servers
            .iter()
            .map(|item| {
                let ip: Ipv4Addr = item.parse().map_err(|_| {
                    ModuleError::new(ModuleCode::DhcpInvalidDns, "Некоректний DHCP DNS")
                })?;
                if ip.is_unspecified() || ip.is_multicast() || ip.is_broadcast() {
                    return Err(ModuleError::new(
                        ModuleCode::DhcpUnsafeDns,
                        "Недопустимий DHCP DNS",
                    ));
                }
                Ok(ip)
            })
            .collect::<Result<Vec<_>, ModuleError>>()?;
        if dns_servers.is_empty() {
            return Err(ModuleError::new(
                ModuleCode::DhcpMissingDns,
                "DHCP потребує DNS-сервер",
            ));
        }
        let lease_time = cfg.server.lan.lease_time.clone();
        if lease_time.is_empty()
            || !lease_time
                .chars()
                .all(|ch| ch.is_ascii_digit() || matches!(ch, 's' | 'm' | 'h' | 'd' | 'w'))
        {
            return Err(ModuleError::new(
                ModuleCode::DhcpInvalidLeaseTime,
                "Некоректний DHCP lease_time",
            ));
        }
        Ok(Self {
            enabled,
            server_name,
            pool_name,
            first,
            last,
            gateway,
            dns_servers,
            lease_time,
            interface: lan.lan_interface.clone(),
            network: format!("{}/{}", Ipv4Addr::from(network), lan.prefix),
        })
    }

    pub fn commands(&self) -> Vec<String> {
        if !self.enabled {
            return vec!["# DHCP: вимкнено в конфігурації".into()];
        }
        let dns = self
            .dns_servers
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>()
            .join(",");
        vec![
            "# DHCP: перед імпортом перевірити існуючі pool/server/network".into(),
            format!("/ip pool add name={} ranges={}-{}", self.pool_name, self.first, self.last),
            format!("/ip dhcp-server network add address={} gateway={} dns-server={}", self.network, self.gateway, dns),
            format!("/ip dhcp-server add name={} interface={} address-pool={} lease-time={} disabled=no", self.server_name, self.interface, self.pool_name, self.lease_time),
        ]
    }
}
