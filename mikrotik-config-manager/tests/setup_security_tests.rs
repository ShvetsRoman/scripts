// Тематичні інтеграційні тести. Робочий код не змінено.
#[allow(dead_code)]
mod support;
use std::process::Command;
use support::*;

#[test]
fn initial_setup_build_without_secrets_fails_without_creating_rsc() {
    // Тест не повинен залежати від робочого .secrets користувача.
    // Готуємо ізольований профіль без секретів та не змінюємо реальний проєкт.
    let temp = std::env::temp_dir().join(format!(
        "mcm-build-no-secrets-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    ));
    let result = (|| -> Result<(), String> {
        std::fs::create_dir_all(temp.join("routers/test")).map_err(|e| e.to_string())?;
        // Профіль повинен бути структурно повним; у цьому тесті
        // перевіряємо лише відсутність секретів, а не відсутність TOML.
        // Копіюємо тільки декларативні файли, не копіюємо .secrets.
        for entry in std::fs::read_dir("routers/test").map_err(|e| e.to_string())? {
            let entry = entry.map_err(|e| e.to_string())?;
            let path = entry.path();
            if path.extension().is_some_and(|ext| ext == "toml") {
                let name = entry.file_name();
                std::fs::copy(&path, temp.join("routers/test").join(name))
                    .map_err(|e| e.to_string())?;
            }
        }
        std::fs::create_dir_all(temp.join("config")).map_err(|e| e.to_string())?;
        std::fs::create_dir_all(temp.join("locales")).map_err(|e| e.to_string())?;
        for file in ["config/manager.toml", "locales/uk.lang", "locales/en.lang"] {
            std::fs::copy(file, temp.join(file)).map_err(|e| e.to_string())?;
        }
        let output = Command::new(env!("CARGO_BIN_EXE_mikrotik-config-manager"))
            .current_dir(&temp)
            .args(["build", "test", "--name", "validation-test.rsc"])
            .output()
            .map_err(|e| e.to_string())?;
        assert!(
            !output.status.success(),
            "Генерація без .secrets має завершуватися помилкою"
        );
        let error = String::from_utf8_lossy(&output.stderr);
        assert!(
            error.contains("секрет")
                || error.contains("secret")
                || error.contains("ADMIN_PASSWORD"),
            "{error}"
        );
        assert!(!temp.join("routers/test/build/validation-test.rsc").exists());
        Ok(())
    })();
    // Видаляємо виключно ізольовані тестові файли.
    let _ = std::fs::remove_dir_all(&temp);
    result.unwrap();
}

#[test]
fn upload_command_accepts_optional_reset_flag() {
    for params in [
        vec!["upload", "test"],
        vec!["upload", "test", "--reset"],
        vec!["upload", "test", "--name", "missing-test.rsc"],
        vec!["upload", "test", "--reset", "--name", "missing-test.rsc"],
    ] {
        let result = cli(&params);
        assert!(!result.status.success());
        assert!(String::from_utf8_lossy(&result.stderr).contains("Файл для upload відсутній"));
    }
    for params in [
        vec!["upload", "test", "--unknown"],
        vec!["upload", "test", "--name", "../escape.rsc"],
        vec!["upload", "test", "--name", "oops.auto.rsc"],
        vec!["upload", "test", "--reset", "--reset"],
        vec!["build", "test", "--reset"],
    ] {
        assert!(!cli(&params).status.success());
    }
    for old in ["export-rsc", "upload-rsc", "upload-reset"] {
        let legacy = cli(&[old, "test", "setup.rsc"]);
        assert!(!legacy.status.success());
        assert!(String::from_utf8_lossy(&legacy.stderr).contains(old));
    }
}

#[test]
fn bundled_secret_templates_are_empty_and_present() {
    // Перевіряємо незаповнені приклади, не читаючи робочі секрети користувача.
    // Робочі .secrets можуть містити дійсні паролі після налаштування CHR.
    for profile in ["test", "hap-ac"] {
        let path = format!("routers/{profile}/.secrets.example");
        let content = std::fs::read_to_string(&path).unwrap();
        assert!(content.lines().any(|line| line == "ADMIN_PASSWORD="));
        if profile == "hap-ac" {
            assert!(content.lines().any(|line| line == "WIFI_PASSWORD="));
        }
        // Значення в еталонному шаблоні завжди порожні.
        for line in content.lines().filter(|line| !line.trim().starts_with('#')) {
            if let Some((key, value)) = line.split_once('=') {
                if key.ends_with("_PASSWORD") {
                    assert!(value.is_empty(), "Шаблон містить заповнений пароль: {key}");
                }
            }
        }
    }
}

#[test]
fn declared_profile_plan_preserves_configured_lan_and_wan() {
    for profile in ["test", "hap-ac"] {
        let out = cli(&["plan", profile]);
        assert!(
            out.status.success(),
            "{profile}: {}",
            String::from_utf8_lossy(&out.stderr)
        );
        let text = String::from_utf8_lossy(&out.stdout);
        assert!(text.contains(&format!("interface={}", wan_name(profile))));
        assert!(text.contains(&format!(
            "address={} interface={}",
            lan_address(profile),
            bridge_name(profile)
        )));
        assert!(!text.contains("/system reset-configuration"));
        assert!(!text.contains("/import"));
    }
}

#[test]
fn wan_is_not_a_member_of_lan_bridge() {
    for profile in ["test", "hap-ac"] {
        let wan_reference = config_value(profile, "network", "wan", "interface");
        let wan_id = wan_reference
            .strip_prefix("@interfaces.")
            .expect("WAN reference");
        let ports = declared_ids(profile, "bridge", "ports");
        assert!(
            !ports.iter().any(|id| id == wan_id),
            "{profile}: WAN у LAN bridge"
        );
    }
}
