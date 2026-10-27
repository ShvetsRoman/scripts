// Тематичні інтеграційні тести. Робочий код не змінено.
#[allow(dead_code)]
mod support;
use std::process::Command;
use support::*;

#[test]
fn wireless_legacy_plan_has_two_radios_and_no_secret() {
    let output = cli(&["plan", "hap-ac", "wireless"]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let plan = String::from_utf8_lossy(&output.stdout);
    assert!(plan.contains("/interface wireless security-profiles add"));
    for id in declared_ids("hap-ac", "wireless", "wireless") {
        assert!(plan.contains(&interface_name("hap-ac", &id)));
    }
    assert!(plan.contains(&format!("bridge={}", bridge_name("hap-ac"))));
    assert!(!plan.contains("pre-shared-key="));
    assert!(!plan.contains("/import"));
}

#[test]
fn full_hap_plan_contains_wifi_after_bridge() {
    let output = cli(&["plan", "hap-ac"]);
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let plan = String::from_utf8_lossy(&output.stdout);
    assert!(
        plan.find("/interface bridge add").unwrap()
            < plan
                .find("/interface wireless security-profiles add")
                .unwrap()
    );
}

// Порти керування повинні надходити з одного джерела та збігатися з Firewall.
#[test]
fn hardening_wireless_rejects_injected_ssid() {
    let source = read_active_toml("routers/hap-ac/wireless.toml");
    let ssid = config_value("hap-ac", "wireless", "wireless.wlan1", "ssid");
    let old = format!("ssid = \"{ssid}\"");
    assert!(source.contains(&old));
    let root = std::env::temp_dir().join(format!("mcm-wifi-hardening-{}", std::process::id()));
    if root.exists() {
        std::fs::remove_dir_all(&root).unwrap();
    }
    std::fs::create_dir_all(root.join("routers/hap-ac")).unwrap();
    std::fs::create_dir_all(root.join("config")).unwrap();
    std::fs::create_dir_all(root.join("locales")).unwrap();
    std::fs::copy("config/manager.toml", root.join("config/manager.toml")).unwrap();
    for locale in ["uk.lang", "en.lang"] {
        std::fs::copy(
            format!("locales/{locale}"),
            root.join("locales").join(locale),
        )
        .unwrap();
    }
    for entry in std::fs::read_dir("routers/hap-ac").unwrap() {
        let entry = entry.unwrap();
        if entry
            .path()
            .extension()
            .and_then(|extension| extension.to_str())
            == Some("toml")
        {
            std::fs::copy(
                entry.path(),
                root.join("routers/hap-ac").join(entry.file_name()),
            )
            .unwrap();
        }
    }
    std::fs::write(
        root.join("routers/hap-ac/wireless.toml"),
        source.replacen(&old, "ssid = \"BAD;reboot\"", 1),
    )
    .unwrap();
    let result = Command::new(env!("CARGO_BIN_EXE_mikrotik-config-manager"))
        .arg("--root")
        .arg(&root)
        .args(["plan", "hap-ac", "wireless"])
        .output()
        .unwrap();
    std::fs::remove_dir_all(root).unwrap();
    assert!(!result.status.success());
}
