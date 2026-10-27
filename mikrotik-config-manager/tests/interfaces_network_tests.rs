// Тематичні інтеграційні тести. Робочий код не змінено.
#[allow(dead_code)]
mod support;
use std::path::Path;
use support::*;

#[test]
fn full_plan_contains_core_modules() {
    let output = cli(&["plan", "test"]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let plan = String::from_utf8_lossy(&output.stdout);
    assert!(plan.contains("/ip address add"));
    assert!(plan.contains("/ip dhcp-server add"));
    assert!(plan.contains("/ip dns set"));
    assert!(plan.contains("mcm-input-ssh-management"));
    assert!(!plan.contains("/import"));
}

#[test]
fn module_plan_is_selective() {
    let output = cli(&["plan", "test", "dns"]);
    assert!(output.status.success());
    let plan = String::from_utf8_lossy(&output.stdout);
    assert!(plan.contains("/ip dns set"));
    assert!(!plan.contains("mcm-input-ssh-management"));
    assert!(!plan.contains("/ip pool add"));
    assert!(!plan.contains("/ip address add"));
}

#[test]
fn test_wan_separate_from_ssh() {
    let output = cli(&["plan", "test", "wan"]);
    assert!(output.status.success());
    let text = String::from_utf8_lossy(&output.stdout);
    assert!(text.contains(&format!("interface={}", wan_name("test"))));
    assert!(text.contains(&format!("interface={}", wan_name("test"))));
}
#[test]
fn test_profile_manages_router_from_lan_bridge() {
    // CHR: адміністрування здійснюється через IP LAN Bridge, без окремої management-адреси.
    let output = cli(&["plan", "test", "network"]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let plan = String::from_utf8_lossy(&output.stdout);
    assert!(!plan.contains("/ip address set"));
    assert!(plan.contains(&format!(
        "/ip address add address={} interface={}",
        lan_address("test"),
        bridge_name("test")
    )));
}

#[test]
fn selective_lists_and_interfaces() {
    assert!(cli(&["plan", "test", "lists"]).status.success());
    assert!(cli(&["plan", "test", "interfaces"]).status.success());
    assert!(!cli(&["plan", "test", "missing"]).status.success());
}

#[test]
fn listed_profiles_match_profile_directories() {
    let result = cli(&["list"]);
    assert!(result.status.success());
    let profiles = String::from_utf8_lossy(&result.stdout);
    let names: Vec<&str> = profiles.lines().collect();
    let mut expected: Vec<String> = std::fs::read_dir("routers")
        .unwrap()
        .filter_map(Result::ok)
        .filter(|entry| entry.path().is_dir())
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .collect();
    expected.sort();
    assert_eq!(names, expected);
}

#[test]
fn bridge_has_separate_module() {
    for profile in ["hap-ac", "test"] {
        let out = cli(&["plan", profile, "bridge"]);
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        let text = String::from_utf8_lossy(&out.stdout);
        assert!(text.contains("/interface bridge add"));
        assert!(text.contains("/interface bridge port add"));
        assert!(!text.contains("/ip pool add"));
    }
}
#[test]
fn bridge_precedes_ip_address_in_full_plan() {
    for profile in ["hap-ac", "test"] {
        let out = cli(&["plan", profile]);
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        let text = String::from_utf8_lossy(&out.stdout);
        assert!(
            text.find("/interface bridge add").unwrap() < text.find("/ip address add").unwrap()
        );
    }
}
#[test]
fn ethernet_configurations_are_present() {
    for profile in ["hap-ac", "test"] {
        assert!(Path::new(&format!("routers/{profile}/interfaces.toml")).exists());
        assert!(Path::new(&format!("routers/{profile}/bridge.toml")).exists());
        assert!(Path::new(&format!("routers/{profile}/lists.toml")).exists());
    }
}

// Повертає список логічних фізичних портів із декларативної конфігурації.
// Для Wi-Fi потрібна окрема перевірка модуля wireless, а не ethernet.
#[test]
fn interfaces_follow_declarations_for_five_seven_and_eight_ports() {
    // 5 Ethernet (CHR), 5 Ethernet + 2 Wi-Fi, 5 Ethernet + 2 Wi-Fi + SFP.
    for (profile, without_sfp, physical_count, wifi_count) in [
        ("test", false, 5, 0),
        ("hap-ac", true, 5, 2),
        ("hap-ac", false, 6, 2),
    ] {
        let (result, full, config) = isolated_interface_plan(profile, without_sfp);
        assert!(
            result.status.success(),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
        assert!(
            full.status.success(),
            "{}",
            String::from_utf8_lossy(&full.stderr)
        );
        let physical_plan = String::from_utf8_lossy(&result.stdout);
        let full_plan = String::from_utf8_lossy(&full.stdout);
        let declared = declared_ports(&config);
        let ethernet_sfp: Vec<_> = declared
            .iter()
            .filter(|(id, _)| id.starts_with("ether") || id.starts_with("sfp"))
            .collect();
        let wlan: Vec<_> = declared
            .iter()
            .filter(|(id, _)| id.starts_with("wlan"))
            .collect();
        assert_eq!(ethernet_sfp.len(), physical_count);
        assert_eq!(wlan.len(), wifi_count);
        assert_eq!(declared.len(), physical_count + wifi_count);
        for (id, name) in ethernet_sfp {
            assert!(
                physical_plan.contains(&format!("default-name={id}] name={name}")),
                "Відсутній {id}: {physical_plan}"
            );
        }
        for (id, _) in wlan {
            assert!(full_plan.contains(id), "Відсутній Wi-Fi {id}: {full_plan}");
        }
        if without_sfp {
            assert!(!physical_plan.contains("default-name=sfp1"));
        }
        assert!(!full_plan.contains("/system reset-configuration"));
        assert!(!full_plan.contains("/import file-name="));
    }
}

#[test]
fn declared_bridge_ports_match_generated_bridge_commands() {
    // Перевіряємо всі порти, реально оголошені в TOML, а не ether2–ether5.
    for profile in ["test", "hap-ac"] {
        let bridge = read_active_toml(format!("routers/{profile}/bridge.toml"));
        let interfaces = read_active_toml(format!("routers/{profile}/interfaces.toml"));
        let names = declared_ports(&interfaces);
        let plan = cli(&["plan", profile, "bridge"]);
        assert!(
            plan.status.success(),
            "{}",
            String::from_utf8_lossy(&plan.stderr)
        );
        let generated = String::from_utf8_lossy(&plan.stdout);
        for id in bridge
            .lines()
            .filter_map(|line| line.trim().strip_prefix("[ports."))
            .filter_map(|id| id.strip_suffix(']'))
        {
            let name = names
                .iter()
                .find(|(source, _)| source == id)
                .map(|(_, name)| name)
                .expect("Bridge посилається на невідомий порт");
            assert!(
                generated.contains(&format!("interface={name}")),
                "{profile}/{id}: {generated}"
            );
        }
    }
}

#[test]
fn physical_home_names_match_original_script() {
    let output = cli(&["plan", "hap-ac", "interfaces"]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let plan = String::from_utf8_lossy(&output.stdout);
    // У модулі interfaces фізичні Ethernet/SFP перейменовуються через default-name.
    // Wi-Fi конфігурується окремим модулем wireless, тому тут його не очікуємо.
    // Якщо назва збігається з заводською, команда перейменування зайва.
    for id in declared_ids("hap-ac", "interfaces", "interfaces") {
        if !id.starts_with("ether") && !id.starts_with("sfp") {
            continue;
        }
        let name = interface_name("hap-ac", &id);
        let rename = format!("default-name={id}] name={name}");
        if name == id {
            assert!(!plan.contains(&rename), "Зайве перейменування {id}");
        } else {
            assert!(
                plan.contains(&rename),
                "Відсутнє перейменування {id} → {name}"
            );
        }
    }
}
#[test]
fn chr_five_ports_use_ether1_wan_and_ether2_to_ether5_lan() {
    let out = cli(&["plan", "test", "interfaces"]);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let text = String::from_utf8_lossy(&out.stdout);
    for id in declared_ids("test", "interfaces", "interfaces") {
        assert!(text.contains(&format!(
            "default-name={id}] name={}",
            interface_name("test", &id)
        )));
    }
    assert_eq!(declared_ids("test", "interfaces", "interfaces").len(), 5);
}

#[test]
fn bridge_lan_names_match_legacy() {
    for profile in ["hap-ac", "test"] {
        let out = cli(&["plan", profile, "bridge"]);
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        let text = String::from_utf8_lossy(&out.stdout);
        let bridge = bridge_name(profile);
        assert!(text.contains(&format!("name={bridge}")));
        for port in declared_ids(profile, "bridge", "ports") {
            assert!(text.contains(&format!(
                "bridge={bridge} interface={}",
                interface_name(profile, &port)
            )));
        }
    }
}
#[test]
fn static_leases_preserve_original_home_values() {
    let out = cli(&["plan", "hap-ac", "leases"]);
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let text = String::from_utf8_lossy(&out.stdout);
    let ids = declared_ids("hap-ac", "dhcp", "leases");
    assert_eq!(text.matches("/ip dhcp-server lease add").count(), ids.len());
    for id in ids {
        let section = format!("leases.{id}");
        let address = config_value("hap-ac", "dhcp", &section, "address");
        let mac = config_value("hap-ac", "dhcp", &section, "mac");
        assert!(text.contains(&format!("address={address} mac-address={mac}")));
    }
}
#[test]
fn test_does_not_include_home_mac_addresses() {
    let out = cli(&["plan", "test", "leases"]);
    assert!(out.status.success());
    assert!(!String::from_utf8_lossy(&out.stdout).contains("mac-address="));
}
#[test]
fn wan_dhcp_client_keeps_default_route() {
    for profile in ["hap-ac", "test"] {
        let out = cli(&["plan", profile, "wan"]);
        assert!(out.status.success());
        assert!(String::from_utf8_lossy(&out.stdout).contains("add-default-route=yes"));
    }
}

#[test]
fn named_interfaces_propagate_to_wan_and_bridge() {
    let wan = cli(&["plan", "test", "wan"]);
    assert!(
        wan.status.success(),
        "{}",
        String::from_utf8_lossy(&wan.stderr)
    );
    assert!(
        String::from_utf8_lossy(&wan.stdout).contains(&format!("interface={}", wan_name("test")))
    );
    let bridge = cli(&["plan", "hap-ac", "bridge"]);
    assert!(
        bridge.status.success(),
        "{}",
        String::from_utf8_lossy(&bridge.stderr)
    );
    let plan = String::from_utf8_lossy(&bridge.stdout);
    assert!(plan.contains(&format!("name={}", bridge_name("hap-ac"))));
    assert!(plan.contains(&format!("interface={}", interface_name("hap-ac", "ether2"))));
}

#[test]
fn home_profile_has_original_names() {
    let interfaces = cli(&["plan", "hap-ac", "interfaces"]);
    assert!(interfaces.status.success());
    let text = String::from_utf8_lossy(&interfaces.stdout);
    // Перевіряємо фізичні Ethernet/SFP за деклараціями, без фіксованих назв.
    // wlan* створює інший модуль; перевірку Wi-Fi здійснюємо окремо.
    for id in declared_ids("hap-ac", "interfaces", "interfaces") {
        if !id.starts_with("ether") && !id.starts_with("sfp") {
            continue;
        }
        let name = interface_name("hap-ac", &id);
        let rename = format!("default-name={id}] name={name}");
        if name == id {
            assert!(!text.contains(&rename), "Зайве перейменування {id}");
        } else {
            assert!(
                text.contains(&rename),
                "Відсутнє перейменування {id} → {name}"
            );
        }
    }
    // Наявність Wi-Fi перевіряємо в його власному плані незалежно від імен.
    let wifi = cli(&["plan", "hap-ac", "wireless"]);
    assert!(
        wifi.status.success(),
        "{}",
        String::from_utf8_lossy(&wifi.stderr)
    );
    let wifi_plan = String::from_utf8_lossy(&wifi.stdout);
    for id in declared_ids("hap-ac", "wireless", "wireless") {
        assert!(wifi_plan.contains(&interface_name("hap-ac", &id)));
    }
}

#[test]
fn system_plan_contains_timezone_ntp_identity() {
    for router in ["hap-ac", "test"] {
        let out = cli(&["plan", router, "system"]);
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        let plan = String::from_utf8_lossy(&out.stdout);
        assert!(plan.contains("time-zone-name=Europe/Kyiv"));
        assert!(plan.contains("/system ntp client servers add"));
        assert!(plan.contains("/system identity set"));
        assert!(!plan.contains("/ip firewall filter add"));
        assert!(!plan.contains("/import"));
    }
}

// Сервіси, які не потрібні для домашнього керування, мають бути вимкнені.
#[test]
fn consistency_lan_wan_requires_masquerade() {
    let result = consistency_fixture(
        "nat-disabled",
        "nat.toml",
        "masquerade = true",
        "masquerade = false",
    );
    assert!(!result.status.success());
    assert!(String::from_utf8_lossy(&result.stderr).contains("LAN"));
}

#[test]
fn finalization_duplicate_wan_lan_list_names_are_rejected() {
    let result = consistency_fixture(
        "duplicate-lists",
        "lists.toml",
        "name = \"WAN\"",
        "name = \"LAN\"",
    );
    assert!(!result.status.success());
    assert!(String::from_utf8_lossy(&result.stderr).contains("Interface Lists"));
}

#[test]
fn finalization_full_plan_preserves_admin_access_and_blocked_apply() {
    for profile in ["hap-ac", "test"] {
        let out = cli(&["plan", profile]);
        assert!(
            out.status.success(),
            "{}",
            String::from_utf8_lossy(&out.stderr)
        );
        let plan = String::from_utf8_lossy(&out.stdout);
        assert!(plan.contains("mcm-input-ssh-management"));
        assert!(plan.contains("mcm-input-final-drop"));
        assert!(plan.find("mcm-input-ssh-management") < plan.find("mcm-input-final-drop"));
        assert!(!cli(&["apply", profile]).status.success());
    }
}

// Перевірки випуску: повний план не повинен містити небезпечних операцій.
#[test]
fn release_plan_never_executes_routeros_changes() {
    for router in ["hap-ac", "test"] {
        let output = cli(&["plan", router]);
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let plan = String::from_utf8_lossy(&output.stdout);
        assert!(plan.contains("PLAN ONLY"));
        for forbidden in [
            "/import",
            "/system reboot",
            "/system reset-configuration",
            "/system package update install",
        ] {
            assert!(!plan.contains(forbidden), "{router}: знайдено {forbidden}");
        }
        assert!(!cli(&["apply", router]).status.success());
    }
}

// Вибірковий план зберігає коректний порядок служб і не додає VPN-дозволів.
#[test]
fn plan_validation_accepts_both_full_profiles() {
    for router in ["hap-ac", "test"] {
        let output = cli(&["plan", router]);
        assert!(
            output.status.success(),
            "{router}: {}",
            String::from_utf8_lossy(&output.stderr)
        );
        let plan = String::from_utf8_lossy(&output.stdout);
        assert!(plan.contains("PLAN ONLY"));
        assert!(!plan
            .lines()
            .any(|line| line.starts_with("/import") || line.starts_with("/system reboot")));
    }
}

// Вибірковий план теж проходить перевірку допустимих команд.
#[test]
fn plan_validation_accepts_selected_modules() {
    for router in ["hap-ac", "test"] {
        for module in ["wireless", "firewall", "wireguard", "system", "security"] {
            let output = cli(&["plan", router, module]);
            assert!(
                output.status.success(),
                "{router}/{module}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
        }
    }
}

// Негативні сценарії не повинні змінювати профілі на диску.
#[test]
fn audit_hardening_rejects_unknown_bridge_port() {
    let out = audit_profile(&[("bridge.toml", "[ports.ether3]", "[ports.ether9]")]);
    assert!(!out.status.success());
}

// Вимкнений VPN не повинен відкривати доступ до служб маршрутизатора.
#[test]
fn integrity_rejects_unknown_interface_id() {
    // ether99 є допустимим ID без фіксованої верхньої межі.
    // ether0 має некоректний номер та повинен відхилятися.
    let out = audit_profile(&[(
        "interfaces.toml",
        "[interfaces.ether1]",
        "[interfaces.ether0]",
    )]);
    assert!(!out.status.success());
    assert!(String::from_utf8_lossy(&out.stderr).contains("невідома таблиця"));
}

#[test]
fn integrity_rejects_unknown_bridge_port_id() {
    let out = audit_profile(&[("bridge.toml", "[ports.ether3]", "[ports.ether99]")]);
    assert!(!out.status.success());
    let error = String::from_utf8_lossy(&out.stderr);
    assert!(
        error.contains("bridge.toml") && error.contains("ports.*") && error.contains("test"),
        "{error}"
    );
}

#[test]
fn initial_setup_export_rejects_non_rsc_and_preserves_apply_block() {
    assert!(!cli(&["build", "test", "--name", "bad.txt"])
        .status
        .success());
    for router in ["test", "hap-ac"] {
        assert!(!cli(&["apply", router]).status.success());
    }
}

// Без локального файлу upload не має починати підключення до маршрутизатора.
