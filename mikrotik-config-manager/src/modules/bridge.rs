use super::interfaces::Interfaces;
use super::reference_error::{ModuleCode, ModuleError};
use super::token;
use mikrotik_config_manager::typed_config::BridgeResource;

// Окремий опис Bridge; не залежить від термінального інтерфейсу.
pub struct Bridge {
    pub name: String,
    pub ports: Vec<String>,
    protocol_mode: String,
    hw_offload: bool,
}
impl Bridge {
    pub fn parse(
        config: &BridgeResource,
        ports: Vec<String>,
        hw_offload: bool,
        interfaces: &Interfaces,
    ) -> Result<Self, ModuleError> {
        let name = config.name.clone();
        token(&name, "bridge.name")
            .map_err(|e| ModuleError::from_token(ModuleCode::BridgeName, e))?;
        let protocol_mode = config.protocol_mode.clone();
        if !["rstp", "stp", "none"].contains(&protocol_mode.as_str()) {
            return Err(ModuleError::new(
                ModuleCode::BridgeProtocol,
                "Некоректний bridge.protocol_mode",
            ));
        }
        let mut resolved_ports = Vec::new();
        for port in ports {
            token(&port, "bridge.ports")
                .map_err(|e| ModuleError::from_token(ModuleCode::BridgeName, e))?;
            let resolved = interfaces.resolved(&port);
            if resolved == name || resolved_ports.contains(&resolved) {
                return Err(ModuleError::new(
                    ModuleCode::BridgePort,
                    "Повторення або некоректний порт Bridge",
                ));
            }
            resolved_ports.push(resolved);
        }
        if resolved_ports.is_empty() {
            return Err(ModuleError::new(
                ModuleCode::BridgeEmpty,
                "Bridge повинен мати порти",
            ));
        }
        Ok(Self {
            name,
            ports: resolved_ports,
            protocol_mode,
            hw_offload,
        })
    }
    pub fn commands(&self) -> Vec<String> {
        let mut commands = vec![
            "# BRIDGE: спочатку bridge, потім bridge ports".into(),
            format!(
                "/interface bridge add name={} protocol-mode={} comment=mcm-lan-bridge",
                self.name, self.protocol_mode
            ),
        ];
        for port in &self.ports {
            if self.hw_offload {
                commands.push(format!(
                    "/interface bridge port add bridge={} interface={} hw=yes",
                    self.name, port
                ));
            } else {
                commands.push(format!(
                    "/interface bridge port add bridge={} interface={}",
                    self.name, port
                ));
            }
        }
        commands
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mikrotik_config_manager::typed_config::InterfaceResource;
    use std::collections::BTreeMap;

    fn interfaces() -> Interfaces {
        let resources = BTreeMap::from([
            (
                "ether2".into(),
                InterfaceResource {
                    name: "ether2".into(),
                    enabled: true,
                    comment: String::new(),
                },
            ),
            (
                "ether3".into(),
                InterfaceResource {
                    name: "ether3".into(),
                    enabled: true,
                    comment: String::new(),
                },
            ),
        ]);
        Interfaces::parse(&resources, "ether1", "ether1").unwrap()
    }

    fn resource() -> BridgeResource {
        BridgeResource {
            name: "bridge-lan".into(),
            enabled: true,
            protocol_mode: "rstp".into(),
        }
    }

    #[test]
    fn typed_bridge_preserves_command_order_and_hw() {
        let bridge = Bridge::parse(
            &resource(),
            vec!["ether2".into(), "ether3".into()],
            false,
            &interfaces(),
        )
        .unwrap();
        let commands = bridge.commands();
        assert!(commands[1].contains("/interface bridge add name=bridge-lan protocol-mode=rstp"));
        assert_eq!(
            commands[2],
            "/interface bridge port add bridge=bridge-lan interface=ether2"
        );
        assert_eq!(
            commands[3],
            "/interface bridge port add bridge=bridge-lan interface=ether3"
        );
        assert!(
            Bridge::parse(&resource(), vec!["ether2".into()], true, &interfaces())
                .unwrap()
                .commands()[2]
                .ends_with("hw=yes")
        );
    }

    #[test]
    fn typed_bridge_rejects_duplicate_or_missing_ports() {
        assert!(Bridge::parse(&resource(), Vec::new(), false, &interfaces()).is_err());
        assert!(Bridge::parse(
            &resource(),
            vec!["ether2".into(), "ether2".into()],
            false,
            &interfaces()
        )
        .is_err());
    }
}
