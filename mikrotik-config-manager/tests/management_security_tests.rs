// Тематичні інтеграційні тести. Робочий код не змінено.
#[allow(dead_code)]
mod support;
use support::*;

#[test]
fn home_management_stays_on_lan_bridge() {
    let output = cli(&["plan", "hap-ac", "firewall"]);
    assert!(output.status.success());
    assert!(String::from_utf8_lossy(&output.stdout)
        .contains(&format!("in-interface={}", bridge_name("hap-ac"))));
}
#[test]
fn home_shared_management_ip_is_allowed() {
    // hAP ac: LAN і Management працюють через той самий bridge та IP.
    let output = cli(&["plan", "hap-ac", "network"]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let plan = String::from_utf8_lossy(&output.stdout);
    assert!(plan.contains(&bridge_name("hap-ac")));
    assert!(plan.contains(&lan_address("hap-ac")));
}

#[test]
fn unnecessary_services_are_disabled() {
    let out = cli(&["plan", "hap-ac", "services"]);
    assert!(out.status.success());
    let plan = String::from_utf8_lossy(&out.stdout);
    for name in [
        "telnet",
        "ftp",
        "www",
        "www-ssl",
        "api",
        "api-ssl",
        "reverse-proxy",
    ] {
        assert!(plan.contains(&format!("name={name}] disabled=yes")));
    }
}

// Регресії декларативної політики безпеки.
#[test]
fn system_security_plans_exist_for_both_profiles() {
    for profile in ["hap-ac", "test"] {
        let output = cli(&["plan", profile, "security"]);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let text = String::from_utf8_lossy(&output.stdout);
        assert!(text.contains("/ip ssh set strong-crypto=yes"));
        assert!(text.contains("/tool mac-server mac-winbox set allowed-interface-list="));
        let channel = config_value(profile, "system", "updates", "channel");
        assert!(text.contains(&format!("/system package update set channel={channel}")));
        assert!(!text.contains("/user add"));
        assert!(!text.contains("/system reboot"));
        assert!(!text.contains("/system package update install"));
    }
}
#[test]
fn security_is_only_in_selected_or_full_plan() {
    let security = cli(&["plan", "test", "security"]);
    assert!(security.status.success());
    let text = String::from_utf8_lossy(&security.stdout);
    assert!(!text.contains("/ip firewall filter add"));
    let dns = cli(&["plan", "test", "dns"]);
    assert!(dns.status.success());
    assert!(!String::from_utf8_lossy(&dns.stdout).contains("/ip ssh set strong-crypto=yes"));
    let all = cli(&["plan", "test"]);
    assert!(all.status.success());
    assert!(String::from_utf8_lossy(&all.stdout).contains("/ip ssh set strong-crypto=yes"));
}
#[test]
fn user_management_definitions_keep_secrets_separate() {
    for profile in ["hap-ac", "test"] {
        let path = format!("routers/{profile}/system.toml");
        let content = std::fs::read_to_string(path).unwrap();
        assert!(content.contains("auto_reboot = false"));
        assert!(!content.contains("password ="));
    }
}

// WireGuard залишається вимкненим, поки користувач не вкаже ключі peers.
#[test]
fn hardening_preserves_read_only_profiles_and_separate_management() {
    for profile in ["hap-ac", "test"] {
        let full = cli(&["plan", profile]);
        assert!(
            full.status.success(),
            "{}",
            String::from_utf8_lossy(&full.stderr)
        );
        let plan = String::from_utf8_lossy(&full.stdout);
        assert!(!plan.contains("/system reboot"));
        assert!(!cli(&["apply", profile]).status.success());
    }
    let (ssh, error, success) = wireguard_plan_with_management(true, true, false);
    assert!(success, "{error}");
    assert!(ssh.contains("mcm-input-wireguard-ssh"));
    assert!(!ssh.contains("mcm-input-wireguard-winbox"));
}

// Кожен негативний тест створює повну незалежну копію конфігурації.
// Жодна команда не звертається до справжнього MikroTik.
#[test]
fn static_audit_rejects_inconsistent_management_on_lan() {
    // Керування LAN Bridge не може мати адресу з іншої мережі.
    let original = lan_address("test");
    let changed = "203.0.113.130/25";
    let old_line = format!("address = \"{original}\"");
    let new_line = format!("address = \"{changed}\"");
    let out = audit_profile(&[("network.toml", &old_line, &new_line)]);
    assert!(!out.status.success());
    let error = String::from_utf8_lossy(&out.stderr);
    assert!(
        error.contains("Management") || error.contains("network") || error.contains("LAN"),
        "{error}"
    );
}

#[test]
fn audit_hardening_rejects_management_broadcast() {
    // Адреса broadcast заборонена і для Management на LAN.
    // В обох оголошеннях LAN/Management однакова адреса; змінюємо їх
    // одночасно, щоб перевірка спрацювала саме на network/broadcast,
    // а не на неузгодженості двох адрес.
    let network = read_active_toml("routers/test/network.toml");
    let source = network
        .lines()
        .find_map(|line| line.trim().strip_prefix("address = "))
        .and_then(|value| value.trim().strip_prefix('"'))
        .and_then(|value| value.strip_suffix('"'))
        .unwrap();
    let (ip, prefix) = source.split_once('/').unwrap();
    let octets: Vec<u8> = ip.split('.').map(|part| part.parse().unwrap()).collect();
    assert_eq!(octets.len(), 4);
    // Профіль використовує /24; тест не залежить від конкретної адреси.
    assert_eq!(prefix, "24");
    let broadcast = format!("{}.{}.{}.255/{prefix}", octets[0], octets[1], octets[2]);
    let gateway_old = format!("gateway = \"{ip}\"");
    let gateway_new = format!(
        "gateway = \"{}.{}.{}.255\"",
        octets[0], octets[1], octets[2]
    );
    let changes = [
        ("network.toml", source, broadcast.as_str()),
        ("network.toml", source, broadcast.as_str()),
        // DHCP gateway має відповідати LAN-адресі, інакше перевірка
        // зупиниться раніше та не дійде до аудиту network/broadcast.
        ("dhcp.toml", gateway_old.as_str(), gateway_new.as_str()),
    ];
    let out = audit_profile(&changes);
    assert!(!out.status.success());
    let error = String::from_utf8_lossy(&out.stderr);
    assert!(error.contains("network/broadcast"), "{error}");
}
