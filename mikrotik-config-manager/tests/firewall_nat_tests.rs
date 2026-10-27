// Тематичні інтеграційні тести. Робочий код не змінено.
#[allow(dead_code)]
mod support;
use support::*;

#[test]
fn firewall_module_is_selective() {
    let output = cli(&["plan", "test", "firewall"]);
    assert!(output.status.success());
    let plan = String::from_utf8_lossy(&output.stdout);
    assert!(plan.contains("chain=input"));
    assert!(plan.contains("chain=forward"));
    assert!(!plan.contains("/ip pool add"));
    assert!(!plan.contains("/ip dns set"));
}

#[test]
fn ssh_allow_precedes_final_input_drop() {
    let output = cli(&["plan", "test", "firewall"]);
    assert!(output.status.success());
    let plan = String::from_utf8_lossy(&output.stdout);
    let allow = plan.find("comment=mcm-input-ssh-management").unwrap();
    let drop = plan.find("comment=mcm-input-final-drop").unwrap();
    assert!(allow < drop);
    assert!(plan.contains(&format!(
        "in-interface={} src-address={}",
        bridge_name("test"),
        lan_cidr("test")
    )));
}

#[test]
fn forward_state_allow_precedes_drop() {
    let output = cli(&["plan", "test", "firewall"]);
    assert!(output.status.success());
    let plan = String::from_utf8_lossy(&output.stdout);
    assert!(
        plan.find("comment=mcm-forward-established").unwrap()
            < plan.find("comment=mcm-forward-final-drop").unwrap()
    );
}

#[test]
fn firewall_plan_never_contains_import_or_management_address_set() {
    let output = cli(&["plan", "test", "firewall"]);
    assert!(output.status.success());
    let plan = String::from_utf8_lossy(&output.stdout);
    assert!(!plan.contains("/import"));
    assert!(!plan.contains("/ip address set"));
    assert!(!plan.contains("/ip service set"));
}

#[test]
fn interface_lists_precede_firewall_in_plan() {
    for name in ["hap-ac", "test"] {
        let out = cli(&["plan", name]);
        assert!(out.status.success());
        let text = String::from_utf8_lossy(&out.stdout);
        assert!(
            text.find("/interface list add name=WAN").unwrap()
                < text.find("comment=mcm-forward-lan-to-wan").unwrap()
        );
        assert!(
            text.find("comment=mcm-forward-lan-to-wan").unwrap()
                < text.find("comment=mcm-forward-final-drop").unwrap()
        );
        assert!(
            text.find("comment=mcm-input-dns-udp").unwrap()
                < text.find("comment=mcm-input-final-drop").unwrap()
        );
    }
}

#[test]
fn optional_fasttrack_starts_disabled() {
    let out = cli(&["plan", "test", "firewall"]);
    assert!(out.status.success());
    assert!(!String::from_utf8_lossy(&out.stdout).contains("action=fasttrack-connection"));
}

#[test]
fn original_names_propagate_to_wan_lists_and_firewall() {
    for profile in ["hap-ac", "test"] {
        for (module, name) in [
            ("wan", format!("interface={}", wan_name(profile))),
            ("lists", format!("interface={}", wan_name(profile))),
            ("firewall", "chain=input".to_string()),
        ] {
            let out = cli(&["plan", profile, module]);
            assert!(
                out.status.success(),
                "{profile}/{module}: {}",
                String::from_utf8_lossy(&out.stderr)
            );
            assert!(String::from_utf8_lossy(&out.stdout).contains(&name));
        }
    }
}

#[test]
fn management_ssh_and_winbox_limited_to_management_network() {
    for profile in ["hap-ac", "test"] {
        let output = cli(&["plan", profile, "firewall"]);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let text = String::from_utf8_lossy(&output.stdout);
        assert!(text.contains("comment=mcm-input-ssh-management"));
        assert!(text.contains("dst-port=8291"));
        assert!(text.contains("comment=mcm-input-winbox-management"));
        assert!(text.contains("comment=mcm-input-wan-new-drop"));
        assert!(text.contains("comment=mcm-forward-wan-new-drop"));
        assert!(
            text.find("mcm-forward-lan-to-wan").unwrap()
                < text.find("mcm-forward-final-drop").unwrap()
        );
    }
}
#[test]
fn nat_uses_configured_wan_list_and_no_manual_wan_interface() {
    for profile in ["hap-ac", "test"] {
        let output = cli(&["plan", profile, "nat"]);
        assert!(output.status.success());
        let text = String::from_utf8_lossy(&output.stdout);
        assert!(text.contains("out-interface-list=WAN"));
        assert!(!text.contains("out-interface=00_WAN"));
    }
}
#[test]
fn fasttrack_is_optional_and_comes_before_stateful_accept() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for profile in ["hap-ac", "test"] {
        let config =
            std::fs::read_to_string(root.join("routers").join(profile).join("firewall.toml"))
                .unwrap();
        assert!(config.contains("fasttrack = false"));
    }
}

// Схему ресурсів перевіряємо без підключення до RouterOS.
#[test]
fn services_and_firewall_ports_are_consistent() {
    for router in ["hap-ac", "test"] {
        let service = cli(&["plan", router, "services"]);
        assert!(
            service.status.success(),
            "{}",
            String::from_utf8_lossy(&service.stderr)
        );
        let service = String::from_utf8_lossy(&service.stdout);
        assert!(service.contains("name=ssh] disabled=no port=22"));
        assert!(service.contains("name=winbox] disabled=no port=8291"));
        assert!(service.contains("discover-interface-list=LAN"));
        let firewall = cli(&["plan", router, "firewall"]);
        assert!(
            firewall.status.success(),
            "{}",
            String::from_utf8_lossy(&firewall.stderr)
        );
        let firewall = String::from_utf8_lossy(&firewall.stdout);
        assert!(firewall.contains("dst-port=22"));
        assert!(firewall.contains("dst-port=8291"));
    }
}

// System не залежить від зміни параметрів мережі та не торкається apply.
#[test]
fn consistency_forward_final_drop_is_required() {
    let result = consistency_fixture(
        "forward-drop",
        "firewall.toml",
        "forward_default_drop = true",
        "forward_default_drop = false",
    );
    assert!(!result.status.success());
    assert!(String::from_utf8_lossy(&result.stderr).contains("DROP"));
}

#[test]
fn static_audit_rejects_dhcp_without_firewall_permission() {
    let out = audit_profile(&[(
        "firewall.toml",
        "allow_lan_dhcp = true",
        "allow_lan_dhcp = false",
    )]);
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("DHCP Server потребує"));
}

#[test]
fn integrity_rejects_unknown_firewall_field() {
    let out = audit_profile(&[(
        "firewall.toml",
        "allow_icmp = true",
        "allow_icmp = true\nallow_icmpp = true",
    )]);
    assert!(!out.status.success());
    let error = String::from_utf8_lossy(&out.stderr);
    assert!(
        error.contains("firewall.toml")
            && error.contains("unknown field")
            && error.contains("allow_icmpp"),
        "{error}"
    );
}

#[test]
fn reverse_proxy_is_disabled_for_both_home_profiles() {
    for profile in ["test", "hap-ac"] {
        let output = cli(&["plan", profile, "services"]);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let plan = String::from_utf8_lossy(&output.stdout);
        assert!(plan.contains("/ip service set [find name=reverse-proxy] disabled=yes"));
        assert!(plan.contains("/ip service set [find name=ssh] disabled=no"));
        assert!(plan.contains("/ip service set [find name=winbox] disabled=no"));
        assert!(!plan.contains("/ip service set [find name=reverse-proxy] disabled=no"));
    }
}

// Синтетичні профілі: тестові значення не накладають обмежень на hap-ac/test.
fn synthetic_firewall_plan(
    tag: &str,
    enabled: bool,
    drop_new_wan: bool,
    brute: bool,
    icmp: i64,
) -> std::process::Output {
    use std::fs;
    let source = fs::read_to_string("routers/test/wireguard.toml").unwrap();
    let root = wg_fixture(tag, &source);
    let file = root.join("routers/test/firewall.toml");
    let original = fs::read_to_string(&file).unwrap();
    let mut cfg: toml::Value = toml::from_str(&original).unwrap();
    let firewall = cfg.get_mut("firewall").unwrap().as_table_mut().unwrap();
    firewall.insert("enabled".into(), toml::Value::Boolean(enabled));
    firewall.insert("drop_new_wan".into(), toml::Value::Boolean(drop_new_wan));
    firewall.insert("brute_force_enabled".into(), toml::Value::Boolean(brute));
    firewall.insert("icmp_limit_per_second".into(), toml::Value::Integer(icmp));
    fs::write(&file, toml::to_string(&cfg).unwrap()).unwrap();
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_mikrotik-config-manager"))
        .arg("--root")
        .arg(&root)
        .args(["plan", "test", "firewall"])
        .output()
        .unwrap();
    fs::remove_dir_all(&root).unwrap();
    output
}

#[test]
fn drop_new_wan_requires_enabled_firewall() {
    let invalid = synthetic_firewall_plan("drop-disabled", false, true, false, 0);
    assert!(!invalid.status.success());
    let stderr = String::from_utf8_lossy(&invalid.stderr);
    assert!(
        stderr.contains("module_firewall_drop_requires_enabled")
            && stderr.contains("firewall.toml"),
        "{stderr}"
    );

    let enabled = synthetic_firewall_plan("drop-enabled", true, true, false, 0);
    assert!(
        enabled.status.success(),
        "{}",
        String::from_utf8_lossy(&enabled.stderr)
    );
    assert!(String::from_utf8_lossy(&enabled.stdout).contains("comment=mcm-input-wan-new-drop"));

    let disabled = synthetic_firewall_plan("drop-off", true, false, false, 0);
    assert!(
        disabled.status.success(),
        "{}",
        String::from_utf8_lossy(&disabled.stderr)
    );
    assert!(!String::from_utf8_lossy(&disabled.stdout).contains("comment=mcm-input-wan-new-drop"));
}

#[test]
fn synthetic_wan_protection_keeps_input_forward_and_lan_order() {
    let output = synthetic_firewall_plan("wan-guard", true, true, true, 10);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let text = String::from_utf8_lossy(&output.stdout);
    let lines: Vec<&str> = text.lines().collect();
    let at = |needle: &str| {
        lines
            .iter()
            .position(|line| line.contains(&format!("comment={needle}")))
            .unwrap_or_else(|| panic!("Не згенеровано правило {needle}"))
    };
    assert!(at("mcm-input-established") < at("mcm-input-invalid"));
    assert!(at("mcm-input-ssh-management") < at("mcm-bf-drop"));
    assert!(at("mcm-bf-drop") < at("mcm-bf-stage1"));
    assert!(at("mcm-bf-stage1") < at("mcm-input-icmp-lan"));
    assert!(at("mcm-input-icmp-lan") < at("mcm-input-icmp-wan-limit"));
    assert!(at("mcm-input-icmp-wan-limit") < at("mcm-input-icmp-wan-excess"));
    assert!(at("mcm-input-icmp-wan-excess") < at("mcm-input-wan-new-drop"));
    assert!(at("mcm-input-wan-new-drop") < at("mcm-input-final-drop"));
    assert!(at("mcm-forward-lan-to-wan") < at("mcm-forward-final-drop"));
    for line in lines.iter().filter(|line| line.contains("comment=mcm-bf-")) {
        assert!(line.contains("in-interface-list=WAN"), "{line}");
    }
    assert!(lines
        .iter()
        .any(|line| line.contains("comment=mcm-input-icmp-wan-limit")
            && line.contains("limit=10/1s,10")));
    assert!(lines
        .iter()
        .any(|line| line.contains("comment=mcm-input-icmp-lan")
            && line.contains("in-interface-list=LAN")
            && !line.contains("limit=")));
}

// Завершальний регресійний аудит: синтетичні TOML, незалежні від назв моделей.
#[test]
fn wan_bruteforce_has_complete_ordered_wan_only_stage_chain() {
    let output = synthetic_firewall_plan("bf-stage-chain", true, true, true, 10);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    let lines: Vec<&str> = stdout.lines().collect();
    let find = |comment: &str| -> usize {
        lines
            .iter()
            .position(|line| line.contains(&format!("comment={comment}")))
            .unwrap_or_else(|| panic!("Відсутнє правило {comment}"))
    };
    let stages = [
        "mcm-bf-drop",
        "mcm-bf-blacklist",
        "mcm-bf-stage3",
        "mcm-bf-stage2",
        "mcm-bf-stage1",
    ];
    for pair in stages.windows(2) {
        assert!(
            find(pair[0]) < find(pair[1]),
            "Некоректний порядок {} → {}",
            pair[0],
            pair[1]
        );
    }
    assert!(find("mcm-input-ssh-management") < find(stages[0]));
    assert!(find(stages[4]) < find("mcm-input-wan-new-drop"));
    assert!(find("mcm-input-wan-new-drop") < find("mcm-input-final-drop"));
    for rule in lines.iter().filter(|line| line.contains("comment=mcm-bf-")) {
        assert!(rule.contains("chain=input"), "{rule}");
        assert!(
            rule.contains("in-interface-list=WAN"),
            "LAN не може потрапляти до blacklist: {rule}"
        );
        assert!(rule.contains("protocol=tcp"), "{rule}");
        assert!(rule.contains("dst-port=22,8291"), "{rule}");
    }
    assert!(lines
        .iter()
        .any(|line| line.contains("comment=mcm-bf-blacklist")
            && line.contains("address-list-timeout=1d")));
    assert!(lines
        .iter()
        .any(|line| line.contains("comment=mcm-bf-stage1")
            && line.contains("address-list-timeout=5m")));
    let lan_icmp = lines
        .iter()
        .find(|line| line.contains("comment=mcm-input-icmp-lan"))
        .unwrap();
    assert!(lan_icmp.contains("in-interface-list=LAN") && !lan_icmp.contains("limit="));
    let wan_icmp = lines
        .iter()
        .find(|line| line.contains("comment=mcm-input-icmp-wan-limit"))
        .unwrap();
    assert!(wan_icmp.contains("in-interface-list=WAN") && wan_icmp.contains("limit=10/1s,10"));
    assert!(find("mcm-input-icmp-lan") < find("mcm-input-icmp-wan-limit"));
    assert!(find("mcm-input-icmp-wan-limit") < find("mcm-input-icmp-wan-excess"));
    assert!(find("mcm-forward-lan-to-wan") < find("mcm-forward-wan-new-drop"));
    assert!(find("mcm-forward-wan-new-drop") < find("mcm-forward-final-drop"));
}

#[test]
fn synthetic_optional_wan_protection_does_not_generate_stale_rules() {
    let output = synthetic_firewall_plan("wan-opt-out", true, false, false, 0);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(!stdout.contains("comment=mcm-bf-"));
    assert!(!stdout.contains("comment=mcm-input-wan-new-drop"));
    assert!(!stdout.contains("comment=mcm-forward-wan-new-drop"));
    assert!(!stdout.contains("comment=mcm-input-icmp-wan-limit"));
    assert!(!stdout.contains("comment=mcm-input-icmp-wan-excess"));
    assert!(stdout.contains("comment=mcm-input-icmp"));
    assert!(stdout.contains("comment=mcm-input-final-drop"));
    assert!(stdout.contains("comment=mcm-forward-final-drop"));
}

#[test]
fn synthetic_invalid_wan_icmp_limit_returns_typed_diagnostic() {
    let output = synthetic_firewall_plan("icmp-limit-invalid", true, true, false, 1001);
    assert!(!output.status.success());
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("module_firewall_icmp_limit") && stderr.contains("firewall.toml"),
        "{stderr}"
    );
}

// Stage 2: ізольовані параметри Firewall, незалежні від поточного hap-ac/test.
#[test]
fn stage2_wan_bruteforce_toggle_does_not_affect_management_access() {
    for brute in [false, true] {
        let output = synthetic_firewall_plan(
            if brute {
                "stage2-brute-on"
            } else {
                "stage2-brute-off"
            },
            true,
            true,
            brute,
            10,
        );
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let text = String::from_utf8_lossy(&output.stdout);
        let management = text.find("comment=mcm-input-ssh-management").unwrap();
        let wan_drop = text.find("comment=mcm-input-wan-new-drop").unwrap();
        assert!(management < wan_drop);
        assert_eq!(text.contains("comment=mcm-bf-stage1"), brute);
        assert_eq!(text.contains("comment=mcm-bf-drop"), brute);
        for rule in text.lines().filter(|line| line.contains("comment=mcm-bf-")) {
            assert!(rule.contains("in-interface-list=WAN"), "{rule}");
        }
    }
}

#[test]
fn stage2_wan_icmp_limit_is_declarative_without_lan_throttling() {
    for limit in [1, 10, 50] {
        let output =
            synthetic_firewall_plan(&format!("stage2-icmp-{limit}"), true, true, false, limit);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let text = String::from_utf8_lossy(&output.stdout);
        let lan = text
            .lines()
            .find(|line| line.contains("comment=mcm-input-icmp-lan"))
            .unwrap();
        let wan = text
            .lines()
            .find(|line| line.contains("comment=mcm-input-icmp-wan-limit"))
            .unwrap();
        assert!(lan.contains("in-interface-list=LAN") && !lan.contains("limit="));
        assert!(wan.contains("in-interface-list=WAN"));
        assert!(wan.contains(&format!("limit={limit}/1s,{limit}")), "{wan}");
        assert!(
            text.find("comment=mcm-input-icmp-lan").unwrap()
                < text.find("comment=mcm-input-icmp-wan-limit").unwrap()
        );
        assert!(
            text.find("comment=mcm-input-icmp-wan-limit").unwrap()
                < text.find("comment=mcm-input-icmp-wan-excess").unwrap()
        );
    }
}
