//! Актуальні контракти релізу та перевірок проєкту.
use std::path::Path;

#[test]
fn stable_check_script_preserves_five_stages_and_executable_bit() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let script = root.join("scripts/check.sh");
    let source = std::fs::read_to_string(&script).unwrap();
    for stage in [
        "Cargo fmt",
        "Cargo fmt check",
        "Cargo clippy",
        "Cargo test",
        "TOML documentation",
    ] {
        assert!(source.contains(stage), "відсутній етап: {stage}");
    }
    assert!(!root.join("scripts/compare-golden-rsc.py").exists());
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        assert_ne!(
            std::fs::metadata(script).unwrap().permissions().mode() & 0o111,
            0
        );
    }
}

#[test]
fn stable_readme_and_release_metadata_match() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let readme = std::fs::read_to_string(root.join("README.md")).unwrap();
    let cargo: toml::Value = std::fs::read_to_string(root.join("Cargo.toml"))
        .unwrap()
        .parse()
        .unwrap();
    let version = cargo["package"]["version"].as_str().unwrap();
    assert_eq!(version, env!("CARGO_PKG_VERSION"));
    assert!(
        readme.starts_with(&format!("# MikroTik Configuration Manager — v{version}\n")),
        "заголовок README не відповідає версії Cargo"
    );
}

#[test]
fn stable_documentation_avoids_outdated_fixed_rust_test_counts() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    for relative in ["README.md", "docs/TESTING-AND-SAFETY.md"] {
        let text = std::fs::read_to_string(root.join(relative)).unwrap();
        for old in [
            "354` Rust-тести",
            "357` тестів",
            "358` Rust-тестів",
            "359` Rust-тестів",
        ] {
            assert!(
                !text.contains(old),
                "застаріла кількість тестів у {relative}: {old}"
            );
        }
        assert!(
            text.contains("./scripts/check.sh"),
            "немає команди перевірки: {relative}"
        );
    }
}

// Перевіряємо, що поточний статус документації відповідає Cargo, а не минулому релізу.
#[test]
fn stage6_readme_current_status_matches_cargo_version() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let readme = std::fs::read_to_string(root.join("README.md")).unwrap();
    let version = env!("CARGO_PKG_VERSION");
    assert!(
        readme.contains(&format!("Поточна версія — **v{version} Stable**")),
        "статус README не відповідає Cargo: {version}"
    );
    assert!(
        !readme.contains("Версія v0.0.39 Stable."),
        "застарілий поточний статус"
    );
}

// Тестуємо однакову структуру профілів, не прив'язуючись до значень TOML.
#[test]
fn stage6_declared_profiles_have_independent_complete_toml_sets() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let routers = root.join("routers");
    let required = [
        "bridge.toml",
        "connection.toml",
        "dhcp.toml",
        "dns.toml",
        "firewall.toml",
        "interfaces.toml",
        "ipv6.toml",
        "lists.toml",
        "nat.toml",
        "network.toml",
        "services.toml",
        "system.toml",
        "wireguard.toml",
        "wireless.toml",
    ];
    let mut count = 0;
    for entry in std::fs::read_dir(&routers).unwrap() {
        let entry = entry.unwrap();
        if !entry.file_type().unwrap().is_dir() {
            continue;
        }
        count += 1;
        let path = entry.path();
        let mut names = std::collections::BTreeSet::new();
        for file in std::fs::read_dir(&path).unwrap() {
            let file = file.unwrap();
            if file.path().extension().and_then(|ext| ext.to_str()) == Some("toml") {
                names.insert(file.file_name().to_string_lossy().into_owned());
                let value = std::fs::read_to_string(file.path()).unwrap();
                let _: toml::Value = value.parse().unwrap();
            }
        }
        let expected: std::collections::BTreeSet<_> =
            required.iter().map(|name| (*name).to_string()).collect();
        assert_eq!(names, expected, "неповний набір TOML у {}", path.display());
    }
    assert!(count > 0, "профілі відсутні");
}

// Наявність усіх ключів у двох перекладах без прив'язки до перекладеного тексту.
#[test]
fn stage6_uk_and_en_locale_keys_are_unique_and_equal() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut languages = Vec::new();
    for language in ["uk", "en"] {
        let source =
            std::fs::read_to_string(root.join(format!("locales/{language}.lang"))).unwrap();
        let mut keys = std::collections::BTreeSet::new();
        for line in source.lines().map(str::trim) {
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let (key, value) = line.split_once('=').expect("невірний формат локалізації");
            assert!(!key.trim().is_empty() && !value.trim().is_empty());
            assert!(
                keys.insert(key.to_owned()),
                "дубль ключа {key} у {language}"
            );
        }
        languages.push(keys);
    }
    assert_eq!(languages[0], languages[1], "локалі мають різні ключі");
}
