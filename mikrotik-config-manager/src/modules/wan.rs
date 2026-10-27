use super::reference_error::{ModuleCode, ModuleError};
use super::{network::Network, token};
use mikrotik_config_manager::typed_config::WanConfig;

// WAN є незалежним від Management та LAN.
pub struct Wan {
    pub interface: String,
    pub enabled: bool,
    default_route: bool,
    peer_dns: bool,
}
impl Wan {
    pub fn parse(
        config: &WanConfig,
        interface: String,
        lan: &Network,
    ) -> Result<Self, ModuleError> {
        token(&interface, "wan.interface")
            .map_err(|detail| ModuleError::from_token(ModuleCode::WanInterfaceConflict, detail))?;
        if interface == lan.lan_interface
            || interface == lan.management_interface
            || lan.lan_ports.iter().any(|port| port == &interface)
        {
            return Err(ModuleError::new(
                ModuleCode::WanInterfaceConflict,
                "WAN не може збігатися з LAN або Management",
            ));
        }
        Ok(Self {
            interface,
            enabled: config.enabled,
            default_route: config.add_default_route,
            peer_dns: config.use_peer_dns,
        })
    }
    pub fn commands(&self) -> Vec<String> {
        if !self.enabled {
            return vec!["# WAN: вимкнено".into()];
        }
        vec!["# WAN: очищення IPv4 DHCP Client лише в сценарії початкового налаштування після RESET".into(),
            "/ip dhcp-client remove [find]".into(),
            format!("/ip dhcp-client add interface={} disabled=no add-default-route={} use-peer-dns={} comment=mcm-wan-dhcp",
                self.interface, if self.default_route {"yes"} else {"no"}, if self.peer_dns {"yes"} else {"no"})]
    }
}
