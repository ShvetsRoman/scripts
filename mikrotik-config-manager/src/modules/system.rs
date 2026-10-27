use super::reference_error::{ModuleCode, ModuleError};
use super::token;
use mikrotik_config_manager::typed_config::SystemConfig;

// Системні налаштування не змінюються безпосередньо: лише формують план.
pub struct System {
    commands: Vec<String>,
}
impl System {
    pub fn parse(cfg: &SystemConfig) -> Result<Self, ModuleError> {
        let hostname = cfg.identity.name.as_str();
        let timezone = cfg.clock.timezone.as_str();
        token(hostname, "identity.name")
            .map_err(|error| ModuleError::from_token(ModuleCode::SystemIdentity, error))?;
        if timezone != "Europe/Kyiv" {
            return Err(ModuleError::new(
                ModuleCode::SystemTimezone,
                "Поки підтримується лише Europe/Kyiv",
            ));
        }
        let enabled = cfg.ntp.enabled;
        let servers = &cfg.ntp.servers;
        let mut result = vec![
            "# SYSTEM: identity, timezone, NTP · тільки план".to_owned(),
            format!("/system identity set name={hostname}"),
            format!("/system clock set time-zone-autodetect=no time-zone-name={timezone}"),
        ];
        if enabled {
            if servers.is_empty() {
                return Err(ModuleError::new(
                    ModuleCode::SystemNtpMissing,
                    "NTP: потрібен хоча б один сервер",
                ));
            }
            let values = servers.iter().map(String::as_str).collect::<Vec<_>>();
            if values.len() > 4 {
                return Err(ModuleError::new(
                    ModuleCode::SystemNtpCount,
                    "NTP: максимум чотири сервери",
                ));
            }
            for server in &values {
                token(server, "ntp.server")
                    .map_err(|error| ModuleError::from_token(ModuleCode::SystemNtpToken, error))?;
            }
            result.push("/system ntp client set enabled=yes mode=unicast".into());
            // RouterOS 7: сервери NTP Client налаштовуються в окремому меню servers.
            for server in values {
                result.push(format!("/system ntp client servers add address={server}"));
            }
        } else {
            result.push("/system ntp client set enabled=no".into());
        }
        Ok(Self { commands: result })
    }
    pub fn commands(&self) -> Vec<String> {
        self.commands.clone()
    }
}
