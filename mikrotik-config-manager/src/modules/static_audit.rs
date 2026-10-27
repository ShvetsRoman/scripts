use super::cross_errors::{CrossCode, CrossError};
use super::network::{parse_address, subnet};
use mikrotik_config_manager::typed_config::{
    BridgeConfig, DhcpConfig, DnsConfig, FirewallConfig, InterfacesConfig, NetworkConfig,
    WireguardConfig, WirelessConfig,
};
use std::collections::HashSet;
use std::net::Ipv4Addr;

// Аудит отримує безпосередньо типізовані TOML ресурси.
pub struct Context<'a> {
    pub network: &'a NetworkConfig,
    pub bridge: &'a BridgeConfig,
    pub interfaces: &'a InterfacesConfig,
    pub dhcp: &'a DhcpConfig,
    pub dns: &'a DnsConfig,
    pub firewall: &'a FirewallConfig,
    pub wireless: &'a WirelessConfig,
    pub wireguard: &'a WireguardConfig,
}

pub fn check(context: &Context<'_>) -> Result<(), CrossError> {
    let Context {
        network,
        bridge,
        interfaces,
        dhcp,
        dns,
        firewall,
        wireless,
        wireguard,
    } = context;
    let (lan_ip, lan_prefix) = parse_address(&network.network.lan.address)
        .map_err(|detail| CrossError::from_ipv4(CrossCode::Static19, detail))?;
    let (mgmt_ip, mgmt_prefix) = parse_address(&network.management.address)
        .map_err(|detail| CrossError::from_ipv4(CrossCode::Static19, detail))?;
    let shared = network.management.on_lan;
    if !shared && overlap(lan_ip, lan_prefix, mgmt_ip, mgmt_prefix) {
        return Err(CrossError::new(
            CrossCode::Static01,
            "Static Audit: перетин підмереж LAN та Management".to_string(),
        ));
    }
    if !shared && network.management.interface == "@bridge.lan" {
        return Err(CrossError::new(
            CrossCode::Static02,
            "Static Audit: окремий Management не може використовувати LAN Bridge".to_string(),
        ));
    }
    if !valid_host(lan_ip, lan_prefix) || !valid_host(mgmt_ip, mgmt_prefix) {
        return Err(CrossError::new(
            CrossCode::Static03,
            "Static Audit: адреса маршрутизатора є network/broadcast".to_string(),
        ));
    }
    let mut lease_addresses = HashSet::new();
    let mut lease_macs = HashSet::new();
    for lease in dhcp.leases.devices.values() {
        let ip: Ipv4Addr = lease.address.parse().map_err(|error| {
            CrossError::from_address_parse(
                CrossCode::Static04,
                "Static Audit: некоректна адреса lease",
                error,
            )
        })?;
        if !valid_host(ip, lan_prefix) || subnet(ip, lan_prefix) != subnet(lan_ip, lan_prefix) {
            return Err(CrossError::new(
                CrossCode::Static05,
                "Static Audit: lease використовує network/broadcast або адресу поза LAN"
                    .to_string(),
            ));
        }
        if !lease_addresses.insert(ip) {
            return Err(CrossError::new(
                CrossCode::Static06,
                "Static Audit: повтор IP у leases".to_string(),
            ));
        }
        if !lease_macs.insert(lease.mac.to_ascii_uppercase()) {
            return Err(CrossError::new(
                CrossCode::Static07,
                "Static Audit: повтор MAC у leases".to_string(),
            ));
        }
    }
    for id in bridge.ports.keys() {
        if !interfaces.interfaces.contains_key(id) {
            return Err(CrossError::new(
                CrossCode::Static15,
                format!("Static Audit: Bridge-порт {id} відсутній в interfaces.toml"),
            ));
        }
    }
    let first: Ipv4Addr = dhcp.pool.lan.start.parse().map_err(|error| {
        CrossError::from_address_parse(CrossCode::Static08, "Static Audit: pool.start", error)
    })?;
    let last: Ipv4Addr = dhcp.pool.lan.end.parse().map_err(|error| {
        CrossError::from_address_parse(CrossCode::Static09, "Static Audit: pool.end", error)
    })?;
    if u32::from(first) > u32::from(last) {
        return Err(CrossError::new(
            CrossCode::Static10,
            "Static Audit: DHCP pool має неправильний діапазон".to_string(),
        ));
    }
    let mut seen_dns = HashSet::new();
    for value in &dhcp.network.lan.dns_servers {
        let ip: Ipv4Addr = value.trim().parse().map_err(|error| {
            CrossError::from_address_parse(
                CrossCode::Static11,
                "Static Audit: DHCP DNS не є IPv4",
                error,
            )
        })?;
        if !seen_dns.insert(ip) {
            return Err(CrossError::new(
                CrossCode::Static12,
                "Static Audit: повторена адреса DHCP DNS".to_string(),
            ));
        }
    }
    if !dns.dns.enabled && seen_dns.contains(&lan_ip) {
        return Err(CrossError::new(
            CrossCode::Static13,
            "Static Audit: DHCP вказує на вимкнений DNS маршрутизатора".to_string(),
        ));
    }
    let bridge_ports: HashSet<&str> = bridge
        .ports
        .iter()
        .filter(|(_, port)| port.enabled)
        .map(|(id, _)| id.as_str())
        .collect();
    if wireless.wireless.enabled {
        for id in wireless.wireless.radios.keys() {
            if let Some(radio) = wireless.wireless.radios.get(id) {
                if radio.enabled {
                    if bridge_ports.contains(id.as_str()) {
                        return Err(CrossError::new(
                            CrossCode::Static16,
                            format!("Static Audit: {id} дублюється в Bridge та Wireless"),
                        ));
                    }
                    if !interfaces.interfaces.contains_key(id) {
                        return Err(CrossError::new(
                            CrossCode::Static17,
                            format!("Static Audit: невідомий фізичний Wi-Fi інтерфейс {id}"),
                        ));
                    }
                    let profile_id = radio
                        .security
                        .strip_prefix("@security.")
                        .unwrap_or(&radio.security);
                    if !wireless.security.contains_key(profile_id) {
                        return Err(CrossError::new(CrossCode::Static18, format!("Static Audit: Wi-Fi {id} посилається на невідомий Security Profile")));
                    }
                }
            }
        }
    }
    if dhcp.server.lan.enabled && (!firewall.firewall.enabled || !firewall.firewall.allow_lan_dhcp)
    {
        return Err(CrossError::new(
            CrossCode::Static14,
            "Static Audit: DHCP Server потребує дозволу Firewall INPUT DHCP".to_string(),
        ));
    }
    // Boolean-поля VPN вже строго типізовані serde, навіть коли VPN вимкнений.
    let _ = &wireguard.wireguard;
    Ok(())
}

// Спільна IPv4/CIDR-математика, однакова для Network/WireGuard/Static Audit.
fn valid_host(ip: Ipv4Addr, prefix: u8) -> bool {
    super::ipv4_math::valid_host(ip, prefix)
}

fn overlap(a: Ipv4Addr, ap: u8, b: Ipv4Addr, bp: u8) -> bool {
    super::ipv4_math::overlaps((a, ap), (b, bp))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_ipv4_network_and_broadcast() {
        assert!(!valid_host("192.168.88.0".parse().unwrap(), 24));
        assert!(!valid_host("192.168.88.255".parse().unwrap(), 24));
        assert!(valid_host("192.168.88.1".parse().unwrap(), 24));
    }
    #[test]
    fn rejects_ipv4_host_in_small_network() {
        assert!(!valid_host("10.0.0.0".parse().unwrap(), 30));
        assert!(!valid_host("10.0.0.3".parse().unwrap(), 30));
        assert!(valid_host("10.0.0.2".parse().unwrap(), 30));
    }
    #[test]
    fn cidr_partial_overlap_is_detected() {
        assert!(overlap(
            "192.168.88.1".parse().unwrap(),
            24,
            "192.168.88.200".parse().unwrap(),
            25
        ));
        assert!(!overlap(
            "192.168.88.1".parse().unwrap(),
            24,
            "192.168.56.10".parse().unwrap(),
            24
        ));
    }
    #[test]
    fn cidr_nested_overlap_is_detected() {
        assert!(overlap(
            "10.0.0.1".parse().unwrap(),
            8,
            "10.77.0.1".parse().unwrap(),
            24
        ));
    }
}

#[cfg(test)]
mod typed_audit_tests {
    use super::*;
    use mikrotik_config_manager::typed_config::read_typed;

    #[test]
    fn both_profiles_pass_typed_static_audit() {
        for profile in ["test", "hap-ac"] {
            let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("routers")
                .join(profile);
            let network = read_typed::<NetworkConfig>(&dir.join("network.toml")).unwrap();
            let bridge = read_typed::<BridgeConfig>(&dir.join("bridge.toml")).unwrap();
            let interfaces = read_typed::<InterfacesConfig>(&dir.join("interfaces.toml")).unwrap();
            let dhcp = read_typed::<DhcpConfig>(&dir.join("dhcp.toml")).unwrap();
            let dns = read_typed::<DnsConfig>(&dir.join("dns.toml")).unwrap();
            let firewall = read_typed::<FirewallConfig>(&dir.join("firewall.toml")).unwrap();
            let wireless = read_typed::<WirelessConfig>(&dir.join("wireless.toml")).unwrap();
            let wireguard = read_typed::<WireguardConfig>(&dir.join("wireguard.toml")).unwrap();
            assert!(
                check(&Context {
                    network: &network,
                    bridge: &bridge,
                    interfaces: &interfaces,
                    dhcp: &dhcp,
                    dns: &dns,
                    firewall: &firewall,
                    wireless: &wireless,
                    wireguard: &wireguard
                })
                .is_ok(),
                "{profile}"
            );
        }
    }
}

#[cfg(test)]
mod regression_negative_tests {
    use super::*;
    use mikrotik_config_manager::typed_config::read_typed;

    #[test]
    fn overlapping_management_network_has_typed_code() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("routers/test");
        let mut network = read_typed::<NetworkConfig>(&dir.join("network.toml")).unwrap();
        let bridge = read_typed::<BridgeConfig>(&dir.join("bridge.toml")).unwrap();
        let interfaces = read_typed::<InterfacesConfig>(&dir.join("interfaces.toml")).unwrap();
        let dhcp = read_typed::<DhcpConfig>(&dir.join("dhcp.toml")).unwrap();
        let dns = read_typed::<DnsConfig>(&dir.join("dns.toml")).unwrap();
        let firewall = read_typed::<FirewallConfig>(&dir.join("firewall.toml")).unwrap();
        let wireless = read_typed::<WirelessConfig>(&dir.join("wireless.toml")).unwrap();
        let wireguard = read_typed::<WireguardConfig>(&dir.join("wireguard.toml")).unwrap();
        network.management.on_lan = false;
        network.management.address = network.network.lan.address.clone();
        let result = check(&Context {
            network: &network,
            bridge: &bridge,
            interfaces: &interfaces,
            dhcp: &dhcp,
            dns: &dns,
            firewall: &firewall,
            wireless: &wireless,
            wireguard: &wireguard,
        });
        assert!(matches!(
            result,
            Err(CrossError {
                code: CrossCode::Static01,
                ..
            })
        ));
    }
}
