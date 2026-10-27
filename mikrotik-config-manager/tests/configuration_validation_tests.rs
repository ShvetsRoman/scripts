// Тематичні інтеграційні тести. Робочий код не змінено.
#[allow(dead_code)]
mod support;
use support::*;

#[test]
fn consistency_both_profiles_can_build_full_plan() {
    for profile in ["hap-ac", "test"] {
        let result = cli(&["plan", profile]);
        assert!(
            result.status.success(),
            "{profile}: {}",
            String::from_utf8_lossy(&result.stderr)
        );
    }
}

#[test]
fn consistency_selection_cannot_bypass_invalid_config() {
    let result = consistency_fixture(
        "missing-fw",
        "firewall.toml",
        "enabled = true",
        "enabled = false",
    );
    assert!(!result.status.success());
}

// Фіналізація перевіряє порядок залежностей до публікації RouterOS-плану.
#[test]
fn static_audit_keeps_profiles_and_blocked_apply() {
    for profile in ["hap-ac", "test"] {
        let out = cli(&["plan", profile]);
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        assert!(!cli(&["apply", profile]).status.success());
    }
}

// Статичний аудит має відхиляти адреси мережі й broadcast на інтерфейсі керування.
#[test]
fn integrity_preserves_profiles_and_apply_block() {
    for profile in ["hap-ac", "test"] {
        let output = cli(&["plan", profile, "dns"]);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(!cli(&["apply", profile]).status.success());
    }
}

// Негативні сценарії v0.0.23 використовують лише тимчасовий профіль.
#[test]
fn integrity_023_rejects_missing_dhcp_pool_end() {
    let end = config_value("test", "dhcp", "pool.lan", "end");
    let out = audit_profile(&[("dhcp.toml", &format!("end = \"{end}\""), "# end вилучено")]);
    assert!(!out.status.success());
    let error = String::from_utf8_lossy(&out.stderr);
    assert!(
        error.contains("dhcp.toml") && error.contains("missing field `end`"),
        "{error}"
    );
}

#[test]
fn integrity_023_rejects_incomplete_bridge_resource() {
    let out = audit_profile(&[("bridge.toml", "hw = false", "# hw пропущено")]);
    assert!(!out.status.success());
    let error = String::from_utf8_lossy(&out.stderr);
    assert!(
        error.contains("bridge.toml")
            && error.contains("поле 'hw'")
            && error.contains("missing field `hw`"),
        "{error}"
    );
}

#[test]
fn integrity_023_rejects_boolean_as_string_number() {
    let out = audit_profile(&[("firewall.toml", "allow_icmp = true", "allow_icmp = 1")]);
    assert!(!out.status.success());
    let error = String::from_utf8_lossy(&out.stderr);
    assert!(
        error.contains("firewall.toml")
            && error.contains("поле 'allow_icmp'")
            && error.contains("expected a boolean"),
        "{error}"
    );
}

#[test]
fn integrity_023_rejects_zero_wireguard_port() {
    let out = audit_profile(&[("wireguard.toml", "listen_port = 51820", "listen_port = 0")]);
    assert!(!out.status.success());
    let error = String::from_utf8_lossy(&out.stderr);
    assert!(error.contains("wireguard:wireguard.listen_port"), "{error}");
}

#[test]
fn integrity_023_rejects_missing_independent_vpn_flag() {
    let out = audit_profile(&[(
        "wireguard.toml",
        "allow_winbox = false",
        "# allow_winbox пропущено",
    )]);
    assert!(!out.status.success());
    let error = String::from_utf8_lossy(&out.stderr);
    // Після типізації помилок CLI показує джерело діагностики окремими полями.
    // Не вимагаємо старого текстового коду «wireguard.allow_winbox»:
    // перевіряємо файл, назву відсутнього поля та повідомлення Serde.
    assert!(error.contains("Configuration Integrity"), "{error}");
    assert!(error.contains("Профіль 'test'"), "{error}");
    assert!(error.contains("wireguard.toml"), "{error}");
    assert!(error.contains("поле 'allow_winbox'"), "{error}");
    assert!(error.contains("missing field `allow_winbox`"), "{error}");
    // Діагностика не повинна містити реальних значень паролів або ключів.
    assert!(!error.contains("private_key ="), "{error}");
}

#[test]
fn integrity_023_preserves_profiles_and_apply_block() {
    for profile in ["hap-ac", "test"] {
        let plan = cli(&["plan", profile]);
        assert!(
            plan.status.success(),
            "{}",
            String::from_utf8_lossy(&plan.stderr)
        );
        assert!(!cli(&["apply", profile]).status.success());
    }
}

#[test]
fn integrity_023_rejects_quoted_boolean() {
    let out = audit_profile(&[(
        "firewall.toml",
        "allow_icmp = true",
        "allow_icmp = \"true\"",
    )]);
    assert!(!out.status.success());
    let error = String::from_utf8_lossy(&out.stderr);
    assert!(
        error.contains("firewall.toml")
            && error.contains("поле 'allow_icmp'")
            && error.contains("expected a boolean"),
        "{error}"
    );
}

#[test]
fn integrity_023_rejects_wrong_array_type() {
    let servers = config_value("test", "dhcp", "network.lan", "dns_servers");
    let original = format!("dns_servers = {servers}");
    let out = audit_profile(&[("dhcp.toml", &original, "dns_servers = \"invalid\"")]);
    assert!(!out.status.success());
    let error = String::from_utf8_lossy(&out.stderr);
    assert!(
        error.contains("dhcp.toml")
            && error.contains("expected a sequence")
            && error.contains("dns_servers"),
        "{error}"
    );
}

#[test]
fn interface_management_024_preserves_test_management_and_repeatable_plan() {
    let first = cli(&["plan", "test", "interfaces"]);
    let second = cli(&["plan", "test", "interfaces"]);
    assert!(
        first.status.success(),
        "{}",
        String::from_utf8_lossy(&first.stderr)
    );
    assert!(
        second.status.success(),
        "{}",
        String::from_utf8_lossy(&second.stderr)
    );
    assert_eq!(first.stdout, second.stdout);
    let plan = String::from_utf8_lossy(&first.stdout);
    assert!(!plan.contains("[find default-name=ether1] disabled=yes"));
    assert!(!plan.contains("[find default-name=ether2] disabled=yes"));
    assert!(!cli(&["apply", "test"]).status.success());
}

#[test]
fn interface_management_024_has_enabled_and_disabled_commands() {
    let output = cli(&["plan", "hap-ac", "interfaces"]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let plan = String::from_utf8_lossy(&output.stdout);
    assert!(
        plan.contains("[find default-name=sfp1] disabled=yes"),
        "{plan}"
    );
    assert!(
        plan.contains("[find default-name=ether2] disabled=no"),
        "{plan}"
    );
    assert!(!plan.contains("[find default-name=ether1] disabled=yes"));
}
