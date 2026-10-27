use super::reference_error::{ModuleCode, ModuleError};
use super::token;
use mikrotik_config_manager::typed_config::NetworkConfig;
use std::net::Ipv4Addr;

pub struct Network {
    pub lan_interface: String,
    pub lan_ip: Ipv4Addr,
    pub prefix: u8,
    pub address: String,
    pub management_interface: String,
    pub lan_ports: Vec<String>,
    pub management_address: String,
}

impl Network {
    pub fn parse(
        cfg: &NetworkConfig,
        lan_interface: &str,
        management: &str,
        resolved_ports: &[String],
    ) -> Result<Self, ModuleError> {
        let lan_interface = lan_interface.to_string();
        let management = management.to_string();
        token(&lan_interface, "lan_interface")
            .map_err(|e| ModuleError::from_token(ModuleCode::NetworkInterfaceConflict, e))?;
        token(&management, "management_interface")
            .map_err(|e| ModuleError::from_token(ModuleCode::NetworkInterfaceConflict, e))?;
        let management_on_lan = cfg.management.on_lan;
        if lan_interface == management && !management_on_lan {
            return Err(ModuleError::new(
                ModuleCode::NetworkInterfaceConflict,
                "LAN і Management не можуть бути одним інтерфейсом",
            ));
        }
        let management_address = cfg.management.address.as_str();
        parse_address(management_address)
            .map_err(|e| ModuleError::from_ipv4(ModuleCode::NetworkManagementMismatch, e))?;
        let address = cfg.network.lan.address.clone();
        let (lan_ip, prefix) = parse_address(&address)
            .map_err(|e| ModuleError::from_ipv4(ModuleCode::NetworkLanPrefix, e))?;
        if prefix == 0 || prefix > 30 {
            return Err(ModuleError::new(
                ModuleCode::NetworkLanPrefix,
                "Префікс LAN має бути /1–/30",
            ));
        }
        // Для домашнього роутера Management може використовувати LAN-bridge та його IP.
        // Для окремої мережі керування збіг адрес суворо заборонено.
        if address == management_address && !management_on_lan {
            return Err(ModuleError::new(
                ModuleCode::NetworkAddressConflict,
                "LAN і Management не можуть мати однакову адресу",
            ));
        }
        let (mgmt_ip, mgmt_prefix) = parse_address(management_address)
            .map_err(|e| ModuleError::from_ipv4(ModuleCode::NetworkManagementMismatch, e))?;
        if subnet(lan_ip, prefix) == subnet(mgmt_ip, prefix)
            && prefix == mgmt_prefix
            && !management_on_lan
        {
            return Err(ModuleError::new(
                ModuleCode::NetworkSubnetConflict,
                "LAN і Management не можуть мати однакову підмережу",
            ));
        }
        if management_on_lan && (lan_interface != management || address != management_address) {
            return Err(ModuleError::new(
                ModuleCode::NetworkManagementMismatch,
                "Management на LAN потребує однакових інтерфейсу й IP",
            ));
        }
        let mut lan_ports = Vec::new();
        for port in resolved_ports {
            token(port, "lan_ports")
                .map_err(|e| ModuleError::from_token(ModuleCode::NetworkManagementPort, e))?;
            if port == &management && !management_on_lan {
                return Err(ModuleError::new(
                    ModuleCode::NetworkManagementPort,
                    "Management не може бути LAN-портом",
                ));
            }
            if lan_ports.contains(port) {
                return Err(ModuleError::new(
                    ModuleCode::NetworkDuplicatePort,
                    "Дубль LAN-порту",
                ));
            }
            lan_ports.push(port.clone());
        }
        Ok(Self {
            lan_interface,
            lan_ip,
            prefix,
            address,
            management_interface: management,
            management_address: management_address.to_string(),
            lan_ports,
        })
    }

    pub fn contains(&self, ip: Ipv4Addr) -> bool {
        subnet(ip, self.prefix) == subnet(self.lan_ip, self.prefix)
    }

    pub fn commands(&self) -> Vec<String> {
        let mut lines = vec![
            "# NETWORK: Management залишається незмінним".into(),
            format!("# Management interface: {}", self.management_interface),
            format!(
                "# Перевірити адресу та інтерфейс перед майбутнім застосуванням: {} / {}",
                self.address, self.lan_interface
            ),
        ];
        lines.push(format!(
            "/ip address add address={} interface={} comment=mcm-lan",
            self.address, self.lan_interface
        ));
        lines
    }
}

pub fn parse_address(value: &str) -> Result<(Ipv4Addr, u8), super::shared_errors::Ipv4Error> {
    use super::shared_errors::{Ipv4Code, Ipv4Error};
    let (ip, prefix) = value.split_once('/').ok_or(Ipv4Error {
        code: Ipv4Code::MissingPrefix,
    })?;
    let ip: Ipv4Addr = ip.parse().map_err(|_| Ipv4Error {
        code: Ipv4Code::InvalidAddress,
    })?;
    let prefix: u8 = prefix.parse().map_err(|_| Ipv4Error {
        code: Ipv4Code::InvalidPrefix,
    })?;
    if prefix > 32 {
        return Err(Ipv4Error {
            code: Ipv4Code::PrefixOutOfRange,
        });
    }
    Ok((ip, prefix))
}

pub fn subnet(ip: Ipv4Addr, prefix: u8) -> u32 {
    super::ipv4_math::subnet(ip, prefix)
}
