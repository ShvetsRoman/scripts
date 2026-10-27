//! Спільна IPv4/CIDR-математика без прив'язки до профілів.
use std::net::Ipv4Addr;

pub(super) fn subnet(ip: Ipv4Addr, prefix: u8) -> u32 {
    let mask = if prefix == 0 {
        0
    } else {
        u32::MAX << (32 - prefix)
    };
    u32::from(ip) & mask
}

pub(super) fn overlaps(a: (Ipv4Addr, u8), b: (Ipv4Addr, u8)) -> bool {
    let prefix = a.1.min(b.1);
    subnet(a.0, prefix) == subnet(b.0, prefix)
}

pub(super) fn valid_host(ip: Ipv4Addr, prefix: u8) -> bool {
    if prefix == 0 || prefix > 30 {
        return false;
    }
    let mask = u32::MAX << (32 - prefix);
    let value = u32::from(ip);
    let network = value & mask;
    value != network && value != (network | !mask)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn subnet_edge_cases_and_overlapping_cidrs() {
        let a = Ipv4Addr::new(10, 4, 8, 1);
        assert_eq!(subnet(a, 0), 0);
        assert_eq!(subnet(a, 32), u32::from(a));
        assert!(overlaps((a, 24), (Ipv4Addr::new(10, 4, 8, 128), 25)));
        assert!(!overlaps((a, 24), (Ipv4Addr::new(10, 4, 9, 1), 24)));
        assert!(!valid_host(Ipv4Addr::new(10, 4, 8, 0), 24));
        assert!(valid_host(a, 24));
        assert!(!valid_host(a, 0));
        assert!(!valid_host(a, 31));
        assert!(!valid_host(a, 32));
        // Незалежно від адреси профілю, дві підмережі перетинаються симетрично.
        for prefix in [0, 1, 8, 16, 24, 30, 32] {
            let other = (Ipv4Addr::new(10, 4, 8, 201), prefix);
            assert_eq!(overlaps((a, 24), other), overlaps(other, (a, 24)));
        }
    }
}
