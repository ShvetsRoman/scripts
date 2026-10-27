use std::fs;

// Режим початкового налаштування має зберігати маркери помилок і завершення.
#[test]
fn runtime_keeps_error_and_completion_guards() {
    let source = fs::read_to_string("src/setup.rs").unwrap();
    assert!(source.contains("on-error="));
    assert!(source.contains("MCM_SETUP_FAILED"));
    assert!(source.contains("MCM: COMPLETE"));
}

// RESET повинен залишатися явною дією незалежно від користувача SSH.
#[test]
fn reset_is_explicit_and_uses_safe_routeros_switches() {
    let cli = fs::read_to_string("src/cli/commands/upload.rs").unwrap();
    assert!(cli.contains("upload_and_reset"));
    assert!(cli.contains("if reset"));
    let routeros = fs::read_to_string("src/routeros.rs").unwrap();
    assert!(routeros.contains("no-defaults=yes"));
    assert!(routeros.contains("run-after-reset={name}"));
}

// Перевіряємо план кожного профілю, не звертаючись до RouterOS.
#[test]
fn wan_dhcp_cleanup_precedes_declared_client_for_both_profiles() {
    use std::process::Command;
    let binary = env!("CARGO_BIN_EXE_mikrotik-config-manager");
    for profile in ["test", "hap-ac"] {
        let output = Command::new(binary)
            .args(["plan", profile, "wan"])
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}: {}",
            profile,
            String::from_utf8_lossy(&output.stderr)
        );
        let text = String::from_utf8_lossy(&output.stdout);
        let remove = text
            .find("/ip dhcp-client remove [find]")
            .expect("немає очищення DHCP Client");
        let add = text
            .find("/ip dhcp-client add ")
            .expect("немає нового DHCP Client");
        assert!(
            remove < add,
            "{}: очищення має бути перед створенням",
            profile
        );
        assert_eq!(text.matches("/ip dhcp-client remove [find]").count(), 1);
    }
}
