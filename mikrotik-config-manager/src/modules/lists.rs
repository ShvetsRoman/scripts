use super::network::Network;
use super::reference_error::{ModuleCode, ModuleError};
use super::token;
use super::wan::Wan;
use mikrotik_config_manager::typed_config::ListResource;

// Назви списків задаються незалежно від назв інтерфейсів.
pub struct Lists {
    pub enabled: bool,
    pub wan: String,
    pub lan: String,
    wan_port: String,
    lan_bridge: String,
}
impl Lists {
    pub fn parse(
        wan_resource: &ListResource,
        lan_resource: &ListResource,
        network: &Network,
        wan: &Wan,
    ) -> Result<Self, ModuleError> {
        let enabled = wan_resource.enabled && lan_resource.enabled;
        let wan_name = wan_resource.name.clone();
        let lan_name = lan_resource.name.clone();
        token(&wan_name, "wan_name")
            .map_err(|e| ModuleError::from_token(ModuleCode::ListName, e))?;
        token(&lan_name, "lan_name")
            .map_err(|e| ModuleError::from_token(ModuleCode::ListName, e))?;
        if wan_name == lan_name {
            return Err(ModuleError::new(
                ModuleCode::ListDuplicate,
                "Interface lists WAN і LAN мають різні назви",
            ));
        }
        if enabled && !wan.enabled {
            return Err(ModuleError::new(
                ModuleCode::ListWanDisabled,
                "Interface lists потребують увімкнений WAN",
            ));
        }
        Ok(Self {
            enabled,
            wan: wan_name,
            lan: lan_name,
            wan_port: wan.interface.clone(),
            lan_bridge: network.lan_interface.clone(),
        })
    }
    pub fn commands(&self) -> Vec<String> {
        if !self.enabled {
            return vec!["# INTERFACE LISTS: вимкнено".into()];
        }
        vec![
            "# INTERFACE LISTS: спочатку списки, потім учасники".into(),
            format!("/interface list add name={} comment=mcm-wan-list", self.wan),
            format!("/interface list add name={} comment=mcm-lan-list", self.lan),
            format!(
                "/interface list member add list={} interface={}",
                self.wan, self.wan_port
            ),
            format!(
                "/interface list member add list={} interface={}",
                self.lan, self.lan_bridge
            ),
        ]
    }
}
