use super::lists::Lists;
use super::reference_error::{SecurityCode, SecurityError};
use super::token;
use mikrotik_config_manager::typed_config::SystemConfig;

// Користувачів визначаємо декларативно: ім’я та група — у TOML,
// паролі — тільки у .secrets. План не виводить жодного пароля.
pub struct Security {
    commands: Vec<String>,
}

impl Security {
    pub fn parse(data: &SystemConfig, lists: &Lists, _router: &str) -> Result<Self, SecurityError> {
        let users = &data.users;
        let admin = users.get("admin").ok_or_else(|| SecurityError {
            code: SecurityCode::MissingAdmin,
            detail: "Немає users.admin".into(),
            cause: None,
        })?;
        let username = admin.name.as_str();
        token(username, "users.admin.name")
            .map_err(|detail| SecurityError::from_token(SecurityCode::InvalidAdminGroup, detail))?;
        let group = admin.group.as_str();
        token(group, "users.admin.group")
            .map_err(|detail| SecurityError::from_token(SecurityCode::InvalidAdminGroup, detail))?;
        if group != "full" {
            return Err(SecurityError {
                code: SecurityCode::InvalidAdminGroup,
                detail: "Адміністративна група повинна бути full".into(),
                cause: None,
            });
        }
        for (id, user) in users {
            if id == "admin" {
                continue;
            }
            token(&user.name, "users.name").map_err(|detail| {
                SecurityError::from_token(SecurityCode::InvalidUserGroup, detail)
            })?;
            if !matches!(user.group.as_str(), "full" | "read" | "write") {
                return Err(SecurityError {
                    code: SecurityCode::InvalidUserGroup,
                    detail: format!("Непідтримувана група користувача {id}"),
                    cause: None,
                });
            }
        }
        if !data.ssh.strong_crypto {
            return Err(SecurityError {
                code: SecurityCode::WeakSshCrypto,
                detail: "SSH strong-crypto не можна вимикати".into(),
                cause: None,
            });
        }
        if data.mac_access.interface_list != "@lists.lan" {
            return Err(SecurityError {
                code: SecurityCode::InvalidMacAccess,
                detail: "MAC Server/WinBox дозволені тільки через логічний LAN".into(),
                cause: None,
            });
        }
        token(&lists.lan, "mac_access.lan_list")
            .map_err(|detail| SecurityError::from_token(SecurityCode::InvalidMacAccess, detail))?;
        let mac_server = data.mac_access.mac_server;
        let mac_winbox = data.mac_access.mac_winbox;
        let channel = data.updates.channel.as_str();
        if !matches!(channel, "stable" | "long-term" | "testing" | "development") {
            return Err(SecurityError {
                code: SecurityCode::InvalidUpdateChannel,
                detail: "Невідомий канал RouterOS Update".into(),
                cause: None,
            });
        }
        if data.updates.auto_install {
            return Err(SecurityError {
                code: SecurityCode::AutoInstall,
                detail: "Автоматичне встановлення оновлень заборонено".into(),
                cause: None,
            });
        }
        if data.updates.auto_reboot {
            return Err(SecurityError {
                code: SecurityCode::AutoReboot,
                detail: "Автоматичне перезавантаження заборонено".into(),
                cause: None,
            });
        }
        if data.routerboard.upgrade {
            return Err(SecurityError {
                code: SecurityCode::RouterboardUpgrade,
                detail: "RouterBOARD upgrade потребує окремого ручного підтвердження".into(),
                cause: None,
            });
        }
        let mut commands = vec![
            "# SECURITY: лише попередній план, без облікових даних".into(),
            format!("# Адміністратор {username}, група {group}: пароль задається в .secrets"),
            "/ip ssh set strong-crypto=yes".into(),
            format!(
                "/tool mac-server set allowed-interface-list={}",
                if mac_server {
                    lists.lan.as_str()
                } else {
                    "none"
                }
            ),
            format!(
                "/tool mac-server mac-winbox set allowed-interface-list={}",
                if mac_winbox {
                    lists.lan.as_str()
                } else {
                    "none"
                }
            ),
            format!("/system package update set channel={channel}"),
            "# Update: без check-for-updates, download, install або reboot".into(),
        ];
        // Перелік додаткових користувачів у плані — без паролів.
        for (id, user) in users {
            if id != "admin" && user.managed {
                commands.push(format!(
                    "# Користувач {}: група {} (пароль лише у .secrets)",
                    user.name, user.group
                ));
            }
        }
        // Модель обладнання не визначається назвою TOML-профілю.
        commands.push("# RouterBOARD (якщо підтримується обладнанням): перевірити firmware вручну; upgrade не генерується".into());
        Ok(Self { commands })
    }
    pub fn commands(&self) -> Vec<String> {
        self.commands.clone()
    }
}

#[cfg(test)]
mod typed_mac_access_reference_tests {
    use mikrotik_config_manager::typed_config::SystemConfig;

    #[test]
    fn both_profiles_use_declarative_lan_list_reference() {
        for path in ["routers/test/system.toml", "routers/hap-ac/system.toml"] {
            let text = std::fs::read_to_string(path).unwrap();
            let typed: SystemConfig = toml::from_str(&text).unwrap();
            assert_eq!(typed.mac_access.interface_list, "@lists.lan");
        }
    }
}
