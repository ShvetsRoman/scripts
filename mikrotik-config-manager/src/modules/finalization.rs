use super::cross_errors::{CrossCode, CrossError};
use mikrotik_config_manager::typed_config::{
    FirewallConfig, ListsConfig, ServicesConfig, SystemConfig, WireguardConfig,
};

// Фінальна перевірка політик: не допускаємо взаємно суперечливих
// налаштувань навіть для вибіркового плану. Команди RouterOS тут не виконуємо.
pub fn check(
    firewall: &FirewallConfig,
    services: &ServicesConfig,
    wireguard: &WireguardConfig,
    system: &SystemConfig,
    lists: &ListsConfig,
) -> Result<(), CrossError> {
    let wan = lists.lists.get("wan").ok_or_else(|| {
        CrossError::new(
            CrossCode::Finalization01,
            "Finalization: відсутній WAN list".to_string(),
        )
    })?;
    let lan = lists.lists.get("lan").ok_or_else(|| {
        CrossError::new(
            CrossCode::Finalization02,
            "Finalization: відсутній LAN list".to_string(),
        )
    })?;
    // Назви WAN/LAN мають бути різними: інакше правила INPUT/FORWARD
    // можуть помилково прирівняти зовнішній трафік до локального.
    if wan.name == lan.name {
        return Err(CrossError::new(
            CrossCode::Finalization03,
            "Finalization: WAN та LAN Interface Lists мають різні назви".to_string(),
        ));
    }
    let fw_enabled = firewall.firewall.enabled;
    let ssh_enabled = services.services.ssh.enabled;
    let winbox_enabled = services.services.winbox.enabled;
    let wg = &wireguard.wireguard;
    let wg_enabled = wg.enabled;
    let allow_ssh = wg.allow_ssh;
    let allow_winbox = wg.allow_winbox;
    let allow_wan = wg.allow_wan;
    let allow_lan = wg.allow_lan;
    let allow_internet = wg.allow_internet;

    // Для вимкненого WireGuard не залишаємо прихованих активних дозволів.
    if !wg_enabled && (allow_ssh || allow_winbox || allow_wan || allow_lan || allow_internet) {
        return Err(CrossError::new(
            CrossCode::Finalization04,
            "Finalization: спочатку увімкни WireGuard, а потім VPN-дозволи".to_string(),
        ));
    }
    if wg_enabled
        && (allow_ssh || allow_winbox || allow_wan || allow_lan || allow_internet)
        && !fw_enabled
    {
        return Err(CrossError::new(
            CrossCode::Finalization05,
            "Finalization: VPN-дозволи потребують увімкненого Firewall".to_string(),
        ));
    }
    if allow_ssh && !ssh_enabled {
        return Err(CrossError::new(
            CrossCode::Finalization06,
            "Finalization: VPN SSH дозволено для вимкненого SSH-сервісу".to_string(),
        ));
    }
    if allow_winbox && !winbox_enabled {
        return Err(CrossError::new(
            CrossCode::Finalization07,
            "Finalization: VPN WinBox дозволено для вимкненого WinBox-сервісу".to_string(),
        ));
    }
    // Налаштування MAC-керування не може посилатися на WAN.
    if system.mac_access.interface_list != "@lists.lan" {
        return Err(CrossError::new(
            CrossCode::Finalization08,
            "Finalization: MAC-керування дозволене лише через LAN".to_string(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod typed_finalization_tests {
    use super::*;
    use mikrotik_config_manager::typed_config::read_typed;

    #[test]
    fn both_profiles_have_consistent_typed_finalization() {
        for profile in ["test", "hap-ac"] {
            let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("routers")
                .join(profile);
            let fw = read_typed::<FirewallConfig>(&dir.join("firewall.toml")).unwrap();
            let services = read_typed::<ServicesConfig>(&dir.join("services.toml")).unwrap();
            let wg = read_typed::<WireguardConfig>(&dir.join("wireguard.toml")).unwrap();
            let system = read_typed::<SystemConfig>(&dir.join("system.toml")).unwrap();
            let lists = read_typed::<ListsConfig>(&dir.join("lists.toml")).unwrap();
            assert!(
                check(&fw, &services, &wg, &system, &lists).is_ok(),
                "{profile}"
            );
        }
    }

    #[test]
    fn typed_finalization_rejects_vpn_permissions_when_disabled() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("routers/test");
        let fw = read_typed::<FirewallConfig>(&dir.join("firewall.toml")).unwrap();
        let services = read_typed::<ServicesConfig>(&dir.join("services.toml")).unwrap();
        let mut wg = read_typed::<WireguardConfig>(&dir.join("wireguard.toml")).unwrap();
        let system = read_typed::<SystemConfig>(&dir.join("system.toml")).unwrap();
        let lists = read_typed::<ListsConfig>(&dir.join("lists.toml")).unwrap();
        wg.wireguard.enabled = false;
        wg.wireguard.allow_ssh = true;
        assert!(matches!(
            check(&fw, &services, &wg, &system, &lists),
            Err(CrossError {
                code: CrossCode::Finalization04,
                ..
            })
        ));
    }
}
