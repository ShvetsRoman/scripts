use super::cross_errors::{CrossCode, CrossError};
use super::{dhcp::Dhcp, dns::Dns, network::Network, services::Services, wan::Wan};
use mikrotik_config_manager::typed_config::{FirewallConfig, NatConfig, WireguardConfig};

// Міжмодульні залежності перевіряємо після завантаження та локальної валідації.
// Це єдина перевірка для повного й вибіркового планів, без доступу до RouterOS.
// Контекст узгодженості збирає всі взаємопов'язані модулі в один аргумент.
// Це дозволяє розширювати перевірку без громіздкої сигнатури та винятків Clippy.
pub struct Context<'a> {
    pub network: &'a Network,
    pub dhcp: &'a Dhcp,
    pub dns: &'a Dns,
    pub wan: &'a Wan,
    pub nat: &'a NatConfig,
    pub firewall: &'a FirewallConfig,
    pub services: &'a Services,
    pub wireguard: &'a WireguardConfig,
}

pub fn check(context: &Context<'_>) -> Result<(), CrossError> {
    let Context {
        network,
        dhcp,
        dns,
        wan,
        nat,
        firewall,
        services,
        wireguard,
    } = context;
    let nat_enabled = nat.nat.enabled;
    let masquerade = nat.nat.masquerade;
    let fw_enabled = firewall.firewall.enabled;
    let lan_to_wan = firewall.firewall.lan_to_wan;
    let input_drop = firewall.firewall.input_default_drop;
    let forward_drop = firewall.firewall.forward_default_drop;
    let wg_enabled = wireguard.wireguard.enabled;

    // DHCP передає IP роутера як DNS: локальний DNS cache має бути доступним.
    if dhcp.enabled
        && dhcp.dns_servers.contains(&network.lan_ip)
        && (!dns.enabled() || !dns.allow_remote_requests)
    {
        return Err(CrossError::new(
            CrossCode::Consistency01,
            "Consistency: DHCP DNS вказує на роутер, але DNS cache вимкнено".to_string(),
        ));
    }
    if dns.allow_remote_requests && dns.enabled() && !fw_enabled {
        return Err(CrossError::new(
            CrossCode::Consistency02,
            "Consistency: DNS cache потребує активного Firewall".to_string(),
        ));
    }
    // У типовій домашній конфігурації LAN→WAN потребує маршруту і NAT.
    if lan_to_wan && (!wan.enabled || !nat_enabled || !masquerade) {
        return Err(CrossError::new(
            CrossCode::Consistency03,
            "Consistency: LAN→WAN потребує WAN та NAT masquerade".to_string(),
        ));
    }
    if (lan_to_wan || wg_enabled) && (!fw_enabled || !input_drop || !forward_drop) {
        return Err(CrossError::new(
            CrossCode::Consistency04,
            "Consistency: потрібні Firewall та фінальні INPUT/FORWARD DROP".to_string(),
        ));
    }
    if wg_enabled {
        let wg_port = wireguard.wireguard.listen_port;
        if wg_port == services.ssh_port || wg_port == services.winbox_port {
            return Err(CrossError::new(
                CrossCode::Consistency05,
                "Consistency: порт WireGuard конфліктує з портом керування".to_string(),
            ));
        }
        // Дозволи VPN-керування не повинні бути увімкнені, якщо служба вимкнена.
        if wireguard.wireguard.allow_winbox && !services.winbox_enabled {
            return Err(CrossError::new(
                CrossCode::Consistency06,
                "Consistency: WireGuard дозволяє вимкнений WinBox".to_string(),
            ));
        }
    }
    Ok(())
}
