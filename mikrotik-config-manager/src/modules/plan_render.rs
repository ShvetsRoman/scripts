use super::*;

// Єдина точка компонування PLAN: порядок RouterOS-команд незмінний.
pub(super) struct Components<'a> {
    pub(super) interfaces: &'a interfaces::Interfaces,
    pub(super) bridge: &'a bridge::Bridge,
    pub(super) network: &'a network::Network,
    pub(super) lists: &'a lists::Lists,
    pub(super) dhcp: &'a dhcp::Dhcp,
    pub(super) leases: &'a leases::Leases,
    pub(super) dns: &'a dns::Dns,
    pub(super) wan: &'a wan::Wan,
    pub(super) wireguard: &'a wireguard::Wireguard,
    pub(super) nat: &'a nat::Nat,
    pub(super) firewall: &'a firewall::Firewall,
    pub(super) ipv6: &'a ipv6::Ipv6,
    pub(super) wireless: &'a wireless::Wireless,
    pub(super) system: &'a system::System,
    pub(super) services: &'a services::Services,
    pub(super) security: &'a security::Security,
}

pub(super) fn compose(
    router: &str,
    selected: Option<&str>,
    components: Components<'_>,
) -> Result<Vec<String>, reference_error::PlanError> {
    let Components {
        interfaces,
        bridge,
        network,
        lists,
        dhcp,
        leases,
        dns,
        wan,
        wireguard,
        nat,
        firewall,
        ipv6,
        wireless,
        system,
        services,
        security,
    } = components;
    let mut lines = vec![format!(
        "# RouterOS 7 · {router} · PLAN ONLY · НЕ ІМПОРТУВАТИ БЕЗ ПЕРЕВІРКИ"
    )];
    match selected {
        None | Some("all") => {
            lines.extend(interfaces.commands());
            lines.extend(bridge.commands());
            lines.extend(network.commands());
            lines.extend(lists.commands());
            lines.extend(dhcp.commands());
            lines.extend(leases.commands());
            lines.extend(dns.commands());
            lines.extend(wan.commands());
            lines.extend(wireguard.commands());
            lines.extend(nat.commands());
            lines.extend(wireguard.nat_rules(&lists.wan));
            lines.extend(firewall.commands_with_wireguard(Some(wireguard), nat.forwards()));
            lines.extend(ipv6.commands());
            lines.extend(wireless.commands());
            lines.extend(system.commands());
            lines.extend(services.commands());
            lines.extend(security.commands());
        }
        Some("interfaces") => lines.extend(interfaces.commands()),
        Some("bridge") => lines.extend(bridge.commands()),
        Some("network") => {
            lines.extend(bridge.commands());
            lines.extend(network.commands());
        }
        Some("lists") => lines.extend(lists.commands()),
        Some("dhcp") => {
            lines.extend(dhcp.commands());
            lines.extend(leases.commands());
        }
        Some("leases") => lines.extend(leases.commands()),
        Some("dns") => lines.extend(dns.commands()),
        Some("wan") => lines.extend(wan.commands()),
        Some("nat") => {
            lines.extend(nat.commands());
            lines.extend(wireguard.nat_rules(&lists.wan));
        }
        Some("firewall") => {
            lines.extend(firewall.commands_with_wireguard(Some(wireguard), nat.forwards()));
            lines.extend(ipv6.commands());
        }
        Some("wireless") => lines.extend(wireless.commands()),
        Some("system") => lines.extend(system.commands()),
        Some("services") => lines.extend(services.commands()),
        Some("security") => lines.extend(security.commands()),
        Some("wireguard") => lines.extend(wireguard.commands()),
        Some(other) => {
            return Err(reference_error::ConfigurationError {
                code: reference_error::ConfigurationCode::UnknownModule,
                detail: format!("Невідомий модуль: {other}"),
            }
            .into())
        }
    }
    Ok(lines)
}
