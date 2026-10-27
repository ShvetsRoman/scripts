// Тематичні інтеграційні тести. Робочий код не змінено.
#[allow(dead_code)]
mod support;
use support::*;

#[test]
fn dynamic_pool_does_not_overlap_static_leases() {
    let out = cli(&["plan", "hap-ac", "dhcp"]);
    assert!(out.status.success());
    let text = String::from_utf8_lossy(&out.stdout);
    let start = config_value("hap-ac", "dhcp", "pool.lan", "start");
    let end = config_value("hap-ac", "dhcp", "pool.lan", "end");
    assert!(text.contains(&format!("ranges={start}-{end}")));
    let dns = config_value("hap-ac", "dhcp", "network.lan", "gateway");
    assert!(text.contains(&format!("dns-server={dns}")));
    let lease = config_value("hap-ac", "dhcp", "server.lan", "lease_time");
    assert!(text.contains(&format!("lease-time={lease}")));
}
#[test]
fn consistency_dhcp_router_dns_requires_cache() {
    let result = consistency_fixture(
        "dns-disabled",
        "dns.toml",
        "allow_remote_requests = true",
        "allow_remote_requests = false",
    );
    assert!(!result.status.success());
    assert!(String::from_utf8_lossy(&result.stderr).contains("DNS cache"));
}

#[test]
fn static_audit_rejects_duplicate_dhcp_dns() {
    let servers = config_value("test", "dhcp", "network.lan", "dns_servers");
    let list: Vec<String> = servers
        .trim_start_matches('[')
        .trim_end_matches(']')
        .split(',')
        .map(|s| s.trim().trim_matches('"').to_owned())
        .collect();
    assert!(!list.is_empty() && !list[0].is_empty());
    let duplicated = format!("dns_servers = [\"{}\", \"{}\"]", list[0], list[0]);
    let original = format!("dns_servers = {servers}");
    let out = audit_profile(&[("dhcp.toml", &original, &duplicated)]);
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("повторена адреса DHCP DNS"));
}
