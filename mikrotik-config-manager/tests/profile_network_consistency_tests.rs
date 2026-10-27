// Контракт незалежних профілів: перевіряємо узгодженість значень,
// не нав’язуючи адресу, назву або кількість портів конкретного маршрутизатора.
use std::{net::Ipv4Addr, path::Path};

fn network_and_prefix(cidr: &str) -> (u32, u32) {
    let (host, bits) = cidr.split_once('/').expect("потрібна адреса CIDR");
    let bits: u32 = bits.parse().expect("префікс IPv4");
    assert!(bits <= 32);
    let host: Ipv4Addr = host.parse().expect("адреса IPv4");
    let mask = if bits == 0 {
        0
    } else {
        u32::MAX << (32 - bits)
    };
    (u32::from(host) & mask, mask)
}

#[test]
fn each_profile_has_consistent_lan_and_dhcp_references() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("routers");
    let mut count = 0;
    for entry in std::fs::read_dir(root).unwrap() {
        let entry = entry.unwrap();
        if !entry.file_type().unwrap().is_dir() {
            continue;
        }
        count += 1;
        let dir = entry.path();
        let network: toml::Value =
            toml::from_str(&std::fs::read_to_string(dir.join("network.toml")).unwrap()).unwrap();
        let dhcp: toml::Value =
            toml::from_str(&std::fs::read_to_string(dir.join("dhcp.toml")).unwrap()).unwrap();
        let nat: toml::Value =
            toml::from_str(&std::fs::read_to_string(dir.join("nat.toml")).unwrap()).unwrap();
        let lan = network["network"]["lan"]["address"].as_str().unwrap();
        let (base, mask) = network_and_prefix(lan);
        let gateway = dhcp["network"]["lan"]["gateway"].as_str().unwrap();
        let gw: Ipv4Addr = gateway.parse().unwrap();
        assert_eq!(u32::from(gw) & mask, base, "{dir:?}: DHCP gateway поза LAN");
        let start: Ipv4Addr = dhcp["pool"]["lan"]["start"]
            .as_str()
            .unwrap()
            .parse()
            .unwrap();
        let end: Ipv4Addr = dhcp["pool"]["lan"]["end"]
            .as_str()
            .unwrap()
            .parse()
            .unwrap();
        assert!(
            u32::from(start) <= u32::from(end),
            "{dir:?}: зворотний DHCP-пул"
        );
        assert_eq!(
            u32::from(start) & mask,
            base,
            "{dir:?}: початок пулу поза LAN"
        );
        assert_eq!(u32::from(end) & mask, base, "{dir:?}: кінець пулу поза LAN");
        if nat["nat"]["hairpin_enabled"].as_bool() == Some(true) {
            let subnet = nat["nat"]["hairpin_lan_subnet"].as_str().unwrap();
            let (nat_base, nat_mask) = network_and_prefix(subnet);
            assert_eq!(
                nat_base,
                base & nat_mask,
                "{dir:?}: hairpin subnet поза LAN"
            );
        }
    }
    assert!(count > 0, "немає профілів для перевірки");
}
