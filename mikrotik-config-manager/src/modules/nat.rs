use super::reference_error::{ModuleCode, ModuleError};
use super::{lists::Lists, wan::Wan};
use mikrotik_config_manager::typed_config::{ForwardSettings, NatConfig};

pub struct Nat {
    enabled: bool,
    masquerade: bool,
    wan_list: String,
    lan_list: String,
    hairpin_enabled: bool,
    hairpin_lan_subnet: Option<String>,
    forwards: Vec<Forward>,
}
// Декларативне правило DNAT та відповідного дозволу Forward.
#[derive(Clone)]
pub struct Forward {
    pub id: String,
    pub protocol: String,
    pub wan_port: u16,
    pub to_address: String,
    pub to_port: u16,
    pub tcp_limit: Option<u16>,
    pub dst_address: Option<String>,
    pub hairpin: bool,
}
// Валідатори NAT зберігають старі умови перевірки та тексти повідомлень.
// Тип помилки створюється в місці виникнення, без розбору її тексту.
fn validate_subnet(raw: &str) -> Result<String, ModuleError> {
    let (address, prefix) = raw.split_once('/').ok_or_else(|| {
        ModuleError::new(
            ModuleCode::NatHairpinCidr,
            "Hairpin: очікується LAN CIDR (наприклад 192.168.88.0/24)",
        )
    })?;
    let ip = address.parse::<std::net::Ipv4Addr>().map_err(|_| {
        ModuleError::new(ModuleCode::NatHairpinCidr, "Hairpin: некоректна LAN адреса")
    })?;
    let bits = prefix.parse::<u8>().map_err(|_| {
        ModuleError::new(ModuleCode::NatHairpinCidr, "Hairpin: некоректний префікс")
    })?;
    if !(1..=30).contains(&bits) || ip.is_unspecified() || ip.is_multicast() || ip.is_loopback() {
        return Err(ModuleError::new(
            ModuleCode::NatHairpinCidr,
            "Hairpin: непридатна LAN підмережа",
        ));
    }
    if super::network::subnet(ip, bits) != u32::from(ip) {
        return Err(ModuleError::new(
            ModuleCode::NatHairpinCidr,
            "Hairpin: вкажіть адресу мережі, а не хоста",
        ));
    }
    Ok(format!("{ip}/{bits}"))
}
impl Forward {
    fn from_settings(id: &str, settings: &ForwardSettings) -> Result<Self, ModuleError> {
        let protocol = settings.protocol.clone();
        if protocol != "tcp" && protocol != "udp" {
            return Err(ModuleError::new(
                ModuleCode::NatForwardProtocol,
                format!("forward.{id}: протокол має бути tcp або udp"),
            ));
        }
        let wan_port = settings.wan_port;
        let to_port = settings.to_port;
        if wan_port == 0 || to_port == 0 {
            return Err(ModuleError::new(
                ModuleCode::NatForwardPort,
                "Порт Forward не може бути нульовим",
            ));
        }
        let addr = settings
            .to_address
            .parse::<std::net::Ipv4Addr>()
            .map_err(|_| {
                ModuleError::new(
                    ModuleCode::NatForwardAddress,
                    format!("forward.{id}: некоректна IPv4-адреса"),
                )
            })?;
        if addr.is_unspecified()
            || addr.is_multicast()
            || addr.is_loopback()
            || addr.is_broadcast()
            || addr.is_link_local()
        {
            return Err(ModuleError::new(
                ModuleCode::NatForwardAddress,
                format!("forward.{id}: непридатна адреса призначення"),
            ));
        }
        let dst_address = settings
            .dst_address
            .as_deref()
            .map(str::trim)
            .filter(|v| !v.is_empty())
            .map(|raw| {
                let addr = raw.parse::<std::net::Ipv4Addr>().map_err(|_| {
                    ModuleError::new(
                        ModuleCode::NatForwardDestination,
                        format!("forward.{id}: некоректний dst_address"),
                    )
                })?;
                if addr.is_unspecified()
                    || addr.is_multicast()
                    || addr.is_loopback()
                    || addr.is_broadcast()
                    || addr.is_link_local()
                {
                    return Err(ModuleError::new(
                        ModuleCode::NatForwardDestination,
                        format!("forward.{id}: недопустимий dst_address"),
                    ));
                }
                Ok::<_, ModuleError>(addr.to_string())
            })
            .transpose()?;
        let tcp_limit = settings.tcp_new_limit;
        if let Some(limit) = tcp_limit {
            if protocol != "tcp" || limit == 0 || limit > 1000 {
                return Err(ModuleError::new(
                    ModuleCode::NatForwardTcpLimit,
                    format!("forward.{id}: ліміт 1..1000 дозволено лише для TCP"),
                ));
            }
        }
        Ok(Self {
            id: id.into(),
            protocol,
            wan_port,
            to_address: addr.to_string(),
            to_port,
            tcp_limit,
            dst_address,
            hairpin: false,
        })
    }
}
impl Nat {
    pub fn parse(config: &NatConfig, wan: &Wan, lists: &Lists) -> Result<Self, ModuleError> {
        let enabled = config.nat.enabled;
        let masquerade = config.nat.masquerade;
        // NAT без WAN не має корисного змісту у звичайній домашній схемі.
        if enabled && !wan.enabled {
            return Err(ModuleError::new(
                ModuleCode::NatWanDisabled,
                "NAT увімкнено, але WAN DHCP Client вимкнений",
            ));
        }
        if enabled && masquerade && !lists.enabled {
            return Err(ModuleError::new(
                ModuleCode::NatMissingWanList,
                "NAT потребує WAN Interface List",
            ));
        }
        let hairpin_enabled = config.nat.hairpin_enabled;
        let hairpin_lan_subnet = config
            .nat
            .hairpin_lan_subnet
            .as_deref()
            .map(str::trim)
            .filter(|v| !v.is_empty())
            .map(validate_subnet)
            .transpose()?;
        if hairpin_enabled && (!enabled || !lists.enabled || !masquerade) {
            return Err(ModuleError::new(
                ModuleCode::NatHairpinDependencies,
                "Hairpin NAT потребує NAT, masquerade та Interface Lists",
            ));
        }
        if hairpin_enabled && hairpin_lan_subnet.is_none() {
            return Err(ModuleError::new(
                ModuleCode::NatHairpinSubnetMissing,
                "Hairpin NAT потребує nat.hairpin_lan_subnet",
            ));
        }
        if !config.forward.is_empty() && (!enabled || !lists.enabled) {
            return Err(ModuleError::new(
                ModuleCode::NatForwardDependencies,
                "Port Forwarding потребує NAT та Interface Lists",
            ));
        }
        let mut forwards = Vec::new();
        let mut unique = std::collections::HashSet::new();
        for (id, settings) in &config.forward {
            let item = Forward::from_settings(id, settings)?;
            if !unique.insert((item.protocol.clone(), item.wan_port)) {
                return Err(ModuleError::new(
                    ModuleCode::NatDuplicateForward,
                    "Port Forwarding: повторено WAN протокол і порт",
                ));
            }
            if hairpin_enabled && item.dst_address.is_none() {
                return Err(ModuleError::new(ModuleCode::NatHairpinPublicAddressMissing, format!("Hairpin NAT: forward.{id}.dst_address обов'язковий для локального звернення за публічною IP")));
            }
            let mut item = item;
            item.hairpin = hairpin_enabled;
            forwards.push(item);
        }
        Ok(Self {
            enabled,
            masquerade,
            wan_list: lists.wan.clone(),
            lan_list: lists.lan.clone(),
            hairpin_enabled,
            hairpin_lan_subnet,
            forwards,
        })
    }
    pub fn forwards(&self) -> &[Forward] {
        &self.forwards
    }
    pub fn commands(&self) -> Vec<String> {
        if !self.enabled {
            return vec!["# NAT: вимкнено".into()];
        }
        let mut lines = vec!["# NAT: декларативне перенаправлення портів".into()];
        // DNAT суворо прив'язано до WAN; не відкриваємо порт керування на роутері.
        for f in &self.forwards {
            let dst = f
                .dst_address
                .as_ref()
                .map(|ip| format!(" dst-address={ip}"))
                .unwrap_or_default();
            lines.push(format!("/ip firewall nat add chain=dstnat action=dst-nat in-interface-list={} protocol={} dst-port={}{} to-addresses={} to-ports={} comment=mcm-pf-{}", self.wan_list, f.protocol, f.wan_port, dst, f.to_address, f.to_port, f.id));
            if self.hairpin_enabled {
                // Неконсистентна внутрішня структура не має спричиняти panic.
                let (Some(public_ip), Some(subnet)) =
                    (f.dst_address.as_ref(), self.hairpin_lan_subnet.as_ref())
                else {
                    continue;
                };
                // Зовнішній DNAT обмежений WAN, тому для LAN потрібне окреме правило.
                lines.push(format!("/ip firewall nat add chain=dstnat action=dst-nat in-interface-list={} src-address={} dst-address={} protocol={} dst-port={} to-addresses={} to-ports={} comment=mcm-hairpin-dst-{}", self.lan_list, subnet, public_ip, f.protocol, f.wan_port, f.to_address, f.to_port, f.id));
                // Мінімальний srcnat: лише LAN -> внутрішня ціль конкретного сервісу.
                lines.push(format!("/ip firewall nat add chain=srcnat action=masquerade src-address={} dst-address={} protocol={} dst-port={} connection-nat-state=dstnat ipsec-policy=out,none comment=mcm-hairpin-src-{}", subnet, f.to_address, f.protocol, f.to_port, f.id));
            }
        }
        if self.masquerade {
            lines.push(format!("/ip firewall nat add chain=srcnat action=masquerade out-interface-list={} ipsec-policy=out,none comment=mcm-wan-masquerade", self.wan_list));
        }
        lines
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn forward(
        protocol: &str,
        wan_port: u16,
        dst: Option<&str>,
        limit: Option<u16>,
    ) -> ForwardSettings {
        ForwardSettings {
            protocol: protocol.into(),
            wan_port,
            to_address: "192.168.88.100".into(),
            to_port: 80,
            tcp_new_limit: limit,
            dst_address: dst.map(str::to_string),
        }
    }
    fn nat(dst: Option<&str>, hairpin: bool) -> Nat {
        let item = Forward::from_settings("web", &forward("tcp", 8080, dst, Some(30))).unwrap();
        Nat {
            enabled: true,
            masquerade: true,
            wan_list: "WAN".into(),
            lan_list: "LAN".into(),
            hairpin_enabled: hairpin,
            hairpin_lan_subnet: Some("192.168.88.0/24".into()),
            forwards: vec![Forward { hairpin, ..item }],
        }
    }
    #[test]
    fn regression_12_typed_nat_errors_do_not_parse_messages() {
        let bad_protocol = Forward::from_settings("web", &forward("bad", 8080, None, None))
            .err()
            .unwrap();
        assert_eq!(bad_protocol.code, ModuleCode::NatForwardProtocol);
        let bad_port = Forward::from_settings("web", &forward("tcp", 0, None, None))
            .err()
            .unwrap();
        assert_eq!(bad_port.code, ModuleCode::NatForwardPort);
        let bad_limit = Forward::from_settings("web", &forward("udp", 8080, None, Some(30)))
            .err()
            .unwrap();
        assert_eq!(bad_limit.code, ModuleCode::NatForwardTcpLimit);
        let bad_cidr = validate_subnet("192.168.88.1/24").err().unwrap();
        assert_eq!(bad_cidr.code, ModuleCode::NatHairpinCidr);
        assert_eq!(
            bad_cidr.code.location(),
            ("nat.toml", "nat.hairpin_lan_subnet")
        );
    }

    #[test]
    fn typed_forward_rejects_invalid_ports_protocols_and_limits() {
        assert_eq!(
            Forward::from_settings("web", &forward("tcp", 8080, None, Some(30)))
                .unwrap()
                .tcp_limit,
            Some(30)
        );
        assert!(Forward::from_settings("web", &forward("udp", 8080, None, Some(30))).is_err());
        assert!(Forward::from_settings("web", &forward("tcp", 0, None, None)).is_err());
        assert!(Forward::from_settings("web", &forward("bad", 8080, None, None)).is_err());
        let mut bad = forward("tcp", 8080, None, None);
        bad.to_address = "127.0.0.1".into();
        assert!(Forward::from_settings("web", &bad).is_err());
    }
    #[test]
    fn paired_dnat_is_wan_scoped() {
        let rules = nat(None, false).commands();
        assert!(rules.iter().any(|s| s.contains(
            "chain=dstnat action=dst-nat in-interface-list=WAN protocol=tcp dst-port=8080"
        )));
        assert!(rules.iter().any(|s| s.contains("mcm-wan-masquerade")));
        assert!(!rules.iter().any(|s| s.contains("mcm-hairpin-")));
    }
    #[test]
    fn absent_or_empty_destination_omits_match() {
        for dst in [None, Some("")] {
            assert_eq!(
                Forward::from_settings("web", &forward("tcp", 8080, dst, None))
                    .unwrap()
                    .dst_address,
                None
            );
            assert!(!nat(dst, false)
                .commands()
                .iter()
                .any(|s| s.contains(" dst-address=")));
        }
    }
    #[test]
    fn explicit_destination_is_added_only_when_set() {
        let rules = nat(Some("203.0.113.7"), false).commands();
        assert!(rules
            .iter()
            .any(|s| s.contains("in-interface-list=WAN") && s.contains("dst-address=203.0.113.7")));
        assert!(!rules.iter().any(|s| s.contains("mcm-hairpin-")));
    }
    #[test]
    fn hairpin_generates_lan_only_dnat_and_targeted_snat() {
        let rules = nat(Some("203.0.113.7"), true).commands();
        assert!(rules.iter().any(|s| s.contains("chain=dstnat")
            && s.contains("in-interface-list=LAN")
            && s.contains("src-address=192.168.88.0/24")
            && s.contains("dst-address=203.0.113.7")
            && s.contains("mcm-hairpin-dst-web")));
        assert!(rules.iter().any(|s| s.contains("chain=srcnat")
            && s.contains("dst-address=192.168.88.100")
            && s.contains("dst-port=80")
            && s.contains("mcm-hairpin-src-web")));
    }
    #[test]
    fn rejects_invalid_destinations_and_subnets() {
        for dst in ["a.b.c.d", "127.0.0.1", "0.0.0.0", "224.0.0.1"] {
            assert!(Forward::from_settings("web", &forward("tcp", 8080, Some(dst), None)).is_err());
        }
        for bad in ["192.168.88.3/24", "invalid", "192.168.88.0/33", "0.0.0.0/0"] {
            assert!(validate_subnet(bad).is_err());
        }
    }
    #[test]
    fn typed_forward_order_is_stable() {
        let cfg: NatConfig = toml::from_str(
            r#"[nat]
enabled = true
masquerade = true
[forward.zed]
protocol = "tcp"
wan_port = 8080
to_address = "192.168.88.100"
to_port = 80
[forward.aaa]
protocol = "udp"
wan_port = 5353
to_address = "192.168.88.101"
to_port = 53
"#,
        )
        .unwrap();
        let ids: Vec<_> = cfg.forward.keys().map(String::as_str).collect();
        assert_eq!(ids, vec!["aaa", "zed"]);
        assert!(Forward::from_settings("aaa", &cfg.forward["aaa"]).is_ok());
    }
}
