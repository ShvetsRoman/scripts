use super::lists::Lists;
use super::network::{parse_address, subnet, Network};
use super::reference_error::{ModuleCode, ModuleError};
use mikrotik_config_manager::typed_config::FirewallSettings;
use std::net::Ipv4Addr;

// Порядок INPUT: стан з’єднання -> керування LAN -> захист WAN -> служби -> DROP.
pub struct Firewall {
    enabled: bool,
    allow_icmp: bool,
    allow_lan_dhcp: bool,
    input_default_drop: bool,
    forward_default_drop: bool,
    fasttrack: bool,
    lan_to_wan: bool,
    dns_cache: bool,
    management_subnet: String,
    management_interface: String,
    lan_interface: String,
    wan_list: String,
    lan_list: String,
    ssh_port: u16,
    winbox_port: u16,
    allow_winbox: bool,
    drop_new_wan: bool,
    brute_force: bool,
    brute_ports: Vec<u16>,
    icmp_limit: u16,
}
impl Firewall {
    pub fn parse(
        cfg: &FirewallSettings,
        lan: &Network,
        lists: &Lists,
        dns_cache: bool,
        ssh_port: u16,
        winbox_port: u16,
        allow_winbox: bool,
    ) -> Result<Self, ModuleError> {
        let enabled = cfg.enabled;
        let allow_icmp = cfg.allow_icmp;
        let allow_lan_dhcp = cfg.allow_lan_dhcp;
        let input_default_drop = cfg.input_default_drop;
        let forward_default_drop = cfg.forward_default_drop;
        let fasttrack = cfg.fasttrack;
        let lan_to_wan = cfg.lan_to_wan;
        // Забороняємо мовчазне ігнорування WAN DROP, якщо Firewall вимкнений.
        // Перевіряємо цю властивість до інших залежностей, щоб діагностика
        // точно вказувала на явно запитану DROP-політику.
        if cfg.drop_new_wan && !enabled {
            return Err(ModuleError::new(
                ModuleCode::FirewallDropRequiresEnabled,
                "Drop-політика потребує Firewall",
            ));
        }
        if (fasttrack || lan_to_wan || dns_cache) && !enabled {
            return Err(ModuleError::new(
                ModuleCode::FirewallRequired,
                "Потрібен увімкнений Firewall",
            ));
        }
        // SSH і WinBox визначаються тільки Services, а не дублюються у Firewall.
        if ssh_port == 0 || winbox_port == 0 || ssh_port == winbox_port {
            return Err(ModuleError::new(
                ModuleCode::FirewallManagementPorts,
                "SSH/WinBox: порти мають бути різними та ненульовими",
            ));
        }
        let drop_new_wan = cfg.drop_new_wan;
        if !lists.enabled {
            return Err(ModuleError::new(
                ModuleCode::FirewallListsRequired,
                "Firewall потребує Interface Lists",
            ));
        }
        if (input_default_drop || forward_default_drop) && !enabled {
            return Err(ModuleError::new(
                ModuleCode::FirewallDropRequiresEnabled,
                "Drop-політика потребує Firewall",
            ));
        }
        let (ip, prefix) = parse_address(&lan.management_address)
            .map_err(|e| ModuleError::from_ipv4(ModuleCode::FirewallManagementPrefix, e))?;
        if !(1..=30).contains(&prefix) {
            return Err(ModuleError::new(
                ModuleCode::FirewallManagementPrefix,
                "Firewall: некоректний префікс керування",
            ));
        }
        let mgmt_network = subnet(ip, prefix);
        let lan_network = subnet(lan.lan_ip, lan.prefix);
        let mgmt_mask = u32::MAX << (32 - prefix);
        let lan_mask = u32::MAX << (32 - lan.prefix);
        if lan.management_interface != lan.lan_interface
            && ((mgmt_network & lan_mask) == lan_network
                || (lan_network & mgmt_mask) == mgmt_network)
        {
            return Err(ModuleError::new(
                ModuleCode::FirewallManagementOverlap,
                "Firewall: LAN перетинається з мережею керування",
            ));
        }
        // Захист рахує нові WAN TCP-з'єднання; LAN ніколи не оцінюється.
        let brute_force = cfg.brute_force_enabled;
        let brute_ports = cfg
            .brute_force_ports
            .split(',')
            .map(|p| {
                p.parse::<u16>().map_err(|_| {
                    ModuleError::new(
                        ModuleCode::FirewallBruteforcePorts,
                        "Некоректний brute_force_ports",
                    )
                })
            })
            .collect::<Result<Vec<_>, _>>()?;
        if brute_ports.is_empty() || brute_ports.len() > 8 || brute_ports.contains(&0) {
            return Err(ModuleError::new(
                ModuleCode::FirewallBruteforcePorts,
                "Brute force: потрібно 1–8 коректних портів",
            ));
        }
        let distinct: std::collections::HashSet<u16> = brute_ports.iter().copied().collect();
        if distinct.len() != brute_ports.len() {
            return Err(ModuleError::new(
                ModuleCode::FirewallBruteforceDuplicate,
                "Brute force: повторений порт",
            ));
        }
        if brute_force && !enabled {
            return Err(ModuleError::new(
                ModuleCode::FirewallBruteforceRequiresEnabled,
                "Brute force потребує Firewall",
            ));
        }
        let icmp_limit = u16::try_from(cfg.icmp_limit_per_second).map_err(|_| {
            ModuleError::new(
                ModuleCode::FirewallIcmpLimit,
                "Некоректний icmp_limit_per_second",
            )
        })?;
        if icmp_limit > 1000 {
            return Err(ModuleError::new(
                ModuleCode::FirewallIcmpLimit,
                "icmp_limit_per_second: максимум 1000",
            ));
        }
        Ok(Self {
            enabled,
            allow_icmp,
            allow_lan_dhcp,
            input_default_drop,
            forward_default_drop,
            fasttrack,
            lan_to_wan,
            dns_cache,
            management_subnet: format!("{}/{}", Ipv4Addr::from(mgmt_network), prefix),
            management_interface: lan.management_interface.clone(),
            lan_interface: lan.lan_interface.clone(),
            wan_list: lists.wan.clone(),
            lan_list: lists.lan.clone(),
            ssh_port,
            winbox_port,
            allow_winbox,
            drop_new_wan,
            brute_force,
            brute_ports,
            icmp_limit,
        })
    }
    // Вставляємо VPN-дозволи до фінального DROP, не після нього.
    pub fn commands_with_wireguard(
        &self,
        wg: Option<&super::wireguard::Wireguard>,
        forwards: &[super::nat::Forward],
    ) -> Vec<String> {
        if !self.enabled {
            return vec!["# FIREWALL: вимкнено".into()];
        }
        let mut out = vec![
            "# FIREWALL INPUT: порядок важливий, PLAN ONLY".into(),
            "/ip firewall filter add chain=input action=accept connection-state=established,related,untracked comment=mcm-input-established".into(),
            "/ip firewall filter add chain=input action=drop connection-state=invalid comment=mcm-input-invalid".into(),
            format!("/ip firewall filter add chain=input action=accept protocol=tcp dst-port={} in-interface={} src-address={} comment=mcm-input-ssh-management", self.ssh_port, self.management_interface, self.management_subnet),
        ];
        // Дозволи SSH та WinBox із LAN формуються поруч до правил WAN.
        if self.allow_winbox {
            out.push(format!("/ip firewall filter add chain=input action=accept protocol=tcp dst-port={} in-interface={} src-address={} comment=mcm-input-winbox-management", self.winbox_port, self.management_interface, self.management_subnet));
        }
        if self.brute_force {
            let ports = self
                .brute_ports
                .iter()
                .map(u16::to_string)
                .collect::<Vec<_>>()
                .join(",");
            // Лише WAN; правило block має бути раніше дозволів із WAN/VPN.
            // Адреси LAN не додаються до списків за жодних умов.
            out.push(format!("/ip firewall filter add chain=input action=drop in-interface-list={} protocol=tcp dst-port={} src-address-list=mcm-bf-blacklist comment=mcm-bf-drop", self.wan_list, ports));
            for (source, destination, timeout, comment) in [
                (
                    "mcm-bf-stage3",
                    "mcm-bf-blacklist",
                    "1d",
                    "mcm-bf-blacklist",
                ),
                ("mcm-bf-stage2", "mcm-bf-stage3", "1h", "mcm-bf-stage3"),
                ("mcm-bf-stage1", "mcm-bf-stage2", "15m", "mcm-bf-stage2"),
            ] {
                out.push(format!("/ip firewall filter add chain=input action=add-src-to-address-list in-interface-list={} protocol=tcp connection-state=new dst-port={} src-address-list={} address-list={} address-list-timeout={} comment={}", self.wan_list, ports, source, destination, timeout, comment));
            }
            out.push(format!("/ip firewall filter add chain=input action=add-src-to-address-list in-interface-list={} protocol=tcp connection-state=new dst-port={} address-list=mcm-bf-stage1 address-list-timeout=5m comment=mcm-bf-stage1", self.wan_list, ports));
        }
        if self.allow_icmp {
            if self.icmp_limit > 0 {
                // LAN отримує ICMP без ліміту; обмеження діє тільки на WAN.
                out.push(format!("/ip firewall filter add chain=input action=accept protocol=icmp in-interface-list={} comment=mcm-input-icmp-lan", self.lan_list));
                out.push(format!("/ip firewall filter add chain=input action=accept protocol=icmp in-interface-list={} limit={}/1s,{} comment=mcm-input-icmp-wan-limit", self.wan_list, self.icmp_limit, self.icmp_limit));
                out.push(format!("/ip firewall filter add chain=input action=drop protocol=icmp in-interface-list={} comment=mcm-input-icmp-wan-excess", self.wan_list));
            } else {
                out.push("/ip firewall filter add chain=input action=accept protocol=icmp comment=mcm-input-icmp".into());
            }
        }
        if self.allow_lan_dhcp {
            out.push(format!("/ip firewall filter add chain=input action=accept protocol=udp dst-port=67 in-interface={} comment=mcm-input-dhcp", self.lan_interface));
        }
        if self.dns_cache {
            for proto in ["udp", "tcp"] {
                out.push(format!("/ip firewall filter add chain=input action=accept in-interface-list={} protocol={} dst-port=53 comment=mcm-input-dns-{}", self.lan_list, proto, proto));
            }
        }
        if let Some(wg) = wg {
            out.extend(wg.input_rules(&self.wan_list));
            // Дозволи VPN-керування стоять раніше за WAN new DROP та final DROP.
            out.extend(wg.management_rules(
                self.ssh_port,
                self.winbox_port,
                true,
                self.allow_winbox,
            ));
        }
        if self.drop_new_wan {
            out.push(format!("/ip firewall filter add chain=input action=drop in-interface-list={} connection-state=new comment=mcm-input-wan-new-drop", self.wan_list));
        }
        if self.input_default_drop {
            out.push(
                "/ip firewall filter add chain=input action=drop comment=mcm-input-final-drop"
                    .into(),
            );
        }
        out.push(
            "# FIREWALL FORWARD: FastTrack перед established; дозволити LAN→WAN перед DROP".into(),
        );
        if self.fasttrack {
            out.push("/ip firewall filter add chain=forward action=fasttrack-connection connection-state=established,related comment=mcm-forward-fasttrack".into());
        }
        out.push("/ip firewall filter add chain=forward action=accept connection-state=established,related,untracked comment=mcm-forward-established".into());
        out.push("/ip firewall filter add chain=forward action=drop connection-state=invalid comment=mcm-forward-invalid".into());
        // DNAT-дозволи перед загальним WAN DROP, лише на конкретні IP і порт.
        for f in forwards {
            if let Some(limit) = f.tcp_limit {
                // Перший дозвіл обмежує загальну швидкість нових TCP-з’єднань для правила.
                out.push(format!("/ip firewall filter add chain=forward action=accept in-interface-list={} protocol=tcp connection-state=new connection-nat-state=dstnat dst-address={} dst-port={} limit={}/1s,{} comment=mcm-pf-{}-rate-allow", self.wan_list, f.to_address, f.to_port, limit, limit, f.id));
                out.push(format!("/ip firewall filter add chain=forward action=drop in-interface-list={} protocol=tcp connection-state=new connection-nat-state=dstnat dst-address={} dst-port={} comment=mcm-pf-{}-rate-drop", self.wan_list, f.to_address, f.to_port, f.id));
            }
            if f.tcp_limit.is_none() {
                out.push(format!("/ip firewall filter add chain=forward action=accept in-interface-list={} connection-state=new connection-nat-state=dstnat protocol={} dst-address={} dst-port={} comment=mcm-pf-{}-allow", self.wan_list, f.protocol, f.to_address, f.to_port, f.id));
            }
        }
        // Локальний Hairpin DNAT: конкретна внутрішня ціль і порт до final DROP.
        for f in forwards.iter().filter(|f| f.hairpin) {
            out.push(format!("/ip firewall filter add chain=forward action=accept in-interface-list={} out-interface-list={} connection-state=new connection-nat-state=dstnat protocol={} dst-address={} dst-port={} comment=mcm-hairpin-forward-{}", self.lan_list, self.lan_list, f.protocol, f.to_address, f.to_port, f.id));
        }
        if self.lan_to_wan {
            out.push(format!("/ip firewall filter add chain=forward action=accept in-interface-list={} out-interface-list={} comment=mcm-forward-lan-to-wan", self.lan_list, self.wan_list));
        }
        if let Some(wg) = wg {
            out.extend(wg.forward_rules(&self.lan_list, &self.wan_list));
        }
        if self.drop_new_wan {
            out.push(format!("/ip firewall filter add chain=forward action=drop in-interface-list={} connection-state=new connection-nat-state=!dstnat comment=mcm-forward-wan-new-drop", self.wan_list));
        }
        if self.forward_default_drop {
            out.push(
                "/ip firewall filter add chain=forward action=drop comment=mcm-forward-final-drop"
                    .into(),
            );
        }
        out
    }
}

#[cfg(test)]
mod security_profile_tests {
    use super::*;

    #[test]
    fn brute_force_wan_only_and_before_final_drop() {
        // Модель тесту: LAN-підключення не мають потрапляти в адресу блокування.
        let fw = Firewall {
            enabled: true,
            allow_icmp: true,
            allow_lan_dhcp: true,
            input_default_drop: true,
            forward_default_drop: true,
            fasttrack: false,
            lan_to_wan: true,
            dns_cache: false,
            management_subnet: "192.168.88.0/24".into(),
            management_interface: "bridge-lan".into(),
            lan_interface: "bridge-lan".into(),
            wan_list: "WAN".into(),
            lan_list: "LAN".into(),
            ssh_port: 22,
            winbox_port: 8291,
            allow_winbox: true,
            drop_new_wan: true,
            brute_force: true,
            brute_ports: vec![22, 8291],
            icmp_limit: 0,
        };
        let lines = fw.commands_with_wireguard(None, &[]);
        let relevant: Vec<_> = lines.iter().filter(|s| s.contains("mcm-bf-")).collect();
        assert_eq!(relevant.len(), 5);
        assert!(relevant.iter().all(|s| s.contains("in-interface-list=WAN")));
        assert!(relevant.iter().all(|s| s.contains("dst-port=22,8291")));
        let before = lines
            .iter()
            .position(|s| s.contains("comment=mcm-bf-drop"))
            .unwrap();
        let last = lines
            .iter()
            .position(|s| s.contains("comment=mcm-input-final-drop"))
            .unwrap();
        assert!(before < last);
    }
}

#[cfg(test)]
mod forward_rate_tests {
    use super::*;
    fn firewall() -> Firewall {
        Firewall {
            enabled: true,
            allow_icmp: true,
            allow_lan_dhcp: true,
            input_default_drop: true,
            forward_default_drop: true,
            fasttrack: false,
            lan_to_wan: true,
            dns_cache: false,
            management_subnet: "192.168.88.0/24".into(),
            management_interface: "bridge-lan".into(),
            lan_interface: "bridge-lan".into(),
            wan_list: "WAN".into(),
            lan_list: "LAN".into(),
            ssh_port: 22,
            winbox_port: 8291,
            allow_winbox: true,
            drop_new_wan: true,
            brute_force: false,
            brute_ports: vec![22, 8291],
            icmp_limit: 10,
        }
    }
    #[test]
    fn lan_icmp_precedes_wan_rate_limit_and_excess_drop() {
        let cmds = firewall().commands_with_wireguard(None, &[]);
        let pos = |needle: &str| cmds.iter().position(|x| x.contains(needle)).unwrap();
        assert!(pos("mcm-input-icmp-lan") < pos("mcm-input-icmp-wan-limit"));
        assert!(pos("mcm-input-icmp-wan-limit") < pos("mcm-input-icmp-wan-excess"));
        assert!(pos("mcm-input-icmp-wan-excess") < pos("mcm-input-final-drop"));
    }
    #[test]
    fn published_tcp_service_is_allowed_and_limited_before_forward_drop() {
        let item = super::super::nat::Forward {
            id: "web".into(),
            protocol: "tcp".into(),
            wan_port: 8080,
            to_address: "192.168.88.100".into(),
            to_port: 80,
            tcp_limit: Some(30),
            dst_address: None,
            hairpin: false,
        };
        let cmds = firewall().commands_with_wireguard(None, &[item]);
        let pos = |needle: &str| cmds.iter().position(|x| x.contains(needle)).unwrap();
        assert!(pos("mcm-pf-web-rate-allow") < pos("mcm-pf-web-rate-drop"));
        assert!(pos("mcm-pf-web-rate-drop") < pos("mcm-forward-final-drop"));
        assert!(cmds
            .iter()
            .any(|x| x.contains("limit=30/1s,30") && x.contains("connection-nat-state=dstnat")));
    }
}

#[cfg(test)]
mod input_order_regression_tests {
    use super::*;

    fn firewall(allow_winbox: bool, brute_force: bool) -> Firewall {
        Firewall {
            enabled: true,
            allow_icmp: true,
            allow_lan_dhcp: true,
            input_default_drop: true,
            forward_default_drop: true,
            fasttrack: false,
            lan_to_wan: true,
            dns_cache: true,
            management_subnet: "192.168.88.0/24".into(),
            management_interface: "bridge-lan".into(),
            lan_interface: "bridge-lan".into(),
            wan_list: "WAN".into(),
            lan_list: "LAN".into(),
            ssh_port: 22,
            winbox_port: 8291,
            allow_winbox,
            drop_new_wan: true,
            brute_force,
            brute_ports: vec![22, 8291],
            icmp_limit: 10,
        }
    }

    fn index(lines: &[String], comment: &str) -> usize {
        lines
            .iter()
            .position(|s| s.contains(&format!("comment={comment}")))
            .unwrap_or_else(|| panic!("Відсутнє правило {comment}"))
    }

    #[test]
    fn management_is_adjacent_and_before_wan_bruteforce() {
        let lines = firewall(true, true).commands_with_wireguard(None, &[]);
        let ssh = index(&lines, "mcm-input-ssh-management");
        let winbox = index(&lines, "mcm-input-winbox-management");
        assert_eq!(winbox, ssh + 1, "SSH і WinBox мають стояти поруч");
        assert!(index(&lines, "mcm-input-established") < index(&lines, "mcm-input-invalid"));
        assert!(index(&lines, "mcm-input-invalid") < ssh);
        assert!(winbox < index(&lines, "mcm-bf-drop"));
        assert!(index(&lines, "mcm-bf-drop") < index(&lines, "mcm-bf-blacklist"));
        assert!(index(&lines, "mcm-bf-blacklist") < index(&lines, "mcm-bf-stage3"));
        assert!(index(&lines, "mcm-bf-stage3") < index(&lines, "mcm-bf-stage2"));
        assert!(index(&lines, "mcm-bf-stage2") < index(&lines, "mcm-bf-stage1"));
        assert!(index(&lines, "mcm-bf-stage1") < index(&lines, "mcm-input-icmp-lan"));
        assert!(index(&lines, "mcm-input-icmp-wan-excess") < index(&lines, "mcm-input-dhcp"));
        assert!(index(&lines, "mcm-input-dhcp") < index(&lines, "mcm-input-dns-udp"));
        assert!(index(&lines, "mcm-input-dns-udp") < index(&lines, "mcm-input-dns-tcp"));
        assert!(index(&lines, "mcm-input-dns-tcp") < index(&lines, "mcm-input-wan-new-drop"));
        assert!(index(&lines, "mcm-input-wan-new-drop") < index(&lines, "mcm-input-final-drop"));
        assert!(lines
            .iter()
            .filter(|s| s.contains("comment=mcm-bf-"))
            .all(|s| s.contains("in-interface-list=WAN")));
    }

    #[test]
    fn optional_winbox_and_bruteforce_keep_existing_policy() {
        for (allow_winbox, brute_force) in [(true, false), (false, true), (false, false)] {
            let lines = firewall(allow_winbox, brute_force).commands_with_wireguard(None, &[]);
            assert_eq!(
                lines
                    .iter()
                    .any(|s| s.contains("comment=mcm-input-winbox-management")),
                allow_winbox
            );
            assert_eq!(
                lines.iter().any(|s| s.contains("comment=mcm-bf-drop")),
                brute_force
            );
            assert!(
                index(&lines, "mcm-input-ssh-management") < index(&lines, "mcm-input-icmp-lan")
            );
            assert!(index(&lines, "mcm-input-dns-tcp") < index(&lines, "mcm-input-final-drop"));
        }
    }
}

#[cfg(test)]
mod typed_firewall_tests {
    use mikrotik_config_manager::typed_config::{read_typed, FirewallConfig};
    use std::path::Path;

    #[test]
    fn serde_firewall_both_profiles_have_safe_drop_policies() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        for profile in ["test", "hap-ac"] {
            let config: FirewallConfig =
                read_typed(&root.join("routers").join(profile).join("firewall.toml")).unwrap();
            assert!(config.firewall.enabled);
            assert!(config.firewall.input_default_drop);
            assert!(config.firewall.forward_default_drop);
            assert!(config.firewall.drop_new_wan);
        }
    }

    #[test]
    fn serde_firewall_rejects_wrong_bool_and_unknown_fields() {
        let good = r#"[firewall]
enabled = true
allow_icmp = true
allow_lan_dhcp = true
input_default_drop = true
forward_default_drop = true
lan_to_wan = true
fasttrack = false
drop_new_wan = true
brute_force_enabled = false
brute_force_ports = "22,8291"
icmp_limit_per_second = 0
"#;
        let valid: FirewallConfig = toml::from_str(good).unwrap();
        assert!(valid.firewall.input_default_drop);
        assert!(toml::from_str::<FirewallConfig>(
            &good.replace("fasttrack = false", "fasttrack = \"false\"")
        )
        .is_err());
        assert!(toml::from_str::<FirewallConfig>(&format!("{good}unexpected = 1\n")).is_err());
    }
}
