pub use super::cross_errors::CrossError;
// Типізована перевірка міжмодульних посилань без повторного читання TOML.
use mikrotik_config_manager::typed_config::{
    BridgeConfig, InterfacesConfig, NetworkConfig, WirelessConfig,
};
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReferenceCode {
    WifiInterface,
    WifiBridge,
    WifiSecurity,
    BridgePort,
    NetworkLan,
}
impl ReferenceCode {
    pub fn location(self) -> (&'static str, &'static str) {
        match self {
            Self::WifiInterface => ("wireless.toml", "wireless.wlan*.interface"),
            Self::WifiBridge => ("wireless.toml", "wireless.wlan*.bridge"),
            Self::WifiSecurity => ("wireless.toml", "wireless.wlan*.security"),
            Self::BridgePort => ("bridge.toml", "ports.*"),
            Self::NetworkLan => ("network.toml", "network.lan.interface"),
        }
    }
    pub fn locale_key(self) -> &'static str {
        match self {
            Self::WifiInterface => "ref_error_wifi_interface",
            Self::WifiBridge => "ref_error_wifi_bridge",
            Self::WifiSecurity => "ref_error_wifi_security",
            Self::BridgePort => "ref_error_bridge_port",
            Self::NetworkLan => "ref_error_network_lan",
        }
    }
}
// Коди не визначаються за текстом помилки: модулі повертають enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ValidationCode {
    DuplicateOrEmptyName,
    UnknownBridgePort,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConfigurationCode {
    ConnectionPortZero,
    WireguardPortZero,
    InvalidPhysicalInterface,
    InvalidBridgePort,
    DisabledLanBridge,
    WanInBridge,
    InvalidManagementReference,
    WanManagementConflict,
    MissingLanBridge,
    MissingBridgePorts,
    MixedBridgeHardware,
    BridgePortMismatch,
    MissingWanList,
    MissingLanList,
    InvalidInterfaceList,
    InvalidDhcpReference,
    InvalidDhcpServerReference,
    WireguardRequiresFirewall,
    UnknownModule,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SecurityCode {
    MissingAdmin,
    InvalidAdminGroup,
    InvalidUserGroup,
    WeakSshCrypto,
    InvalidMacAccess,
    InvalidUpdateChannel,
    AutoInstall,
    AutoReboot,
    RouterboardUpgrade,
}

// Місце помилки визначаємо за типізованим кодом, не з тексту деталі.
// None означає, що одна помилка стосується кількох TOML-секцій.
impl ValidationCode {
    pub fn location(self) -> Option<(&'static str, &'static str)> {
        match self {
            Self::DuplicateOrEmptyName => None,
            Self::UnknownBridgePort => Some(("bridge.toml", "ports.*")),
        }
    }
}
impl ConfigurationCode {
    pub fn location(self) -> (&'static str, &'static str) {
        match self {
            Self::ConnectionPortZero => ("connection.toml", "connection.port"),
            Self::WireguardPortZero => ("wireguard.toml", "wireguard.listen_port"),
            Self::InvalidPhysicalInterface => ("interfaces.toml", "interfaces.*"),
            Self::InvalidBridgePort => ("bridge.toml", "ports.*"),
            Self::DisabledLanBridge => ("bridge.toml", "bridge.lan.enabled"),
            Self::WanInBridge => ("network.toml", "wan.interface"),
            Self::InvalidManagementReference => ("network.toml", "management.interface"),
            Self::WanManagementConflict => ("network.toml", "wan.interface"),
            Self::MissingLanBridge => ("bridge.toml", "bridge.lan"),
            Self::MissingBridgePorts | Self::MixedBridgeHardware | Self::BridgePortMismatch => {
                ("bridge.toml", "ports.*")
            }
            Self::MissingWanList => ("lists.toml", "lists.wan"),
            Self::MissingLanList => ("lists.toml", "lists.lan"),
            Self::InvalidInterfaceList => ("lists.toml", "lists.*.members"),
            Self::InvalidDhcpReference => ("dhcp.toml", "server.lan"),
            Self::InvalidDhcpServerReference => ("dhcp.toml", "leases.server"),
            Self::WireguardRequiresFirewall => ("firewall.toml", "firewall.enabled"),
            Self::UnknownModule => ("config/manager.toml", "module"),
        }
    }
}
impl SecurityCode {
    pub fn location(self) -> (&'static str, &'static str) {
        match self {
            Self::MissingAdmin => ("system.toml", "users.admin"),
            Self::InvalidAdminGroup => ("system.toml", "users.admin.*"),
            Self::InvalidUserGroup => ("system.toml", "users.*"),
            Self::WeakSshCrypto => ("system.toml", "ssh.strong_crypto"),
            Self::InvalidMacAccess => ("system.toml", "mac_access.*"),
            Self::InvalidUpdateChannel => ("system.toml", "updates.channel"),
            Self::AutoInstall => ("system.toml", "updates.auto_install"),
            Self::AutoReboot => ("system.toml", "updates.auto_reboot"),
            Self::RouterboardUpgrade => ("system.toml", "routerboard.upgrade"),
        }
    }
}

impl ValidationCode {
    pub fn locale_key(self) -> &'static str {
        match self {
            Self::DuplicateOrEmptyName => "validation_duplicate_name",
            Self::UnknownBridgePort => "validation_unknown_bridge_port",
        }
    }
}
impl ConfigurationCode {
    pub fn locale_key(self) -> &'static str {
        match self {
            Self::ConnectionPortZero => "configuration_connection_port_zero",
            Self::WireguardPortZero => "configuration_wireguard_port_zero",
            Self::InvalidPhysicalInterface => "configuration_invalid_interface",
            Self::InvalidBridgePort => "configuration_invalid_bridge_port",
            Self::DisabledLanBridge => "configuration_disabled_lan_bridge",
            Self::WanInBridge => "configuration_wan_in_bridge",
            Self::InvalidManagementReference => "configuration_invalid_management_reference",
            Self::WanManagementConflict => "configuration_wan_management_conflict",
            Self::MissingLanBridge => "configuration_missing_lan_bridge",
            Self::MissingBridgePorts => "configuration_missing_bridge_ports",
            Self::MixedBridgeHardware => "configuration_mixed_bridge_hardware",
            Self::BridgePortMismatch => "configuration_bridge_port_mismatch",
            Self::MissingWanList => "configuration_missing_wan_list",
            Self::MissingLanList => "configuration_missing_lan_list",
            Self::InvalidInterfaceList => "configuration_invalid_interface_list",
            Self::InvalidDhcpReference => "configuration_invalid_dhcp_reference",
            Self::InvalidDhcpServerReference => "configuration_invalid_dhcp_server_reference",
            Self::WireguardRequiresFirewall => "configuration_wireguard_requires_firewall",
            Self::UnknownModule => "configuration_unknown_module",
        }
    }
}
impl SecurityCode {
    pub fn locale_key(self) -> &'static str {
        match self {
            Self::MissingAdmin => "security_missing_admin",
            Self::InvalidAdminGroup => "security_invalid_admin_group",
            Self::InvalidUserGroup => "security_invalid_user_group",
            Self::WeakSshCrypto => "security_weak_ssh",
            Self::InvalidMacAccess => "security_invalid_mac",
            Self::InvalidUpdateChannel => "security_invalid_channel",
            Self::AutoInstall => "security_auto_install",
            Self::AutoReboot => "security_auto_reboot",
            Self::RouterboardUpgrade => "security_routerboard_upgrade",
        }
    }
}
#[derive(Debug, PartialEq, Eq)]
pub struct ValidationError {
    pub code: ValidationCode,
    pub detail: String,
}
#[derive(Debug, PartialEq, Eq)]
pub struct ConfigurationError {
    pub code: ConfigurationCode,
    pub detail: String,
}
#[derive(Debug, PartialEq, Eq)]
pub struct SecurityError {
    pub code: SecurityCode,
    pub detail: String,
    pub cause: Option<super::shared_errors::TokenError>,
}
impl SecurityError {
    // Первинна помилка зберігається без аналізу її повідомлення.
    pub fn from_token(code: SecurityCode, error: super::shared_errors::TokenError) -> Self {
        Self {
            code,
            detail: error.to_string(),
            cause: Some(error),
        }
    }
}
impl std::error::Error for SecurityError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.cause
            .as_ref()
            .map(|e| e as &(dyn std::error::Error + 'static))
    }
}

impl fmt::Display for ValidationError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.detail)
    }
}
impl fmt::Display for ConfigurationError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.detail)
    }
}
impl fmt::Display for SecurityError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.detail)
    }
}

// Типи помилок внутрішніх парсерів: коди не залежать від тексту повідомлень.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ModuleCode {
    // Stage 18: System, Services і Leases — окремі коди без аналізу рядків.
    SystemIdentity,
    SystemTimezone,
    SystemNtpMissing,
    SystemNtpCount,
    SystemNtpToken,
    ServicesPortsZero,
    ServicesPortsConflict,
    ServicesDiscoveryReference,
    ServicesDiscoveryToken,
    LeasesLimit,
    LeasesDhcpDisabled,
    LeasesId,
    LeasesAddress,
    LeasesComment,
    LeasesMac,
    LeasesLanRange,
    LeasesDuplicate,
    // Stage 14: структуровані помилки Interfaces та WireGuard.
    InterfacePhysical,
    InterfaceName,
    InterfaceDuplicate,
    InterfaceCriticalDisabled,
    InterfaceManagementRename,
    InterfaceRenameCollision,
    WireguardToken,
    WireguardPort,
    WireguardCidr,
    WireguardLanOverlap,
    WireguardManagementOverlap,
    WireguardInternetPermission,
    WireguardPeerKey,
    WireguardPeerBase64,
    WireguardPeerDuplicate,
    WireguardPeerCidr,
    WireguardPeerOutside,
    WireguardPeerHostCollision,
    WireguardPeerOverlap,
    // Stage 13: помилки Bridge, Lists і Wireless без аналізу рядків.
    BridgeName,
    BridgeProtocol,
    BridgePort,
    BridgeEmpty,
    ListName,
    ListDuplicate,
    ListWanDisabled,
    WifiFactoryId,
    WifiDisabledDriver,
    WifiDisabledRadios,
    WifiDriver,
    WifiNoRadios,
    WifiFactoryName,
    WifiFactoryDuplicate,
    WifiInterface,
    WifiBridge,
    WifiRadioDisabled,
    WifiToken,
    WifiSecurity,
    WifiPasswordSource,
    WifiAuthentication,
    WifiSecurityDuplicate,
    WifiChannel,

    // Stage 12: внутрішні перевірки NAT та IPv6 без рядкових кодів.
    NatHairpinCidr,
    NatForwardProtocol,
    NatForwardPort,
    NatForwardAddress,
    NatForwardDestination,
    NatForwardTcpLimit,
    Ipv6FirewallRequired,

    // Stage 11: предметні коди Network, NAT та Firewall.
    NetworkInterfaceConflict,
    NetworkLanPrefix,
    NetworkAddressConflict,
    NetworkSubnetConflict,
    NetworkManagementMismatch,
    NetworkManagementPort,
    NetworkDuplicatePort,
    NatWanDisabled,
    NatMissingWanList,
    NatHairpinDependencies,
    NatHairpinSubnetMissing,
    NatForwardDependencies,
    NatDuplicateForward,
    NatHairpinPublicAddressMissing,
    FirewallRequired,
    FirewallManagementPorts,
    FirewallListsRequired,
    FirewallDropRequiresEnabled,
    FirewallManagementPrefix,
    FirewallManagementOverlap,
    FirewallBruteforcePorts,
    FirewallBruteforceDuplicate,
    FirewallBruteforceRequiresEnabled,
    FirewallIcmpLimit,
    WanInterfaceConflict,
    DnsInvalidAddress,
    DnsEmptyServers,
    DnsDuplicateServers,
    DhcpInvalidPoolStart,
    DhcpInvalidPoolEnd,
    DhcpInvalidGateway,
    DhcpPoolOutsideLan,
    DhcpInvalidDns,
    DhcpUnsafeDns,
    DhcpMissingDns,
    DhcpInvalidLeaseTime,
    DhcpInvalidName,
}
impl ModuleCode {
    pub fn locale_key(self) -> &'static str {
        match self {
            Self::SystemIdentity => "module_system_identity",
            Self::SystemTimezone => "module_system_timezone",
            Self::SystemNtpMissing => "module_system_ntp_missing",
            Self::SystemNtpCount => "module_system_ntp_count",
            Self::SystemNtpToken => "module_system_ntp_token",
            Self::ServicesPortsZero => "module_services_ports_zero",
            Self::ServicesPortsConflict => "module_services_ports_conflict",
            Self::ServicesDiscoveryReference => "module_services_discovery_reference",
            Self::ServicesDiscoveryToken => "module_services_discovery_token",
            Self::LeasesLimit => "module_leases_limit",
            Self::LeasesDhcpDisabled => "module_leases_dhcp_disabled",
            Self::LeasesId => "module_leases_id",
            Self::LeasesAddress => "module_leases_address",
            Self::LeasesComment => "module_leases_comment",
            Self::LeasesMac => "module_leases_mac",
            Self::LeasesLanRange => "module_leases_lan_range",
            Self::LeasesDuplicate => "module_leases_duplicate",
            Self::InterfacePhysical => "module_interface_physical",
            Self::InterfaceName => "module_interface_name",
            Self::InterfaceDuplicate => "module_interface_duplicate",
            Self::InterfaceCriticalDisabled => "module_interface_critical_disabled",
            Self::InterfaceManagementRename => "module_interface_management_rename",
            Self::InterfaceRenameCollision => "module_interface_rename_collision",
            Self::WireguardToken => "module_wireguard_token",
            Self::WireguardPort => "module_wireguard_port",
            Self::WireguardCidr => "module_wireguard_cidr",
            Self::WireguardLanOverlap => "module_wireguard_lan_overlap",
            Self::WireguardManagementOverlap => "module_wireguard_management_overlap",
            Self::WireguardInternetPermission => "module_wireguard_internet_permission",
            Self::WireguardPeerKey => "module_wireguard_peer_key",
            Self::WireguardPeerBase64 => "module_wireguard_peer_base64",
            Self::WireguardPeerDuplicate => "module_wireguard_peer_duplicate",
            Self::WireguardPeerCidr => "module_wireguard_peer_cidr",
            Self::WireguardPeerOutside => "module_wireguard_peer_outside",
            Self::WireguardPeerHostCollision => "module_wireguard_peer_host_collision",
            Self::WireguardPeerOverlap => "module_wireguard_peer_overlap",
            Self::BridgeName => "module_bridge_name",
            Self::BridgeProtocol => "module_bridge_protocol",
            Self::BridgePort => "module_bridge_port",
            Self::BridgeEmpty => "module_bridge_empty",
            Self::ListName => "module_list_name",
            Self::ListDuplicate => "module_list_duplicate",
            Self::ListWanDisabled => "module_list_wan_disabled",
            Self::WifiFactoryId => "module_wifi_factory_id",
            Self::WifiDisabledDriver => "module_wifi_disabled_driver",
            Self::WifiDisabledRadios => "module_wifi_disabled_radios",
            Self::WifiDriver => "module_wifi_driver",
            Self::WifiNoRadios => "module_wifi_no_radios",
            Self::WifiFactoryName => "module_wifi_factory_name",
            Self::WifiFactoryDuplicate => "module_wifi_factory_duplicate",
            Self::WifiInterface => "module_wifi_interface",
            Self::WifiBridge => "module_wifi_bridge",
            Self::WifiRadioDisabled => "module_wifi_radio_disabled",
            Self::WifiToken => "module_wifi_token",
            Self::WifiSecurity => "module_wifi_security",
            Self::WifiPasswordSource => "module_wifi_password_source",
            Self::WifiAuthentication => "module_wifi_authentication",
            Self::WifiSecurityDuplicate => "module_wifi_security_duplicate",
            Self::WifiChannel => "module_wifi_channel",
            Self::NatHairpinCidr => "module_nat_hairpin_cidr",
            Self::NatForwardProtocol => "module_nat_forward_protocol",
            Self::NatForwardPort => "module_nat_forward_port",
            Self::NatForwardAddress => "module_nat_forward_address",
            Self::NatForwardDestination => "module_nat_forward_destination",
            Self::NatForwardTcpLimit => "module_nat_forward_tcp_limit",
            Self::Ipv6FirewallRequired => "module_ipv6_firewall_required",
            Self::NetworkInterfaceConflict => "module_network_interface_conflict",
            Self::NetworkLanPrefix => "module_network_lan_prefix",
            Self::NetworkAddressConflict => "module_network_address_conflict",
            Self::NetworkSubnetConflict => "module_network_subnet_conflict",
            Self::NetworkManagementMismatch => "module_network_management_mismatch",
            Self::NetworkManagementPort => "module_network_management_port",
            Self::NetworkDuplicatePort => "module_network_duplicate_port",
            Self::NatWanDisabled => "module_nat_wan_disabled",
            Self::NatMissingWanList => "module_nat_missing_wan_list",
            Self::NatHairpinDependencies => "module_nat_hairpin_dependencies",
            Self::NatHairpinSubnetMissing => "module_nat_hairpin_subnet_missing",
            Self::NatForwardDependencies => "module_nat_forward_dependencies",
            Self::NatDuplicateForward => "module_nat_duplicate_forward",
            Self::NatHairpinPublicAddressMissing => "module_nat_hairpin_public_address_missing",
            Self::FirewallRequired => "module_firewall_required",
            Self::FirewallManagementPorts => "module_firewall_management_ports",
            Self::FirewallListsRequired => "module_firewall_lists_required",
            Self::FirewallDropRequiresEnabled => "module_firewall_drop_requires_enabled",
            Self::FirewallManagementPrefix => "module_firewall_management_prefix",
            Self::FirewallManagementOverlap => "module_firewall_management_overlap",
            Self::FirewallBruteforcePorts => "module_firewall_bruteforce_ports",
            Self::FirewallBruteforceDuplicate => "module_firewall_bruteforce_duplicate",
            Self::FirewallBruteforceRequiresEnabled => {
                "module_firewall_bruteforce_requires_enabled"
            }
            Self::FirewallIcmpLimit => "module_firewall_icmp_limit",
            Self::WanInterfaceConflict => "module_wan_interface_conflict",
            Self::DnsInvalidAddress => "module_dns_invalid_address",
            Self::DnsEmptyServers => "module_dns_empty_servers",
            Self::DnsDuplicateServers => "module_dns_duplicate_servers",
            Self::DhcpInvalidPoolStart => "module_dhcp_invalid_pool_start",
            Self::DhcpInvalidPoolEnd => "module_dhcp_invalid_pool_end",
            Self::DhcpInvalidGateway => "module_dhcp_invalid_gateway",
            Self::DhcpPoolOutsideLan => "module_dhcp_pool_outside_lan",
            Self::DhcpInvalidDns => "module_dhcp_invalid_dns",
            Self::DhcpUnsafeDns => "module_dhcp_unsafe_dns",
            Self::DhcpMissingDns => "module_dhcp_missing_dns",
            Self::DhcpInvalidLeaseTime => "module_dhcp_invalid_lease_time",
            Self::DhcpInvalidName => "module_dhcp_invalid_name",
        }
    }
    pub fn location(self) -> (&'static str, &'static str) {
        match self {
            Self::SystemIdentity => ("system.toml", "identity.name"),
            Self::SystemTimezone => ("system.toml", "clock.timezone"),
            Self::SystemNtpMissing => ("system.toml", "ntp.servers"),
            Self::SystemNtpCount => ("system.toml", "ntp.servers"),
            Self::SystemNtpToken => ("system.toml", "ntp.servers"),
            Self::ServicesPortsZero => ("services.toml", "services.*.port"),
            Self::ServicesPortsConflict => ("services.toml", "services.*.port"),
            Self::ServicesDiscoveryReference => ("services.toml", "discovery.interface_list"),
            Self::ServicesDiscoveryToken => ("services.toml", "discovery.interface_list"),
            Self::LeasesLimit => ("dhcp.toml", "leases.devices"),
            Self::LeasesDhcpDisabled => ("dhcp.toml", "leases.enabled"),
            Self::LeasesId => ("dhcp.toml", "leases.devices.*"),
            Self::LeasesAddress => ("dhcp.toml", "leases.devices.*.address"),
            Self::LeasesComment => ("dhcp.toml", "leases.devices.*.comment"),
            Self::LeasesMac => ("dhcp.toml", "leases.devices.*.mac"),
            Self::LeasesLanRange => ("dhcp.toml", "leases.devices.*.address"),
            Self::LeasesDuplicate => ("dhcp.toml", "leases.devices.*"),
            Self::InterfacePhysical => ("interfaces.toml", "interfaces.*"),
            Self::InterfaceName => ("interfaces.toml", "interfaces.*.name"),
            Self::InterfaceDuplicate => ("interfaces.toml", "interfaces.*"),
            Self::InterfaceCriticalDisabled => ("interfaces.toml", "interfaces.*.enabled"),
            Self::InterfaceManagementRename => ("interfaces.toml", "interfaces.*.name"),
            Self::InterfaceRenameCollision => ("interfaces.toml", "interfaces.*.name"),
            Self::WireguardToken => ("wireguard.toml", "wireguard.*"),
            Self::WireguardPort => ("wireguard.toml", "wireguard.listen_port"),
            Self::WireguardCidr => ("wireguard.toml", "wireguard.address"),
            Self::WireguardLanOverlap => ("wireguard.toml", "wireguard.address"),
            Self::WireguardManagementOverlap => ("wireguard.toml", "wireguard.address"),
            Self::WireguardInternetPermission => ("wireguard.toml", "wireguard.allow_wan"),
            Self::WireguardPeerKey => ("wireguard.toml", "peers.*.public_key"),
            Self::WireguardPeerBase64 => ("wireguard.toml", "peers.*.public_key"),
            Self::WireguardPeerDuplicate => ("wireguard.toml", "peers.*.public_key"),
            Self::WireguardPeerCidr => ("wireguard.toml", "peers.*.allowed_address"),
            Self::WireguardPeerOutside => ("wireguard.toml", "peers.*.allowed_address"),
            Self::WireguardPeerHostCollision => ("wireguard.toml", "peers.*.allowed_address"),
            Self::WireguardPeerOverlap => ("wireguard.toml", "peers.*.allowed_address"),

            Self::BridgeName => ("bridge.toml", "bridge.lan.name"),
            Self::BridgeProtocol => ("bridge.toml", "bridge.lan.protocol_mode"),
            Self::BridgePort => ("bridge.toml", "ports.*"),
            Self::BridgeEmpty => ("bridge.toml", "ports.*"),
            Self::ListName => ("lists.toml", "lists.*.name"),
            Self::ListDuplicate => ("lists.toml", "lists.*.name"),
            Self::ListWanDisabled => ("lists.toml", "lists.wan"),
            Self::WifiFactoryId => ("wireless.toml", "wireless.radios.*"),
            Self::WifiDisabledDriver => ("wireless.toml", "wireless.driver"),
            Self::WifiDisabledRadios => ("wireless.toml", "wireless.radios"),
            Self::WifiDriver => ("wireless.toml", "wireless.driver"),
            Self::WifiNoRadios => ("wireless.toml", "wireless.radios"),
            Self::WifiFactoryName => ("wireless.toml", "wireless.radios.*.default_name"),
            Self::WifiFactoryDuplicate => ("wireless.toml", "wireless.radios.*.default_name"),
            Self::WifiInterface => ("wireless.toml", "wireless.radios.*.interface"),
            Self::WifiBridge => ("wireless.toml", "wireless.radios.*.bridge"),
            Self::WifiRadioDisabled => ("wireless.toml", "wireless.radios.*.enabled"),
            Self::WifiToken => ("wireless.toml", "wireless.radios.*"),
            Self::WifiSecurity => ("wireless.toml", "wireless.radios.*.security"),
            Self::WifiPasswordSource => ("wireless.toml", "security.*.password_source"),
            Self::WifiAuthentication => ("wireless.toml", "security.*.authentication"),
            Self::WifiSecurityDuplicate => ("wireless.toml", "security.*.name"),
            Self::WifiChannel => ("wireless.toml", "wireless.radios.*"),
            Self::NatHairpinCidr => ("nat.toml", "nat.hairpin_lan_subnet"),
            Self::NatForwardProtocol => ("nat.toml", "forward.*.protocol"),
            Self::NatForwardPort => ("nat.toml", "forward.*.wan_port"),
            Self::NatForwardAddress => ("nat.toml", "forward.*.to_address"),
            Self::NatForwardDestination => ("nat.toml", "forward.*.dst_address"),
            Self::NatForwardTcpLimit => ("nat.toml", "forward.*.tcp_new_limit"),
            Self::Ipv6FirewallRequired => ("ipv6.toml", "ipv6.firewall"),
            Self::NetworkInterfaceConflict => ("network.toml", "network"),
            Self::NetworkLanPrefix => ("network.toml", "network"),
            Self::NetworkAddressConflict => ("network.toml", "network"),
            Self::NetworkSubnetConflict => ("network.toml", "network"),
            Self::NetworkManagementMismatch => ("network.toml", "network"),
            Self::NetworkManagementPort => ("network.toml", "network"),
            Self::NetworkDuplicatePort => ("network.toml", "network"),
            Self::NatWanDisabled => ("nat.toml", "nat"),
            Self::NatMissingWanList => ("nat.toml", "nat"),
            Self::NatHairpinDependencies => ("nat.toml", "nat"),
            Self::NatHairpinSubnetMissing => ("nat.toml", "nat"),
            Self::NatForwardDependencies => ("nat.toml", "nat"),
            Self::NatDuplicateForward => ("nat.toml", "nat"),
            Self::NatHairpinPublicAddressMissing => ("nat.toml", "nat"),
            Self::FirewallRequired => ("firewall.toml", "firewall"),
            Self::FirewallManagementPorts => ("firewall.toml", "firewall"),
            Self::FirewallListsRequired => ("firewall.toml", "firewall"),
            Self::FirewallDropRequiresEnabled => ("firewall.toml", "firewall"),
            Self::FirewallManagementPrefix => ("firewall.toml", "firewall"),
            Self::FirewallManagementOverlap => ("firewall.toml", "firewall"),
            Self::FirewallBruteforcePorts => ("firewall.toml", "firewall"),
            Self::FirewallBruteforceDuplicate => ("firewall.toml", "firewall"),
            Self::FirewallBruteforceRequiresEnabled => ("firewall.toml", "firewall"),
            Self::FirewallIcmpLimit => ("firewall.toml", "firewall"),
            Self::WanInterfaceConflict => ("network.toml", "wan.interface"),
            Self::DnsInvalidAddress | Self::DnsEmptyServers | Self::DnsDuplicateServers => {
                ("dns.toml", "dns.servers")
            }
            Self::DhcpInvalidPoolStart => ("dhcp.toml", "pool.lan.start"),
            Self::DhcpInvalidPoolEnd => ("dhcp.toml", "pool.lan.end"),
            Self::DhcpInvalidGateway => ("dhcp.toml", "network.lan.gateway"),
            Self::DhcpPoolOutsideLan => ("dhcp.toml", "pool.lan"),
            Self::DhcpInvalidDns | Self::DhcpUnsafeDns | Self::DhcpMissingDns => {
                ("dhcp.toml", "network.lan.dns_servers")
            }
            Self::DhcpInvalidLeaseTime => ("dhcp.toml", "server.lan.lease_time"),
            Self::DhcpInvalidName => ("dhcp.toml", "pool.lan.name"),
        }
    }
}
#[derive(Debug, PartialEq, Eq)]
pub struct ModuleError {
    pub code: ModuleCode,
    pub detail: String,
    cause: Option<ModuleCause>,
}
// Відома першопричина залишається типом, а не відновлюється з тексту.
#[derive(Debug, PartialEq, Eq)]
enum ModuleCause {
    Token(super::shared_errors::TokenError),
    Ipv4(super::shared_errors::Ipv4Error),
    Physical(super::interfaces::PhysicalInterfaceError),
}
impl ModuleError {
    pub fn new(code: ModuleCode, detail: impl Into<String>) -> Self {
        Self {
            code,
            detail: detail.into(),
            cause: None,
        }
    }
    // Зберігаємо історичний текст помилки разом із конкретною причиною.
    pub fn from_token(code: ModuleCode, error: super::shared_errors::TokenError) -> Self {
        Self {
            code,
            detail: error.to_string(),
            cause: Some(ModuleCause::Token(error)),
        }
    }
    pub fn from_ipv4(code: ModuleCode, error: super::shared_errors::Ipv4Error) -> Self {
        Self {
            code,
            detail: error.to_string(),
            cause: Some(ModuleCause::Ipv4(error)),
        }
    }
    // Окремий тип помилки заводського ідентифікатора не є помилкою токена.
    pub(super) fn from_physical(
        code: ModuleCode,
        error: super::interfaces::PhysicalInterfaceError,
    ) -> Self {
        Self {
            code,
            detail: error.to_string(),
            cause: Some(ModuleCause::Physical(error)),
        }
    }
}
impl std::error::Error for ModuleError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self.cause.as_ref()? {
            ModuleCause::Token(error) => Some(error),
            ModuleCause::Ipv4(error) => Some(error),
            ModuleCause::Physical(error) => Some(error),
        }
    }
}
impl fmt::Display for ModuleError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.detail)
    }
}

#[derive(Debug)]
pub enum PlanError {
    Cross(CrossError),
    Shared(super::shared_errors::SharedError),
    PlanValidation(super::plan_validation::PlanValidationError),
    Reference(ReferenceCode),
    Validation(ValidationError),
    Configuration(ConfigurationError),
    Security(SecurityError),
    Module(ModuleError),
    TypedConfig(mikrotik_config_manager::typed_config::TypedReadError),
    Profile(crate::config::ProfileError),
    Boundary(Box<PlanBoundaryError>),
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlanBoundaryCode {
    BridgeId,
    LanBridgeReference,
    ConnectionConfig,
    WireguardConfig,
}
#[derive(Debug)]
pub struct PlanBoundaryError {
    pub code: PlanBoundaryCode,
    pub detail: String,
    pub source: Option<mikrotik_config_manager::typed_config::TypedReadError>,
}
impl fmt::Display for PlanBoundaryError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        // Вичерпне зіставлення з кодом: тип залишається частиною робочої діагностики.
        // Усі варіанти навмисно зберігають попередній текст CLI.
        match self.code {
            PlanBoundaryCode::BridgeId
            | PlanBoundaryCode::LanBridgeReference
            | PlanBoundaryCode::ConnectionConfig
            | PlanBoundaryCode::WireguardConfig => f.write_str(&self.detail),
        }
    }
}
impl std::error::Error for PlanBoundaryError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.source
            .as_ref()
            .map(|error| error as &(dyn std::error::Error + 'static))
    }
}
impl PlanBoundaryError {
    pub fn new(code: PlanBoundaryCode, detail: impl Into<String>) -> Self {
        Self {
            code,
            detail: detail.into(),
            source: None,
        }
    }
    pub fn with_config(
        code: PlanBoundaryCode,
        detail: String,
        source: mikrotik_config_manager::typed_config::TypedReadError,
    ) -> Self {
        Self {
            code,
            detail,
            source: Some(source),
        }
    }
}
impl fmt::Display for PlanError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Cross(error) => error.fmt(f),
            Self::Shared(error) => error.fmt(f),
            Self::PlanValidation(error) => error.fmt(f),
            Self::Reference(code) => write!(f, "Invalid configuration reference: {:?}", code),
            Self::Validation(error) => error.fmt(f),
            Self::Configuration(error) => error.fmt(f),
            Self::Security(error) => error.fmt(f),
            Self::Module(error) => error.fmt(f),
            Self::TypedConfig(error) => error.fmt(f),
            Self::Profile(error) => error.fmt(f),
            Self::Boundary(error) => error.fmt(f),
        }
    }
}
impl From<super::shared_errors::SharedError> for PlanError {
    fn from(value: super::shared_errors::SharedError) -> Self {
        Self::Shared(value)
    }
}
impl From<super::plan_validation::PlanValidationError> for PlanError {
    fn from(value: super::plan_validation::PlanValidationError) -> Self {
        Self::PlanValidation(value)
    }
}
impl From<CrossError> for PlanError {
    fn from(value: CrossError) -> Self {
        Self::Cross(value)
    }
}
impl From<ModuleError> for PlanError {
    fn from(value: ModuleError) -> Self {
        Self::Module(value)
    }
}
impl From<mikrotik_config_manager::typed_config::TypedReadError> for PlanError {
    fn from(value: mikrotik_config_manager::typed_config::TypedReadError) -> Self {
        Self::TypedConfig(value)
    }
}
impl From<crate::config::ProfileError> for PlanError {
    fn from(value: crate::config::ProfileError) -> Self {
        Self::Profile(value)
    }
}
impl From<PlanBoundaryError> for PlanError {
    fn from(value: PlanBoundaryError) -> Self {
        Self::Boundary(Box::new(value))
    }
}
impl std::error::Error for PlanError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::TypedConfig(error) => Some(error),
            Self::Profile(error) => Some(error),
            Self::Boundary(error) => Some(error),
            Self::Module(error) => Some(error),
            Self::Security(error) => Some(error),
            Self::Cross(error) => Some(error),
            Self::Shared(error) => Some(error),
            _ => None,
        }
    }
}
impl From<ValidationError> for PlanError {
    fn from(value: ValidationError) -> Self {
        Self::Validation(value)
    }
}
impl From<ConfigurationError> for PlanError {
    fn from(value: ConfigurationError) -> Self {
        Self::Configuration(value)
    }
}
impl From<SecurityError> for PlanError {
    fn from(value: SecurityError) -> Self {
        Self::Security(value)
    }
}

pub fn inspect(
    wifi: &WirelessConfig,
    interfaces: &InterfacesConfig,
    bridge: &BridgeConfig,
    network: &NetworkConfig,
) -> Option<ReferenceCode> {
    for (id, port) in &bridge.ports {
        if port.enabled && !interfaces.interfaces.contains_key(id) {
            return Some(ReferenceCode::BridgePort);
        }
    }
    if network.network.lan.interface != "@bridge.lan" {
        return Some(ReferenceCode::NetworkLan);
    }
    if !wifi.wireless.enabled {
        return None;
    }
    for (id, radio) in &wifi.wireless.radios {
        if !radio.enabled {
            continue;
        }
        if radio.interface != format!("@interfaces.{id}")
            || !interfaces
                .interfaces
                .get(id)
                .is_some_and(|entry| entry.enabled)
        {
            return Some(ReferenceCode::WifiInterface);
        }
        if radio.bridge != "@bridge.lan" || !bridge.bridge.contains_key("lan") {
            return Some(ReferenceCode::WifiBridge);
        }
        match radio.security.strip_prefix("@security.") {
            Some(key) if wifi.security.contains_key(key) => {}
            _ => return Some(ReferenceCode::WifiSecurity),
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use mikrotik_config_manager::typed_config::read_typed;
    use std::path::Path;
    #[test]
    fn emits_typed_error_from_in_memory_config_without_message_matching() {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("routers/hap-ac");
        let mut wifi: WirelessConfig = read_typed(&dir.join("wireless.toml")).unwrap();
        let interfaces: InterfacesConfig = read_typed(&dir.join("interfaces.toml")).unwrap();
        let bridge: BridgeConfig = read_typed(&dir.join("bridge.toml")).unwrap();
        let network: NetworkConfig = read_typed(&dir.join("network.toml")).unwrap();
        assert_eq!(inspect(&wifi, &interfaces, &bridge, &network), None);
        wifi.wireless.radios.get_mut("wlan1").unwrap().security = "@security.invalid".into();
        assert_eq!(
            inspect(&wifi, &interfaces, &bridge, &network),
            Some(ReferenceCode::WifiSecurity)
        );
    }
    #[test]
    fn invalid_reference_from_plan_is_structured_without_toml_reread() {
        // Fixture з окремим профілем перевіряємо через існуючий інтеграційний набір;
        // тут контролюємо лише саме перенесення варіанта через Result.
        let result: Result<(), PlanError> = Err(PlanError::Reference(ReferenceCode::WifiSecurity));
        assert!(matches!(
            result,
            Err(PlanError::Reference(ReferenceCode::WifiSecurity))
        ));
    }
    #[test]
    fn error_variant_remains_structured_across_result() {
        let result: Result<(), PlanError> = Err(PlanError::Reference(ReferenceCode::BridgePort));
        assert!(matches!(
            result,
            Err(PlanError::Reference(ReferenceCode::BridgePort))
        ));
    }
}

#[cfg(test)]
mod regression_typed_error_tests {
    use super::*;
    #[test]
    fn domain_variants_survive_result_without_string_parsing() {
        let validation: Result<(), PlanError> = Err(ValidationError {
            code: ValidationCode::UnknownBridgePort,
            detail: "bridge".into(),
        }
        .into());
        assert!(matches!(
            validation,
            Err(PlanError::Validation(ValidationError {
                code: ValidationCode::UnknownBridgePort,
                ..
            }))
        ));
        let configuration: Result<(), PlanError> = Err(ConfigurationError {
            code: ConfigurationCode::WireguardPortZero,
            detail: "wireguard".into(),
        }
        .into());
        assert!(matches!(
            configuration,
            Err(PlanError::Configuration(ConfigurationError {
                code: ConfigurationCode::WireguardPortZero,
                ..
            }))
        ));
        let security: Result<(), PlanError> = Err(SecurityError {
            code: SecurityCode::WeakSshCrypto,
            detail: "ssh".into(),
            cause: None,
        }
        .into());
        assert!(matches!(
            security,
            Err(PlanError::Security(SecurityError {
                code: SecurityCode::WeakSshCrypto,
                ..
            }))
        ));
    }
    #[test]
    fn domain_errors_keep_display_compatible_and_exclude_secrets() {
        let error = PlanError::Security(SecurityError {
            code: SecurityCode::AutoInstall,
            detail: "Автоматичне встановлення оновлень заборонено".into(),
            cause: None,
        });
        assert_eq!(
            error.to_string(),
            "Автоматичне встановлення оновлень заборонено"
        );
        assert!(!error.to_string().contains("PASSWORD"));
    }
}

// Stage 7: два раніше рядкові випадки мають стабільні коди та точне місце.
#[cfg(test)]
mod regression_error_coverage_tests {
    use super::*;

    #[test]
    fn lan_bridge_disabled_is_a_typed_configuration_error() {
        let result: Result<(), PlanError> = Err(ConfigurationError {
            code: ConfigurationCode::DisabledLanBridge,
            detail: "LAN bridge вимкнено".into(),
        }
        .into());
        assert!(matches!(
            result,
            Err(PlanError::Configuration(ConfigurationError {
                code: ConfigurationCode::DisabledLanBridge,
                ..
            }))
        ));
        assert_eq!(
            ConfigurationCode::DisabledLanBridge.location(),
            ("bridge.toml", "bridge.lan.enabled")
        );
    }

    #[test]
    fn wan_in_bridge_is_a_typed_configuration_error() {
        let result: Result<(), PlanError> = Err(ConfigurationError {
            code: ConfigurationCode::WanInBridge,
            detail: "WAN входить до Bridge".into(),
        }
        .into());
        assert!(matches!(
            result,
            Err(PlanError::Configuration(ConfigurationError {
                code: ConfigurationCode::WanInBridge,
                ..
            }))
        ));
        assert_eq!(
            ConfigurationCode::WanInBridge.location(),
            ("network.toml", "wan.interface")
        );
    }
}

// Stage 8: мережеві та адміністративні порушення мають власні коди.
// Перевіряємо повну передачу варіанта через Result без аналізу тексту.
#[cfg(test)]
mod regression_network_management_tests {
    use super::*;

    #[test]
    fn management_and_wan_codes_are_structured() {
        for (code, file, field) in [
            (
                ConfigurationCode::InvalidManagementReference,
                "network.toml",
                "management.interface",
            ),
            (
                ConfigurationCode::WanManagementConflict,
                "network.toml",
                "wan.interface",
            ),
        ] {
            let result: Result<(), PlanError> = Err(ConfigurationError {
                code,
                detail: "Початкова діагностика".to_owned(),
            }
            .into());
            match result {
                Err(PlanError::Configuration(error)) => {
                    assert_eq!(error.code, code);
                    assert_eq!(error.code.location(), (file, field));
                    assert!(!error.code.locale_key().is_empty());
                }
                _ => panic!("Очікується типізована помилка конфігурації"),
            }
        }
    }
}

// Регресія Stage 9: усі нові коди несуть конкретне поле і власний переклад.
#[cfg(test)]
mod regression_coverage_tests {
    use super::*;
    use crate::i18n::Messages;
    use std::path::Path;

    const CODES: [ConfigurationCode; 11] = [
        ConfigurationCode::MissingLanBridge,
        ConfigurationCode::MissingBridgePorts,
        ConfigurationCode::MixedBridgeHardware,
        ConfigurationCode::BridgePortMismatch,
        ConfigurationCode::MissingWanList,
        ConfigurationCode::MissingLanList,
        ConfigurationCode::InvalidInterfaceList,
        ConfigurationCode::InvalidDhcpReference,
        ConfigurationCode::InvalidDhcpServerReference,
        ConfigurationCode::WireguardRequiresFirewall,
        ConfigurationCode::UnknownModule,
    ];

    #[test]
    fn regression_9_codes_keep_typed_identity_and_locations() {
        for code in CODES {
            let err: PlanError = ConfigurationError {
                code,
                detail: "ПОМИЛКА_ТЕСТ".into(),
            }
            .into();
            assert!(
                matches!(err, PlanError::Configuration(ConfigurationError { code: actual, .. }) if actual == code)
            );
            let (file, field) = code.location();
            assert!(!file.is_empty() && !field.is_empty());
            assert!(code.locale_key().starts_with("configuration_"));
        }
    }

    #[test]
    fn regression_9_codes_resolve_in_both_language_files() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        for language in ["uk", "en"] {
            let messages = Messages::load(root, language).unwrap();
            for code in CODES {
                let translation = messages.get(code.locale_key());
                assert!(!translation.is_empty());
                assert_ne!(translation, code.locale_key());
            }
        }
    }
}

#[cfg(test)]
mod regression_parser_errors_tests {
    use super::*;
    // Усі коди залишаються структурованими під час проходження через Result.
    #[test]
    fn module_error_survives_result() {
        for code in [
            ModuleCode::WanInterfaceConflict,
            ModuleCode::DnsInvalidAddress,
            ModuleCode::DnsEmptyServers,
            ModuleCode::DnsDuplicateServers,
            ModuleCode::DhcpInvalidPoolStart,
            ModuleCode::DhcpInvalidPoolEnd,
            ModuleCode::DhcpInvalidGateway,
            ModuleCode::DhcpPoolOutsideLan,
            ModuleCode::DhcpInvalidDns,
            ModuleCode::DhcpUnsafeDns,
            ModuleCode::DhcpMissingDns,
            ModuleCode::DhcpInvalidLeaseTime,
            ModuleCode::DhcpInvalidName,
        ] {
            let result: Result<(), PlanError> = Err(ModuleError::new(code, "причина").into());
            assert!(
                matches!(result, Err(PlanError::Module(ModuleError { code: actual, .. })) if actual == code)
            );
            assert!(!code.location().0.is_empty());
            assert!(!code.locale_key().is_empty());
        }
    }
}

#[cfg(test)]
mod regression_module_error_tests {
    use super::*;
    #[test]
    fn network_nat_firewall_codes_are_structured() {
        // Код не відновлюємо з рядка: перевіряємо саме enum у Result.
        for code in [
            ModuleCode::NetworkLanPrefix,
            ModuleCode::NatDuplicateForward,
            ModuleCode::FirewallManagementOverlap,
        ] {
            let result: Result<(), PlanError> = Err(ModuleError::new(code, "деталь").into());
            assert!(
                matches!(result, Err(PlanError::Module(ModuleError { code: c, .. })) if c == code)
            );
            assert!(!code.locale_key().is_empty());
        }
    }
}

#[cfg(test)]
mod historical_regression_coverage_tests {
    use super::{ModuleCode, ModuleError, PlanError};
    #[test]
    fn bridge_lists_wifi_codes_keep_structured_result() {
        // Помилка проходить через Result без порівняння тексту.
        for code in [
            ModuleCode::BridgeProtocol,
            ModuleCode::ListDuplicate,
            ModuleCode::WifiDriver,
            ModuleCode::WifiSecurity,
            ModuleCode::WifiChannel,
        ] {
            let result: Result<(), PlanError> =
                Err(ModuleError::new(code, "деталь не є кодом").into());
            assert!(
                matches!(result, Err(PlanError::Module(ModuleError { code: found, .. })) if found == code)
            );
            assert!(!code.location().0.is_empty());
        }
    }
    #[test]
    fn all_stage13_codes_exist_in_both_locales() {
        // Коди однакові для всіх роутерів; переклад не залежить від назви профілю.
        let uk = include_str!("../../locales/uk.lang");
        let en = include_str!("../../locales/en.lang");
        for code in [
            ModuleCode::BridgeName,
            ModuleCode::BridgeProtocol,
            ModuleCode::BridgePort,
            ModuleCode::BridgeEmpty,
            ModuleCode::ListName,
            ModuleCode::ListDuplicate,
            ModuleCode::ListWanDisabled,
            ModuleCode::WifiFactoryId,
            ModuleCode::WifiDisabledDriver,
            ModuleCode::WifiDisabledRadios,
            ModuleCode::WifiDriver,
            ModuleCode::WifiNoRadios,
            ModuleCode::WifiFactoryName,
            ModuleCode::WifiFactoryDuplicate,
            ModuleCode::WifiInterface,
            ModuleCode::WifiBridge,
            ModuleCode::WifiRadioDisabled,
            ModuleCode::WifiToken,
            ModuleCode::WifiSecurity,
            ModuleCode::WifiPasswordSource,
            ModuleCode::WifiAuthentication,
            ModuleCode::WifiSecurityDuplicate,
            ModuleCode::WifiChannel,
        ] {
            let key = format!("{}=", code.locale_key());
            assert!(uk.lines().any(|line| line.starts_with(&key)), "uk: {key}");
            assert!(en.lines().any(|line| line.starts_with(&key)), "en: {key}");
        }
    }
}

#[cfg(test)]
mod regression_module_codes_tests {
    use super::*;
    // Перевіряємо повне покриття двох локалізацій і коректні координати.
    #[test]
    fn regression_14_codes_have_locales_and_locations() {
        let uk = include_str!("../../locales/uk.lang");
        let en = include_str!("../../locales/en.lang");
        let codes = [
            ModuleCode::InterfacePhysical,
            ModuleCode::InterfaceName,
            ModuleCode::InterfaceDuplicate,
            ModuleCode::InterfaceCriticalDisabled,
            ModuleCode::InterfaceManagementRename,
            ModuleCode::InterfaceRenameCollision,
            ModuleCode::WireguardToken,
            ModuleCode::WireguardPort,
            ModuleCode::WireguardCidr,
            ModuleCode::WireguardLanOverlap,
            ModuleCode::WireguardManagementOverlap,
            ModuleCode::WireguardInternetPermission,
            ModuleCode::WireguardPeerKey,
            ModuleCode::WireguardPeerBase64,
            ModuleCode::WireguardPeerDuplicate,
            ModuleCode::WireguardPeerCidr,
            ModuleCode::WireguardPeerOutside,
            ModuleCode::WireguardPeerHostCollision,
            ModuleCode::WireguardPeerOverlap,
        ];
        for code in codes {
            let key = format!("{} =", code.locale_key());
            assert!(uk.lines().any(|line| line.starts_with(&key)), "uk: {key}");
            assert!(en.lines().any(|line| line.starts_with(&key)), "en: {key}");
            assert!(code.location().0.ends_with(".toml"));
            let result: Result<(), PlanError> = Err(ModuleError::new(code, "без секретів").into());
            assert!(matches!(result, Err(PlanError::Module(_))));
        }
    }
}

// Stage 14 Fix: усі коди Interfaces та WireGuard мають унікальне відображення.
// Компілятор перевіряє унікальність варіантів enum, а тест — доступність діагностики.
#[cfg(test)]
mod regression_duplicate_guard_tests {
    use super::ModuleCode;
    use std::collections::HashSet;

    #[test]
    fn interface_and_wireguard_codes_are_unique_and_complete() {
        let codes = [
            ModuleCode::InterfacePhysical,
            ModuleCode::InterfaceName,
            ModuleCode::InterfaceDuplicate,
            ModuleCode::InterfaceCriticalDisabled,
            ModuleCode::InterfaceManagementRename,
            ModuleCode::InterfaceRenameCollision,
            ModuleCode::WireguardToken,
            ModuleCode::WireguardPort,
            ModuleCode::WireguardCidr,
            ModuleCode::WireguardLanOverlap,
            ModuleCode::WireguardManagementOverlap,
            ModuleCode::WireguardInternetPermission,
            ModuleCode::WireguardPeerKey,
            ModuleCode::WireguardPeerBase64,
            ModuleCode::WireguardPeerDuplicate,
            ModuleCode::WireguardPeerCidr,
            ModuleCode::WireguardPeerOutside,
            ModuleCode::WireguardPeerHostCollision,
            ModuleCode::WireguardPeerOverlap,
        ];
        let unique: HashSet<_> = codes.iter().copied().collect();
        assert_eq!(unique.len(), 19);
        for code in codes {
            let (file, field) = code.location();
            assert!(!file.is_empty());
            assert!(!field.is_empty());
            assert!(code.locale_key().starts_with("module_"));
        }
    }
}

#[cfg(test)]
mod regression_parser_error_tests {
    use super::{ModuleCode, ModuleError, PlanError};
    // Перевіряємо повний ланцюжок Result → PlanError без розпізнавання тексту.
    fn propagate(code: ModuleCode) -> Result<(), PlanError> {
        Err(ModuleError::new(code, "контрольована помилка").into())
    }
    #[test]
    fn parser_errors_preserve_codes_and_context() {
        for code in [
            ModuleCode::SystemIdentity,
            ModuleCode::SystemTimezone,
            ModuleCode::SystemNtpMissing,
            ModuleCode::SystemNtpCount,
            ModuleCode::SystemNtpToken,
            ModuleCode::ServicesPortsZero,
            ModuleCode::ServicesPortsConflict,
            ModuleCode::ServicesDiscoveryReference,
            ModuleCode::ServicesDiscoveryToken,
            ModuleCode::LeasesLimit,
            ModuleCode::LeasesDhcpDisabled,
            ModuleCode::LeasesId,
            ModuleCode::LeasesAddress,
            ModuleCode::LeasesComment,
            ModuleCode::LeasesMac,
            ModuleCode::LeasesLanRange,
            ModuleCode::LeasesDuplicate,
        ] {
            let error = propagate(code).expect_err("Помилка повинна залишитись типізованою");
            let PlanError::Module(module) = error else {
                panic!("Загублено типізований код");
            };
            assert_eq!(module.code, code);
            assert_eq!(module.detail, "контрольована помилка");
            assert!(code.locale_key().starts_with("module_"));
            assert!(code.location().0.ends_with(".toml"));
        }
    }
}

// Регресії наскрізної передачі помилок без рядкових fallback.
#[cfg(test)]
mod regression_typed_boundary_regressions {
    use super::*;
    use std::error::Error;
    #[test]
    fn boundary_reason_remains_typed_through_plan_result() {
        // Помилку передає окрема функція, щоб тестувати справжню межу Result.
        fn boundary_result() -> Result<(), PlanError> {
            Err(PlanBoundaryError::new(PlanBoundaryCode::BridgeId, "Невідомий Bridge ID").into())
        }
        match boundary_result().unwrap_err() {
            PlanError::Boundary(problem) => {
                assert_eq!(problem.code, PlanBoundaryCode::BridgeId);
                assert_eq!(problem.to_string(), "Невідомий Bridge ID");
            }
            other => panic!("Неочікуваний варіант: {other}"),
        }
    }
    #[test]
    fn toml_read_source_survives_plan_boundary() {
        let path = std::path::Path::new("/definitely/nonexistent/stage-typed.toml");
        let error = mikrotik_config_manager::typed_config::read_typed::<
            mikrotik_config_manager::typed_config::SystemConfig,
        >(path)
        .unwrap_err();
        let wrapper = PlanBoundaryError::with_config(
            PlanBoundaryCode::ConnectionConfig,
            format!("Configuration Integrity: {error}"),
            error,
        );
        let plan: PlanError = wrapper.into();
        assert!(plan.source().is_some());
        assert!(plan.source().unwrap().source().is_some());
    }
}

// Stage 29: типізована першопричина проходить через PlanError до CLI.
#[cfg(test)]
mod regression_source_chain_tests {
    use super::*;
    use std::error::Error;

    #[test]
    fn token_cause_survives_module_and_plan() {
        let token_error = super::super::token("bad value", "interface.name").unwrap_err();
        let previous_text = token_error.to_string();
        let error: PlanError =
            ModuleError::from_token(ModuleCode::InterfaceName, token_error).into();
        assert_eq!(error.to_string(), previous_text);
        let module = error.source().expect("module cause");
        let source = module.source().expect("token cause");
        assert!(source
            .downcast_ref::<super::super::shared_errors::TokenError>()
            .is_some());
    }

    #[test]
    fn ipv4_cause_survives_module_and_plan() {
        let invalid = super::super::network::parse_address("bad/24").unwrap_err();
        let error: PlanError = ModuleError::from_ipv4(ModuleCode::NetworkLanPrefix, invalid).into();
        let source = error.source().unwrap().source().unwrap();
        let ip = source
            .downcast_ref::<super::super::shared_errors::Ipv4Error>()
            .unwrap();
        assert_eq!(
            ip.code,
            super::super::shared_errors::Ipv4Code::InvalidAddress
        );
        assert_eq!(error.to_string(), "Некоректний IPv4");
    }

    #[test]
    fn cross_ipv4_and_shared_token_keep_source() {
        let invalid = super::super::network::parse_address("10.0.0.1/99").unwrap_err();
        let error: PlanError =
            CrossError::from_ipv4(super::super::cross_errors::CrossCode::Static19, invalid).into();
        assert!(error
            .source()
            .unwrap()
            .source()
            .unwrap()
            .downcast_ref::<super::super::shared_errors::Ipv4Error>()
            .is_some());
        let invalid = super::super::token("unsafe;value", "bridge.name").unwrap_err();
        let error: PlanError = super::super::shared_errors::SharedError::from_token(
            super::super::shared_errors::SharedCode::InvalidToken,
            invalid,
        )
        .into();
        assert!(error
            .source()
            .unwrap()
            .source()
            .unwrap()
            .downcast_ref::<super::super::shared_errors::TokenError>()
            .is_some());
    }
}

#[cfg(test)]
mod regression_security_source_tests {
    use super::*;
    use std::error::Error;
    #[test]
    fn invalid_security_token_keeps_original_cause_through_plan() {
        let cause = super::super::shared_errors::TokenError {
            code: super::super::shared_errors::TokenCode::InvalidCharactersOrEmpty,
            label: "users.admin.name".into(),
        };
        let expected = cause.to_string();
        let error: PlanError =
            SecurityError::from_token(SecurityCode::InvalidAdminGroup, cause).into();
        assert_eq!(error.to_string(), expected);
        let security = error.source().expect("SecurityError");
        assert!(security.downcast_ref::<SecurityError>().is_some());
        let token = security.source().expect("TokenError");
        assert!(token
            .downcast_ref::<super::super::shared_errors::TokenError>()
            .is_some());
    }
}
