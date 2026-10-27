use super::lists::Lists;
use super::network::{parse_address, Network};
use super::reference_error::{ModuleCode, ModuleError};
use super::token;
use super::wan::Wan;
use mikrotik_config_manager::typed_config::WireguardConfig;
use std::collections::HashSet;
use std::net::Ipv4Addr;

// Перетин CIDR: порівнюємо мережі за коротшим префіксом.
// Це коректно також для часткового накладання /24 із /25.
fn overlaps(a: (Ipv4Addr, u8), b: (Ipv4Addr, u8)) -> bool {
    super::ipv4_math::overlaps(a, b)
}

// Інтерфейс та правила ізольовані від виконання: лише PLAN.
// Ключів приватного доступу не створюємо і не зберігаємо.
pub struct Wireguard {
    commands: Vec<String>,
    enabled: bool,
    name: String,
    port: u16,
    allow_wan: bool,
    allow_lan: bool,
    allow_ssh: bool,
    allow_winbox: bool,
    allow_internet: bool,
    vpn_network: String,
}
impl Wireguard {
    pub fn parse(
        config: &WireguardConfig,
        network: &Network,
        _wan: &Wan,
        _lists: &Lists,
    ) -> Result<Self, ModuleError> {
        let general = &config.wireguard;
        let enabled = general.enabled;
        let blank = || Self {
            commands: vec!["# WIREGUARD: вимкнено; конфігурація не застосовується".into()],
            enabled: false,
            name: String::new(),
            port: 0,
            allow_wan: false,
            allow_lan: false,
            allow_ssh: false,
            allow_winbox: false,
            allow_internet: false,
            vpn_network: String::new(),
        };
        if !enabled {
            return Ok(blank());
        }
        let name = general.name.clone();
        token(&name, "wireguard.name")
            .map_err(|e| ModuleError::from_token(ModuleCode::WireguardToken, e))?;
        let port = general.listen_port;
        if port == 0 {
            return Err(ModuleError::new(
                ModuleCode::WireguardPort,
                "WireGuard: порт 0 заборонений",
            ));
        }
        let address = general.address.as_str();
        let cidr = parse_address(address)
            .map_err(|e| ModuleError::from_ipv4(ModuleCode::WireguardCidr, e))?;
        if !(1..=30).contains(&cidr.1) {
            return Err(ModuleError::new(
                ModuleCode::WireguardCidr,
                "WireGuard: некоректна VPN-підмережа",
            ));
        }
        let lan_cidr = (network.lan_ip, network.prefix);
        let mgmt_cidr = parse_address(&network.management_address)
            .map_err(|e| ModuleError::from_ipv4(ModuleCode::WireguardManagementOverlap, e))?;
        if overlaps(cidr, lan_cidr) {
            return Err(ModuleError::new(
                ModuleCode::WireguardLanOverlap,
                "WireGuard: VPN перетинається з LAN",
            ));
        }
        if overlaps(cidr, mgmt_cidr) {
            return Err(ModuleError::new(
                ModuleCode::WireguardManagementOverlap,
                "WireGuard: VPN перетинається з Management",
            ));
        }
        let mask = u32::MAX << (32 - cidr.1);
        let vpn_network = format!("{}/{}", Ipv4Addr::from(u32::from(cidr.0) & mask), cidr.1);
        // Політика доступу задається явно, а не виводиться з факту увімкнення VPN.
        let allow_wan = general.allow_wan;
        let allow_lan = general.allow_lan;
        let allow_ssh = general.allow_ssh;
        let allow_winbox = general.allow_winbox;
        let allow_internet = general.allow_internet;
        if allow_internet && !allow_wan {
            return Err(ModuleError::new(
                ModuleCode::WireguardInternetPermission,
                "WireGuard: доступ до Інтернету потребує allow_wan=true",
            ));
        }
        // BTreeMap підтримує стабільний порядок peer ID.
        let mut out = vec![
            "# WIREGUARD: лише план; ключі та секрети не показуються".into(),
            format!(
                "/interface wireguard add name={name} listen-port={port} comment=mcm-wireguard"
            ),
            format!(
                "/ip address add address={address} interface={name} comment=mcm-wireguard-address"
            ),
        ];
        let mut peer_keys = HashSet::new();
        let mut allowed_networks: Vec<(Ipv4Addr, u8)> = Vec::new();
        for (id, peer) in &config.peers {
            token(id, "wireguard.peer_id")
                .map_err(|e| ModuleError::from_token(ModuleCode::WireguardToken, e))?;
            if !peer.enabled {
                continue;
            }
            let public_key = peer.public_key.as_str();
            // Ключ WireGuard = 32 байти, закодовані у canonical Base64 з одним '='.
            if public_key.len() != 44
                || !public_key.ends_with('=')
                || !public_key[..43]
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'+' || b == b'/')
            {
                return Err(ModuleError::new(
                    ModuleCode::WireguardPeerKey,
                    format!("WireGuard peer {id}: некоректний public_key"),
                ));
            }
            // Для 32-байтового значення останній значущий Base64 символ має 2 молодші біти = 0.
            let last = public_key.as_bytes()[42];
            let digit = match last {
                b'A'..=b'Z' => last - b'A',
                b'a'..=b'z' => last - b'a' + 26,
                b'0'..=b'9' => last - b'0' + 52,
                b'+' => 62,
                b'/' => 63,
                _ => {
                    return Err(ModuleError::new(
                        ModuleCode::WireguardPeerBase64,
                        format!("WireGuard peer {id}: некоректний Base64"),
                    ))
                }
            };
            if digit & 3 != 0 {
                return Err(ModuleError::new(
                    ModuleCode::WireguardPeerBase64,
                    format!("WireGuard peer {id}: некоректне завершення Base64"),
                ));
            }
            if !peer_keys.insert(public_key.to_owned()) {
                return Err(ModuleError::new(
                    ModuleCode::WireguardPeerDuplicate,
                    "WireGuard: повторений public_key",
                ));
            }
            let allowed = peer.allowed_address.as_str();
            let peer_cidr = parse_address(allowed)
                .map_err(|e| ModuleError::from_ipv4(ModuleCode::WireguardPeerCidr, e))?;
            if peer_cidr.1 != 32 {
                return Err(ModuleError::new(
                    ModuleCode::WireguardPeerCidr,
                    format!("WireGuard peer {id}: для домашнього road-warrior потрібен /32"),
                ));
            }
            if !overlaps(peer_cidr, cidr) {
                return Err(ModuleError::new(
                    ModuleCode::WireguardPeerOutside,
                    format!("WireGuard peer {id}: IP поза VPN-підмережею"),
                ));
            }
            if peer_cidr.0 == cidr.0 {
                return Err(ModuleError::new(
                    ModuleCode::WireguardPeerHostCollision,
                    format!("WireGuard peer {id}: IP збігається з інтерфейсом VPN"),
                ));
            }
            if allowed_networks
                .iter()
                .any(|&other| overlaps(peer_cidr, other))
            {
                return Err(ModuleError::new(
                    ModuleCode::WireguardPeerOverlap,
                    "WireGuard: перетин allowed_address між peers",
                ));
            }
            allowed_networks.push(peer_cidr);
            let description = peer.comment.as_deref().unwrap_or(id.as_str());
            token(description, "wireguard.peer.comment")
                .map_err(|e| ModuleError::from_token(ModuleCode::WireguardToken, e))?;
            out.push(format!("/interface wireguard peers add interface={name} public-key=\"{public_key}\" allowed-address={allowed} comment={description}"));
        }
        Ok(Self {
            commands: out,
            enabled,
            name,
            port,
            allow_wan,
            allow_lan,
            allow_ssh,
            allow_winbox,
            allow_internet,
            vpn_network,
        })
    }
    pub fn commands(&self) -> Vec<String> {
        self.commands.clone()
    }
    pub fn enabled(&self) -> bool {
        self.enabled
    }
    pub fn input_rules(&self, wan_list: &str) -> Vec<String> {
        if !self.enabled || !self.allow_wan {
            return Vec::new();
        }
        vec![format!("/ip firewall filter add chain=input action=accept in-interface-list={wan_list} protocol=udp dst-port={} comment=mcm-input-wireguard-udp",self.port)]
    }
    // Кожен адміністративний протокол має власний перемикач доступу з VPN.
    // Вони ніколи не дозволяють доступ напряму з фізичного WAN.
    pub fn management_rules(
        &self,
        ssh_port: u16,
        winbox_port: u16,
        ssh_enabled: bool,
        winbox_enabled: bool,
    ) -> Vec<String> {
        if !self.enabled {
            return Vec::new();
        }
        let mut rules = Vec::new();
        if self.allow_ssh && ssh_enabled {
            rules.push(format!("/ip firewall filter add chain=input action=accept in-interface={} src-address={} protocol=tcp dst-port={} comment=mcm-input-wireguard-ssh", self.name, self.vpn_network, ssh_port));
        }
        if self.allow_winbox && winbox_enabled {
            rules.push(format!("/ip firewall filter add chain=input action=accept in-interface={} src-address={} protocol=tcp dst-port={} comment=mcm-input-wireguard-winbox", self.name, self.vpn_network, winbox_port));
        }
        rules
    }
    pub fn forward_rules(&self, lan_list: &str, wan_list: &str) -> Vec<String> {
        if !self.enabled {
            return Vec::new();
        }
        let mut rules = Vec::new();
        if self.allow_lan {
            rules.push(format!("/ip firewall filter add chain=forward action=accept in-interface={} src-address={} out-interface-list={lan_list} comment=mcm-forward-wireguard-lan",self.name,self.vpn_network));
        }
        if self.allow_internet {
            rules.push(format!("/ip firewall filter add chain=forward action=accept in-interface={} src-address={} out-interface-list={wan_list} comment=mcm-forward-wireguard-wan",self.name,self.vpn_network));
        }
        rules
    }
    pub fn nat_rules(&self, wan_list: &str) -> Vec<String> {
        if !self.enabled || !self.allow_internet {
            return Vec::new();
        }
        vec![format!("/ip firewall nat add chain=srcnat action=masquerade src-address={} out-interface-list={wan_list} comment=mcm-wireguard-wan-masquerade",self.vpn_network)]
    }
}

#[cfg(test)]
mod tests {
    use super::overlaps;
    use std::net::Ipv4Addr;
    fn ip(s: &str) -> Ipv4Addr {
        s.parse().unwrap()
    }
    #[test]
    fn partial_cidr_overlap() {
        assert!(overlaps((ip("10.77.0.1"), 24), (ip("10.77.0.128"), 25)));
    }
    #[test]
    fn disjoint_networks() {
        assert!(!overlaps((ip("10.77.0.1"), 24), (ip("10.78.0.1"), 24)));
    }
}

#[cfg(test)]
mod typed_wireguard_tests {
    use mikrotik_config_manager::typed_config::WireguardConfig;

    #[test]
    fn profiles_deserialize_and_keep_vpn_disabled() {
        for name in ["test", "hap-ac"] {
            let content =
                std::fs::read_to_string(format!("routers/{name}/wireguard.toml")).unwrap();
            let value: WireguardConfig = toml::from_str(&content).unwrap();
            assert!(!value.wireguard.enabled);
            assert_eq!(value.wireguard.listen_port, 51820);
            assert!(value.peers.is_empty());
        }
    }

    #[test]
    fn rejects_wrong_types_unknown_fields_and_peer_fields() {
        let text = std::fs::read_to_string("routers/test/wireguard.toml").unwrap();
        assert!(toml::from_str::<WireguardConfig>(
            &text.replace("enabled = false", "enabled = \"false\"")
        )
        .is_err());
        assert!(toml::from_str::<WireguardConfig>(&format!("{text}\n[peers.bad]\nenabled = true\npublic_key = 22\nallowed_address = \"10.77.0.2/32\"\n")).is_err());
        assert!(
            toml::from_str::<WireguardConfig>(&format!("{text}\nunknown_field = true\n")).is_err()
        );
    }
}
