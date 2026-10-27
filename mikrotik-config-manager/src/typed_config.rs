//! Типізовані схеми об'єднаних TOML конфігурацій.
//!
//! Цей модуль — перший ізольований крок міграції. Поки що планувальник
//! використовує старий інтерфейс: переносити його без Cargo-перевірок небезпечно.
use serde::Deserialize;
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

// Глобальні налаштування CLI: сувора схема без рядкового адаптера.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ManagerConfig {
    pub manager: ManagerSettings,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ManagerSettings {
    pub language: String,
    pub default_router: String,
    pub color: String,
}

// Строга декларація SSH-з’єднання, спільна для плану та RouterOS-клієнта.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConnectionConfig {
    pub connection: ConnectionSettings,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConnectionSettings {
    pub host: String,
    pub port: u16,
    pub user: String,
    pub identity_file: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NetworkConfig {
    pub network: NetworkSection,
    pub management: ManagementConfig,
    pub wan: WanConfig,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NetworkSection {
    pub lan: LanAddress,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LanAddress {
    pub interface: String,
    pub address: String,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ManagementConfig {
    pub interface: String,
    pub address: String,
    pub on_lan: bool,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WanConfig {
    pub enabled: bool,
    pub interface: String,
    pub add_default_route: bool,
    pub use_peer_dns: bool,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DhcpConfig {
    pub pool: PoolSection,
    pub server: ServerSection,
    pub network: DhcpNetworkSection,
    pub leases: LeaseSection,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PoolSection {
    pub lan: PoolConfig,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PoolConfig {
    pub name: String,
    pub start: String,
    pub end: String,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ServerSection {
    pub lan: DhcpServerConfig,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DhcpServerConfig {
    pub name: String,
    pub enabled: bool,
    pub interface: String,
    pub pool: String,
    pub lease_time: String,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DhcpNetworkSection {
    pub lan: DhcpLanConfig,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DhcpLanConfig {
    pub gateway: String,
    pub dns_servers: Vec<String>,
}
#[derive(Debug, Deserialize)]
pub struct LeaseSection {
    pub enabled: bool,
    pub server: String,
    #[serde(flatten)]
    pub devices: BTreeMap<String, StaticLease>,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StaticLease {
    pub address: String,
    pub mac: String,
    pub comment: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SystemConfig {
    pub identity: IdentityConfig,
    pub clock: ClockConfig,
    pub ntp: NtpConfig,
    pub users: BTreeMap<String, UserConfig>,
    pub ssh: SshConfig,
    pub mac_access: MacAccessConfig,
    pub updates: UpdatesConfig,
    pub routerboard: RouterboardConfig,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct IdentityConfig {
    pub name: String,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ClockConfig {
    pub timezone: String,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NtpConfig {
    pub enabled: bool,
    pub servers: Vec<String>,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UserConfig {
    pub name: String,
    pub group: String,
    pub managed: bool,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SshConfig {
    pub strong_crypto: bool,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MacAccessConfig {
    pub interface_list: String,
    pub mac_server: bool,
    pub mac_winbox: bool,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UpdatesConfig {
    pub channel: String,
    pub auto_install: bool,
    pub auto_reboot: bool,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RouterboardConfig {
    pub upgrade: bool,
}

// Конфігурація Wi-Fi та несекретних профілів WPA2-PSK.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WirelessConfig {
    pub wireless: WirelessSection,
    #[serde(default)]
    pub security: BTreeMap<String, WifiSecurityProfile>,
}
#[derive(Debug, Deserialize)]
// Динамічні radio ID обробляє flatten; їхню допустимість перевіряє Wireless::parse.
// deny_unknown_fields тут несумісний із flatten і відхиляє wlan1/wlan2.
pub struct WirelessSection {
    pub enabled: bool,
    pub driver: String,
    #[serde(flatten)]
    pub radios: BTreeMap<String, WifiRadio>,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WifiRadio {
    pub enabled: bool,
    // Явне заводське ім’я інтерфейсу RouterOS (не кінцеве name).
    // Необов’язкове, щоб зберегти чинні декларації профілів.
    #[serde(default)]
    pub default_name: Option<String>,
    pub interface: String,
    pub ssid: String,
    pub band: String,
    pub channel_width: String,
    pub frequency: String,
    pub country: String,
    pub security: String,
    pub bridge: String,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WifiSecurityProfile {
    pub name: String,
    pub authentication: String,
    pub password_source: String,
}

// Типізований WireGuard: суворі поля ресурсу та peer.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WireguardConfig {
    pub wireguard: WireguardSettings,
    #[serde(default)]
    pub peers: BTreeMap<String, WireguardPeer>,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WireguardSettings {
    pub enabled: bool,
    pub name: String,
    pub listen_port: u16,
    pub address: String,
    pub allow_wan: bool,
    pub allow_lan: bool,
    pub allow_ssh: bool,
    pub allow_winbox: bool,
    pub allow_internet: bool,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WireguardPeer {
    pub enabled: bool,
    pub public_key: String,
    pub allowed_address: String,
    pub comment: Option<String>,
}

// Схеми мережевих модулів. Ключі ресурсів залишаються декларативними ID.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct InterfacesConfig {
    pub interfaces: BTreeMap<String, InterfaceResource>,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct InterfaceResource {
    pub name: String,
    pub enabled: bool,
    pub comment: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BridgeConfig {
    pub bridge: BTreeMap<String, BridgeResource>,
    pub ports: BTreeMap<String, BridgePort>,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BridgeResource {
    pub name: String,
    pub enabled: bool,
    pub protocol_mode: String,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BridgePort {
    pub bridge: String,
    pub enabled: bool,
    pub hw: bool,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ListsConfig {
    pub lists: BTreeMap<String, ListResource>,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ListResource {
    pub name: String,
    pub enabled: bool,
    pub members: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DnsConfig {
    pub dns: DnsSettings,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DnsSettings {
    pub enabled: bool,
    pub servers: Vec<String>,
    pub allow_remote_requests: bool,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NatConfig {
    pub nat: NatSettings,
    #[serde(default)]
    pub forward: BTreeMap<String, ForwardSettings>,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(deny_unknown_fields)]
pub struct ForwardSettings {
    pub protocol: String,
    pub wan_port: u16,
    pub to_address: String,
    pub to_port: u16,
    #[serde(default)]
    pub tcp_new_limit: Option<u16>,
    #[serde(default)]
    pub dst_address: Option<String>,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NatSettings {
    pub enabled: bool,
    pub masquerade: bool,
    #[serde(default)]
    pub hairpin_enabled: bool,
    #[serde(default)]
    pub hairpin_lan_subnet: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FirewallConfig {
    pub firewall: FirewallSettings,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FirewallSettings {
    pub enabled: bool,
    pub allow_icmp: bool,
    pub allow_lan_dhcp: bool,
    pub input_default_drop: bool,
    pub forward_default_drop: bool,
    pub lan_to_wan: bool,
    pub fasttrack: bool,
    pub drop_new_wan: bool,
    pub brute_force_enabled: bool,
    pub brute_force_ports: String,
    pub icmp_limit_per_second: i64,
}

// Типізована конфігурація IPv6. Невідомі поля та рядкові bool відхиляються.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Ipv6Config {
    pub ipv6: Ipv6Settings,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Ipv6Settings {
    pub enabled: bool,
    pub firewall: bool,
}

// Типізовані служби керування. Невідомі поля та неправильні типи заборонені.
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ServicesConfig {
    pub services: ServiceEntries,
    pub discovery: DiscoverySettings,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ServiceEntries {
    pub ssh: ManagedService,
    pub winbox: ManagedService,
    pub telnet: DisabledService,
    pub ftp: DisabledService,
    pub www: DisabledService,
    #[serde(rename = "www-ssl")]
    pub www_ssl: DisabledService,
    pub api: DisabledService,
    #[serde(rename = "api-ssl")]
    pub api_ssl: DisabledService,
    #[serde(rename = "reverse-proxy")]
    pub reverse_proxy: DisabledService,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ManagedService {
    pub enabled: bool,
    pub port: u16,
    pub limit_to_lan: bool,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DisabledService {
    pub enabled: bool,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DiscoverySettings {
    pub interface_list: String,
}

// Єдине оформлення помилок конфігурації: профіль, файл, поле та позиція.
// Не додаємо до діагностики значення полів: вони можуть містити конфіденційні дані.
pub fn diagnostic_location(path: &Path) -> String {
    let file = path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("<невідомий файл>");
    let profile = path
        .parent()
        .and_then(|p| p.file_name())
        .and_then(|s| s.to_str());
    let is_router = path
        .parent()
        .and_then(|p| p.parent())
        .and_then(|p| p.file_name())
        .and_then(|s| s.to_str())
        == Some("routers");
    if is_router {
        format!("Профіль '{}', файл '{}':", profile.unwrap_or("?"), file)
    } else {
        format!("Файл '{}':", path.display())
    }
}

fn quoted_field(message: &str) -> Option<&str> {
    for marker in ["missing field `", "unknown field `", "duplicate field `"] {
        if let Some(start) = message.find(marker) {
            return message[start + marker.len()..].split('`').next();
        }
    }
    None
}

pub fn format_toml_error(path: &Path, text: &str, err: &toml::de::Error) -> String {
    let mut context = diagnostic_location(path);
    let message = err.message();
    let span = err.span();
    let field = quoted_field(message).or_else(|| {
        // Для помилки типу беремо тільки назву ключа з проблемного рядка.
        let start = span.as_ref()?.start.min(text.len());
        let line = text[..start].rsplit('\n').next()?;
        let key = line.split_once('=')?.0.trim();
        if !key.is_empty()
            && key
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        {
            Some(key)
        } else {
            None
        }
    });
    if let Some(field) = field {
        context.push_str(&format!(" поле '{}';", field));
    }
    if let Some(span) = span {
        let prefix = &text[..span.start.min(text.len())];
        let line = prefix.bytes().filter(|&b| b == b'\n').count() + 1;
        let column = prefix
            .rsplit('\n')
            .next()
            .map_or(1, |v| v.chars().count() + 1);
        context.push_str(&format!(" рядок {line}, колонка {column};"));
    }
    format!("{context} {message}")
}

// Типізована помилка читання TOML зі збереженням оригінальної причини.
#[derive(Debug)]
pub enum TypedReadError {
    Io {
        detail: String,
        source: std::io::Error,
    },
    Toml {
        detail: String,
        source: toml::de::Error,
    },
}
impl std::fmt::Display for TypedReadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io { detail, .. } | Self::Toml { detail, .. } => f.write_str(detail),
        }
    }
}
impl std::error::Error for TypedReadError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io { source, .. } => Some(source),
            Self::Toml { source, .. } => Some(source),
        }
    }
}

pub fn read_typed<T: serde::de::DeserializeOwned>(path: &Path) -> Result<T, TypedReadError> {
    let text = fs::read_to_string(path).map_err(|source| TypedReadError::Io {
        detail: format!("{} {source}", diagnostic_location(path)),
        source,
    })?;
    toml::from_str(&text).map_err(|source| TypedReadError::Toml {
        detail: format_toml_error(path, &text, &source),
        source,
    })
}

#[cfg(test)]
mod diagnostic_tests {
    use super::*;

    #[test]
    fn missing_field_includes_profile_file_and_field_without_values() {
        let path = Path::new("/project/routers/home-main/connection.toml");
        let value = "[connection]\nhost = \"private.example\"\nport = 22\nuser = \"admin\"\n";
        let error = toml::from_str::<ConnectionConfig>(value).unwrap_err();
        let output = format_toml_error(path, value, &error);
        assert!(output.contains("home-main"), "{output}");
        assert!(output.contains("connection.toml"), "{output}");
        assert!(output.contains("identity_file"), "{output}");
        assert!(!output.contains("private.example"), "{output}");
    }

    // Регресія: діагностика не показує значень полів із конфігурації.
    #[test]
    fn stage3_diagnostic_keeps_profile_and_hides_secret_values() {
        let path = Path::new("/project/routers/private-router/connection.toml");
        let secret = "PRIVATE_STAGE3_TOKEN_VALUE";
        let value = format!(
            "[connection]\nhost = \"{secret}\"\nport = \"invalid\"\nuser = \"admin\"\nidentity_file = \"key\"\n"
        );
        let error = toml::from_str::<ConnectionConfig>(&value).unwrap_err();
        let output = format_toml_error(path, &value, &error);
        assert!(output.contains("private-router"));
        assert!(output.contains("connection.toml"));
        assert!(!output.contains(secret));
    }

    #[test]
    fn invalid_type_and_syntax_have_profile_and_location() {
        let path = Path::new("/project/routers/guest/connection.toml");
        for value in [
            "[connection]\nhost = \"host\"\nport = \"bad\"\nuser = \"admin\"\nidentity_file = \"key\"\n",
            "[connection\n",
        ] {
            let error = toml::from_str::<ConnectionConfig>(value).unwrap_err();
            let output = format_toml_error(path, value, &error);
            assert!(output.contains("guest") && output.contains("connection.toml"), "{output}");
            assert!(output.contains("рядок"), "{output}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn profiles_deserialize_independently_without_fixed_values() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        for profile in ["test", "hap-ac"] {
            let dir = root.join("routers").join(profile);
            let n: NetworkConfig = read_typed(&dir.join("network.toml")).unwrap();
            let d: DhcpConfig = read_typed(&dir.join("dhcp.toml")).unwrap();
            let s: SystemConfig = read_typed(&dir.join("system.toml")).unwrap();
            // Будь-які значення та незалежні налаштування профілів припустимі,
            // якщо вони коректно десеріалізуються у строгі типи.
            let _: NetworkConfig = n;
            let _: DhcpConfig = d;
            let _: SystemConfig = s;
        }
    }

    #[test]
    fn merged_typed_sections_reject_invalid_values() {
        // Некоректний bool у Network не може стати рядковим значенням.
        let network = r#"[network.lan]
interface = "@bridge.lan"
address = "192.168.88.1/24"
[management]
interface = "@bridge.lan"
address = "192.168.88.1/24"
on_lan = 1
[wan]
enabled = true
interface = "@interfaces.ether1"
add_default_route = true
use_peer_dns = false
"#;
        assert!(toml::from_str::<NetworkConfig>(network).is_err());
        // Поле DNS DHCP мусить бути масивом, а не рядком.
        let dhcp = r#"[pool.lan]
name = "pool"
start = "192.168.88.100"
end = "192.168.88.200"
[server.lan]
name = "dhcp"
enabled = true
interface = "@bridge.lan"
pool = "@pool.lan"
lease_time = "12h"
[network.lan]
gateway = "192.168.88.1"
dns_servers = "192.168.88.1"
[leases]
enabled = false
server = "@server.lan"
"#;
        assert!(toml::from_str::<DhcpConfig>(dhcp).is_err());
        // NTP приймає лише bool та масив адрес.
        let system = r#"[identity]
name = "router"
[clock]
timezone = "Europe/Kyiv"
[ntp]
enabled = "true"
servers = ["pool.ntp.org"]
"#;
        assert!(toml::from_str::<SystemConfig>(system).is_err());
    }

    #[test]
    fn network_modules_deserialize_both_profiles() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        for profile in ["test", "hap-ac"] {
            let dir = root.join("routers").join(profile);
            let interfaces: InterfacesConfig = read_typed(&dir.join("interfaces.toml")).unwrap();
            let bridge: BridgeConfig = read_typed(&dir.join("bridge.toml")).unwrap();
            let lists: ListsConfig = read_typed(&dir.join("lists.toml")).unwrap();
            let dns: DnsConfig = read_typed(&dir.join("dns.toml")).unwrap();
            let nat: NatConfig = read_typed(&dir.join("nat.toml")).unwrap();
            let firewall: FirewallConfig = read_typed(&dir.join("firewall.toml")).unwrap();
            assert!(interfaces.interfaces.contains_key("ether1"));
            assert!(bridge.bridge.contains_key("lan"));
            assert!(bridge.ports.contains_key("ether2"));
            assert_eq!(lists.lists.len(), 2);
            assert!(dns.dns.enabled);
            assert!(nat.nat.masquerade);
            assert!(nat.forward.is_empty());
            assert!(firewall.firewall.input_default_drop);
        }
    }

    #[test]
    fn network_modules_reject_unknown_fields_and_wrong_types() {
        let bad_dns =
            "[dns]\nenabled = true\nservers = \"1.1.1.1\"\nallow_remote_requests = true\n";
        assert!(toml::from_str::<DnsConfig>(bad_dns).is_err());
        let bad_interface =
            "[interfaces.ether1]\nname = \"WAN\"\nenabled = \"true\"\ncomment = \"test\"\n";
        assert!(toml::from_str::<InterfacesConfig>(bad_interface).is_err());
        let bad_nat = "[nat]\nenabled = true\nmasquerade = true\nunknown = true\n";
        assert!(toml::from_str::<NatConfig>(bad_nat).is_err());
        let bad_forward_type = "[nat]\nenabled = true\nmasquerade = true\n[forward.web]\nprotocol = \"tcp\"\nwan_port = \"8080\"\nto_address = \"192.168.88.100\"\nto_port = 80\n";
        assert!(toml::from_str::<NatConfig>(bad_forward_type).is_err());
        let bad_forward_unknown = "[nat]\nenabled = true\nmasquerade = true\n[forward.web]\nprotocol = \"tcp\"\nwan_port = 8080\nto_address = \"192.168.88.100\"\nto_port = 80\nunknown = true\n";
        assert!(toml::from_str::<NatConfig>(bad_forward_unknown).is_err());
        let bad_bridge = "[bridge.lan]\nname = \"lan\"\nenabled = true\nprotocol_mode = \"rstp\"\n[ports.ether2]\nbridge = \"@bridge.lan\"\nenabled = true\nhw = \"true\"\n";
        assert!(toml::from_str::<BridgeConfig>(bad_bridge).is_err());
    }

    #[test]
    fn typed_deserialization_rejects_wrong_types_and_unknown_fields() {
        let mut bad = r#"[network.lan]
interface = "@bridge.lan"
address = "192.168.88.1/24"
[management]
interface = "@bridge.lan"
address = "192.168.88.1/24"
on_lan = "true"
[wan]
enabled = true
interface = "@interfaces.ether1"
add_default_route = true
use_peer_dns = false
"#
        .to_owned();
        assert!(toml::from_str::<NetworkConfig>(&bad).is_err());
        bad = bad.replace("on_lan = \"true\"", "on_lan = true");
        bad.push_str("unexpected = 123\n");
        assert!(toml::from_str::<NetworkConfig>(&bad).is_err());
    }
    #[test]
    fn merged_wan_leases_security_have_strict_types() {
        for router in ["test", "hap-ac"] {
            let base = Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("routers")
                .join(router);
            let network: NetworkConfig = read_typed(&base.join("network.toml")).unwrap();
            let dhcp: DhcpConfig = read_typed(&base.join("dhcp.toml")).unwrap();
            let system: SystemConfig = read_typed(&base.join("system.toml")).unwrap();
            assert!(network.wan.interface.starts_with('@'));
            assert_eq!(dhcp.leases.server, "@server.lan");
            assert!(system.users.contains_key("admin"));
            assert!(system.ssh.strong_crypto);
        }
    }

    #[test]
    fn typed_wan_lease_and_security_reject_wrong_fields() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("routers/test");
        let n = fs::read_to_string(root.join("network.toml")).unwrap();
        let d = fs::read_to_string(root.join("dhcp.toml")).unwrap();
        let s = fs::read_to_string(root.join("system.toml")).unwrap();
        assert!(toml::from_str::<NetworkConfig>(
            &n.replace("use_peer_dns = false", "use_peer_dns = \"false\"")
        )
        .is_err());
        assert!(toml::from_str::<DhcpConfig>(
            &d.replace("server = \"@server.lan\"", "server = true")
        )
        .is_err());
        assert!(toml::from_str::<SystemConfig>(
            &s.replace("strong_crypto = true", "strong_crypto = 1")
        )
        .is_err());
    }
}

// Регресія: обидві першопричини доступні без аналізу тексту.
#[cfg(test)]
mod typed_read_source_tests {
    use super::*;
    use std::error::Error;
    #[test]
    fn missing_file_retains_io_source() {
        let path = std::path::Path::new("/nonexistent-mcm-typed-read/config.toml");
        let error = read_typed::<ManagerConfig>(path).unwrap_err();
        assert!(matches!(error, TypedReadError::Io { .. }));
        assert!(error.source().is_some());
    }
    #[test]
    fn invalid_toml_retains_deserializer_source() {
        let dir = std::env::temp_dir();
        let file = dir.join(format!(
            "mcm-stage21-typed-{}-{}.toml",
            std::process::id(),
            "invalid"
        ));
        std::fs::write(&file, "[manager\nlanguage = 4").unwrap();
        let error = read_typed::<ManagerConfig>(&file).unwrap_err();
        std::fs::remove_file(&file).unwrap();
        assert!(matches!(error, TypedReadError::Toml { .. }));
        assert!(error.source().is_some());
    }
}
