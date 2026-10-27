// Тематичні інтеграційні тести. Робочий код не змінено.
#[allow(dead_code)]
mod support;
use support::*;

#[test]
fn wireguard_disabled_by_default_for_both_profiles() {
    for profile in ["hap-ac", "test"] {
        let out = cli(&["plan", profile, "wireguard"]);
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        let plan = String::from_utf8_lossy(&out.stdout);
        assert!(plan.contains("WIREGUARD:"));
        assert!(!plan.contains("/interface wireguard add"));
        assert!(!plan.contains("private-key="));
    }
}

// Новий модуль присутній у загальному плані, а у вибірковому немає інших ресурсів.
#[test]
fn wireguard_is_selective_and_apply_stays_blocked() {
    let out = cli(&["plan", "hap-ac", "wireguard"]);
    assert!(out.status.success());
    let plan = String::from_utf8_lossy(&out.stdout);
    assert!(!plan.contains("/ip dhcp-server add"));
    assert!(!plan.contains("/ip firewall filter add"));
    assert!(!cli(&["apply", "hap-ac"]).status.success());
    assert!(!cli(&["apply", "test"]).status.success());
}

// Конфігураційні файли WireGuard мають декларативну схему без секретів.
#[test]
fn wireguard_declaration_contains_no_private_keys() {
    for profile in ["hap-ac", "test"] {
        let file = read_active_toml(format!("routers/{profile}/wireguard.toml"));
        assert!(file.contains("[wireguard]"));
        assert!(file.contains("enabled = false"));
        assert!(!file
            .lines()
            .any(|l| l.trim_start().starts_with("private_key =")));
        assert!(!file
            .lines()
            .any(|l| l.trim_start().starts_with("preshared_key =")));
    }
}

// Ізольована копія профілів: негативні тести не змінюють робочі TOML.
#[test]
fn wireguard_udp_and_lan_allow_precede_drop() {
    let out = wg_plan("vpn-order", WG_OK, "firewall");
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let text = String::from_utf8_lossy(&out.stdout);
    assert!(
        text.find("mcm-input-wireguard-udp").unwrap() < text.find("mcm-input-final-drop").unwrap()
    );
    assert!(
        text.find("mcm-forward-wireguard-lan").unwrap()
            < text.find("mcm-forward-final-drop").unwrap()
    );
    assert!(!text.contains("mcm-forward-wireguard-wan"));
}
#[test]
fn wireguard_overlapping_lan_is_rejected() {
    // Беремо адресу LAN з поточного профілю, а не з історичної конфігурації.
    let network: toml::Value = std::fs::read_to_string("routers/test/network.toml")
        .unwrap()
        .parse()
        .unwrap();
    let lan_address = network["network"]["lan"]["address"].as_str().unwrap();
    assert!(WG_OK.contains("10.77.0.1/24"));
    let conf = WG_OK.replace("10.77.0.1/24", lan_address);
    let out = wg_plan("vpn-overlap", &conf, "wireguard");
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("перетинається"));
}
#[test]
fn wireguard_internet_requires_explicit_wan_permission() {
    let conf = WG_OK
        .replace("allow_wan = true", "allow_wan = false")
        .replace("allow_internet = false", "allow_internet = true");
    assert!(!wg_plan("vpn-wan-guard", &conf, "wireguard")
        .status
        .success());
}
#[test]
fn wireguard_internet_generates_explicit_forward_and_nat() {
    let conf = WG_OK.replace("allow_internet = false", "allow_internet = true");
    for (modname, needle) in [
        ("firewall", "mcm-forward-wireguard-wan"),
        ("nat", "mcm-wireguard-wan-masquerade"),
    ] {
        let out = wg_plan(&format!("vpn-{modname}"), &conf, modname);
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        assert!(String::from_utf8_lossy(&out.stdout).contains(needle));
    }
}
#[test]
fn wireguard_private_keys_are_never_in_plan() {
    let out = wg_plan("vpn-secret", WG_OK, "wireguard");
    assert!(out.status.success());
    let text = String::from_utf8_lossy(&out.stdout);
    assert!(!text.contains("private-key="));
    assert!(!text.contains("preshared-key="));
}

#[test]
fn wireguard_peer_outside_vpn_is_rejected() {
    let conf=format!("{WG_OK}\n[peers.phone]\nenabled = true\npublic_key = \"{}=\"\nallowed_address = \"10.90.0.2/32\"\n", "A".repeat(43));
    let out = wg_plan("peer-outside", &conf, "wireguard");
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("поза VPN"));
}
#[test]
fn wireguard_duplicate_peer_network_is_rejected() {
    let conf=format!("{WG_OK}\n[peers.phone]\nenabled = true\npublic_key = \"{}=\"\nallowed_address = \"10.77.0.2/32\"\n\n[peers.laptop]\nenabled = true\npublic_key = \"{}=\"\nallowed_address = \"10.77.0.2/32\"\n", "A".repeat(43), "Q".repeat(43));
    let out = wg_plan("peer-duplicate", &conf, "wireguard");
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("allowed_address"));
}

// Запускаємо інтеграційний сценарій на копії профілю, не змінюючи файли користувача.
// Короткий виклик для перевірки виключно правил Firewall.
#[test]
fn wireguard_router_management_is_opt_in_and_precedes_drop() {
    let (plan, error, success) = wireguard_plan_with_management(true, true, true);
    assert!(success, "{error}");
    let ssh = plan.find("comment=mcm-input-wireguard-ssh").unwrap();
    let winbox = plan.find("comment=mcm-input-wireguard-winbox").unwrap();
    let drop = plan.find("comment=mcm-input-final-drop").unwrap();
    assert!(ssh < drop && winbox < drop);
    assert!(plan.contains(&format!(
        "in-interface={} src-address={} protocol=tcp dst-port=22",
        config_value("test", "wireguard", "wireguard", "name"),
        cidr_network(&config_value("test", "wireguard", "wireguard", "address"))
    )));
    assert!(plan.contains(&format!(
        "in-interface={} src-address={} protocol=tcp dst-port=8291",
        config_value("test", "wireguard", "wireguard", "name"),
        cidr_network(&config_value("test", "wireguard", "wireguard", "address"))
    )));
    assert!(!plan.contains("comment=mcm-forward-wireguard-lan"));
}

#[test]
fn wireguard_router_management_off_by_default() {
    let (plan, error, success) = wireguard_plan_with_management(false, false, false);
    assert!(success, "{error}");
    assert!(!plan.contains("mcm-input-wireguard-ssh"));
    assert!(!plan.contains("mcm-input-wireguard-winbox"));
}

#[test]
fn wireguard_router_management_does_not_follow_allow_lan() {
    let (plan, error, success) = wireguard_plan_with_management(true, false, false);
    assert!(success, "{error}");
    assert!(!plan.contains("mcm-input-wireguard-ssh"));
    assert!(!plan.contains("mcm-input-wireguard-winbox"));
}

// Незалежні перемикачі SSH/WinBox не мають відкривати інший протокол.
#[test]
fn wireguard_only_ssh_can_be_enabled() {
    let (plan, error, success) = wireguard_plan_with_management(true, true, false);
    assert!(success, "{error}");
    assert!(plan.contains("comment=mcm-input-wireguard-ssh"));
    assert!(!plan.contains("comment=mcm-input-wireguard-winbox"));
}

#[test]
fn wireguard_only_winbox_can_be_enabled() {
    let (plan, error, success) = wireguard_plan_with_management(true, false, true);
    assert!(success, "{error}");
    assert!(!plan.contains("comment=mcm-input-wireguard-ssh"));
    assert!(plan.contains("comment=mcm-input-wireguard-winbox"));
}

// Негативні перевірки змінюють лише тимчасову копію тестового профілю.
#[test]
fn finalization_wireguard_interface_precedes_firewall_reference() {
    // Команди створення інтерфейсу присутні лише в повному плані.
    let (plan, error, success) = wireguard_plan_with_management_mode(true, true, true, "all");
    assert!(success, "{error}");
    let interface = plan
        .find(&format!(
            "/interface wireguard add name={}",
            config_value("test", "wireguard", "wireguard", "name")
        ))
        .unwrap();
    let address = plan
        .find(&format!(
            "/ip address add address={} interface={}",
            config_value("test", "wireguard", "wireguard", "address"),
            config_value("test", "wireguard", "wireguard", "name")
        ))
        .unwrap();
    let firewall = plan.find("comment=mcm-input-wireguard-ssh").unwrap();
    assert!(interface < address && address < firewall);
}

#[test]
fn finalization_disabled_vpn_rejects_stale_ssh_permission() {
    let result = consistency_fixture(
        "disabled-vpn-access",
        "wireguard.toml",
        "allow_ssh = false",
        "allow_ssh = true",
    );
    assert!(!result.status.success());
    assert!(String::from_utf8_lossy(&result.stderr).contains("Finalization"));
}

#[test]
fn finalization_disabled_vpn_rejects_stale_winbox_permission() {
    let result = consistency_fixture(
        "disabled-vpn-winbox",
        "wireguard.toml",
        "allow_winbox = false",
        "allow_winbox = true",
    );
    assert!(!result.status.success());
    assert!(String::from_utf8_lossy(&result.stderr).contains("Finalization"));
}

#[test]
fn release_default_profiles_keep_vpn_management_closed() {
    for router in ["hap-ac", "test"] {
        let output = cli(&["plan", router, "firewall"]);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let plan = String::from_utf8_lossy(&output.stdout);
        assert!(!plan.contains("comment=mcm-input-wireguard-ssh"));
        assert!(!plan.contains("comment=mcm-input-wireguard-winbox"));
    }
}

// Перевірка повного плану обох профілів через новий валідатор RouterOS.
#[test]
fn audit_hardening_preserves_independent_vpn_management() {
    for profile in ["hap-ac", "test"] {
        let out = cli(&["plan", profile]);
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        let plan = String::from_utf8_lossy(&out.stdout);
        assert!(!plan.contains("comment=mcm-input-wireguard-ssh"));
        assert!(!plan.contains("comment=mcm-input-wireguard-winbox"));
        assert!(!cli(&["apply", profile]).status.success());
    }
}

// Перевірки Configuration Integrity працюють на копії профілю.
#[test]
fn integrity_rejects_unknown_wireguard_flag() {
    let out = audit_profile(&[("wireguard.toml", "allow_ssh = false", "allow_sssh = false")]);
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("Configuration Integrity"));
}
