// Спільні допоміжні функції інтеграційних тестів.
use std::process::Command;

pub(crate) fn only_active_toml(source: &str) -> String {
    source
        .lines()
        .filter(|line| !line.trim_start().starts_with('#'))
        .collect::<Vec<_>>()
        .join("\n")
}

pub(crate) fn read_active_toml(path: impl AsRef<std::path::Path>) -> String {
    only_active_toml(&std::fs::read_to_string(path).unwrap())
}

// Адаптивне читання декларацій: тест очікує значення з TOML, не старі назви.
pub(crate) fn config_value(profile: &str, file: &str, section: &str, key: &str) -> String {
    let source = read_active_toml(format!("routers/{profile}/{file}.toml"));
    let header = format!("[{section}]");
    let body = source
        .split(&header)
        .nth(1)
        .unwrap_or_else(|| panic!("Відсутня секція {section}"));
    let line = body
        .lines()
        .take_while(|line| !line.trim_start().starts_with('['))
        .find(|line| line.trim_start().starts_with(&format!("{key} =")))
        .unwrap_or_else(|| panic!("Відсутнє поле {section}.{key}"));
    line.split_once('=')
        .unwrap()
        .1
        .trim()
        .trim_matches('"')
        .to_string()
}
pub(crate) fn interface_name(profile: &str, id: &str) -> String {
    config_value(profile, "interfaces", &format!("interfaces.{id}"), "name")
}
pub(crate) fn bridge_name(profile: &str) -> String {
    config_value(profile, "bridge", "bridge.lan", "name")
}
pub(crate) fn wan_name(profile: &str) -> String {
    let reference = config_value(profile, "network", "wan", "interface");
    interface_name(
        profile,
        reference
            .strip_prefix("@interfaces.")
            .expect("WAN має посилатися на interfaces"),
    )
}
pub(crate) fn lan_address(profile: &str) -> String {
    config_value(profile, "network", "network.lan", "address")
}
pub(crate) fn cidr_network(address: &str) -> String {
    let (ip, prefix) = address.split_once('/').expect("Для LAN обов'язковий CIDR");
    let ip: std::net::Ipv4Addr = ip.parse().unwrap();
    let prefix: u32 = prefix.parse().unwrap();
    assert!(prefix <= 32);
    let mask = if prefix == 0 {
        0
    } else {
        u32::MAX << (32 - prefix)
    };
    format!(
        "{}/{}",
        std::net::Ipv4Addr::from(u32::from(ip) & mask),
        prefix
    )
}
pub(crate) fn lan_cidr(profile: &str) -> String {
    cidr_network(&lan_address(profile))
}
pub(crate) fn declared_ids(profile: &str, file: &str, prefix: &str) -> Vec<String> {
    let source = read_active_toml(format!("routers/{profile}/{file}.toml"));
    source
        .lines()
        .filter_map(|line| line.trim().strip_prefix(&format!("[{prefix}.")))
        .filter_map(|name| name.strip_suffix(']'))
        .map(str::to_string)
        .collect()
}

pub(crate) fn cli(args: &[&str]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_mikrotik-config-manager"))
        .args(args)
        .output()
        .unwrap()
}

pub(crate) fn declared_ports(config: &str) -> Vec<(String, String)> {
    let mut result = Vec::new();
    let mut current: Option<String> = None;
    for line in config.lines().map(str::trim) {
        if let Some(id) = line
            .strip_prefix("[interfaces.")
            .and_then(|v| v.strip_suffix(']'))
        {
            current = Some(id.to_string());
        } else if let (Some(id), Some(value)) = (&current, line.strip_prefix("name = \"")) {
            if let Some(name) = value.strip_suffix('"') {
                result.push((id.clone(), name.to_string()));
                current = None;
            }
        }
    }
    result
}

// Копіюємо профіль у незалежний тимчасовий каталог для сценаріїв із
// різною кількістю інтерфейсів, не змінюючи живий роутер та .secrets.
pub(crate) fn isolated_interface_plan(
    profile: &str,
    without_sfp: bool,
) -> (std::process::Output, std::process::Output, String) {
    use std::fs;
    let root = std::env::temp_dir().join(format!(
        "mcm-interface-matrix-{}-{:?}-{}",
        std::process::id(),
        std::thread::current().id(),
        profile
    ));
    let destination = root.join("routers").join(profile);
    fs::create_dir_all(&destination).unwrap();
    fs::create_dir_all(root.join("config")).unwrap();
    fs::create_dir_all(root.join("locales")).unwrap();
    fs::copy("config/manager.toml", root.join("config/manager.toml")).unwrap();
    for entry in fs::read_dir("locales").unwrap() {
        let entry = entry.unwrap();
        if entry.path().is_file() {
            fs::copy(entry.path(), root.join("locales").join(entry.file_name())).unwrap();
        }
    }
    for entry in fs::read_dir(format!("routers/{profile}")).unwrap() {
        let entry = entry.unwrap();
        if entry.path().is_file() {
            fs::copy(entry.path(), destination.join(entry.file_name())).unwrap();
        }
    }
    let path = destination.join("interfaces.toml");
    let mut interfaces = fs::read_to_string(&path).unwrap();
    if without_sfp {
        // Прибираємо лише секцію SFP: варіант 7 = 5 Ethernet + 2 Wi-Fi.
        // Кожна секція TOML закінчується початком наступної секції або EOF.
        let mut skipping = false;
        let mut filtered = String::new();
        for line in interfaces.lines() {
            if line.trim() == "[interfaces.sfp1]" {
                skipping = true;
                continue;
            }
            if skipping && line.trim().starts_with('[') {
                skipping = false;
            }
            if !skipping {
                filtered.push_str(line);
                filtered.push('\n');
            }
        }
        interfaces = filtered;
        fs::write(&path, &interfaces).unwrap();
    }
    let root_arg = root.to_str().unwrap();
    let physical = Command::new(env!("CARGO_BIN_EXE_mikrotik-config-manager"))
        .args(["--root", root_arg, "plan", profile, "interfaces"])
        .output()
        .unwrap();
    let full = Command::new(env!("CARGO_BIN_EXE_mikrotik-config-manager"))
        .args(["--root", root_arg, "plan", profile])
        .output()
        .unwrap();
    fs::remove_dir_all(root).unwrap();
    (physical, full, interfaces)
}

pub(crate) fn wg_fixture(tag: &str, config: &str) -> std::path::PathBuf {
    let root = std::env::temp_dir().join(format!(
        "mcm-wg-{tag}-{}-{}",
        std::process::id(),
        std::thread::current()
            .name()
            .unwrap_or("suite")
            .replace(':', "_")
    ));
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(root.join("routers/test")).unwrap();
    std::fs::create_dir_all(root.join("config")).unwrap();
    std::fs::create_dir_all(root.join("locales")).unwrap();
    for file in std::fs::read_dir("routers/test").unwrap() {
        let f = file.unwrap();
        if f.path().is_file() {
            std::fs::copy(f.path(), root.join("routers/test").join(f.file_name())).unwrap();
        }
    }
    for dir in ["config", "locales"] {
        for f in std::fs::read_dir(dir).unwrap() {
            let f = f.unwrap();
            if f.path().is_file() {
                std::fs::copy(f.path(), root.join(dir).join(f.file_name())).unwrap();
            }
        }
    }
    std::fs::write(root.join("routers/test/wireguard.toml"), config).unwrap();
    root
}
pub(crate) fn wg_plan(tag: &str, conf: &str, module: &str) -> std::process::Output {
    let root = wg_fixture(tag, conf);
    let result = Command::new(env!("CARGO_BIN_EXE_mikrotik-config-manager"))
        .args(["--root", root.to_str().unwrap(), "plan", "test", module])
        .output()
        .unwrap();
    std::fs::remove_dir_all(root).unwrap();
    result
}
pub(crate) const WG_OK: &str = "[wireguard]\nenabled = true\nname = \"WG-TEST\"\nlisten_port = 51820\naddress = \"10.77.0.1/24\"\nallow_wan = true\nallow_lan = true\nallow_ssh = false\nallow_winbox = false\nallow_internet = false\n";

pub(crate) fn wireguard_plan_with_management(
    enabled: bool,
    allow_ssh: bool,
    allow_winbox: bool,
) -> (String, String, bool) {
    wireguard_plan_with_management_mode(enabled, allow_ssh, allow_winbox, "firewall")
}

// Окремий режим дозволяє перевірити залежності в повному плані RouterOS.
pub(crate) fn wireguard_plan_with_management_mode(
    enabled: bool,
    allow_ssh: bool,
    allow_winbox: bool,
    module: &str,
) -> (String, String, bool) {
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root = std::env::temp_dir().join(format!("mcm-wg-mgmt-{}-{nonce}", std::process::id()));
    let router_dir = root.join("routers").join("test");
    fs::create_dir_all(&router_dir).unwrap();
    // Тимчасовий проєкт має містити не тільки профіль, а й конфігурацію CLI.
    // Інакше перевірка зупиниться до аналізу WireGuard-правил.
    for dir in ["config", "locales"] {
        let destination = root.join(dir);
        fs::create_dir_all(&destination).unwrap();
        for entry in fs::read_dir(dir).unwrap() {
            let entry = entry.unwrap();
            if entry.path().is_file() {
                fs::copy(entry.path(), destination.join(entry.file_name())).unwrap();
            }
        }
    }
    for entry in fs::read_dir("routers/test").unwrap() {
        let entry = entry.unwrap();
        if entry.path().extension().and_then(|s| s.to_str()) == Some("toml") {
            fs::copy(entry.path(), router_dir.join(entry.file_name())).unwrap();
        }
    }
    let path = router_dir.join("wireguard.toml");
    let source = fs::read_to_string(&path).unwrap();
    let source = source
        .replace("enabled = false", &format!("enabled = {enabled}"))
        .replace("allow_ssh = false", &format!("allow_ssh = {allow_ssh}"))
        .replace(
            "allow_winbox = false",
            &format!("allow_winbox = {allow_winbox}"),
        );
    fs::write(path, source).unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_mikrotik-config-manager"))
        .arg("--root")
        .arg(&root)
        .args(["plan", "test", module])
        .output()
        .unwrap();
    let result = (
        String::from_utf8_lossy(&output.stdout).into_owned(),
        String::from_utf8_lossy(&output.stderr).into_owned(),
        output.status.success(),
    );
    fs::remove_dir_all(root).unwrap();
    result
}

pub(crate) fn consistency_fixture(
    tag: &str,
    file: &str,
    from: &str,
    to: &str,
) -> std::process::Output {
    // Тестові мутації застосовуємо лише до активних рядків TOML.
    // Інакше replacen може змінити перший закоментований приклад.
    let original = read_active_toml(format!("routers/test/{file}"));
    assert!(
        original.contains(from),
        "Тестове поле не знайдене: {file} / {from}"
    );
    let wireguard = read_active_toml("routers/test/wireguard.toml");
    let root = wg_fixture(tag, &wireguard);
    std::fs::write(
        root.join("routers/test").join(file),
        original.replacen(from, to, 1),
    )
    .unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_mikrotik-config-manager"))
        .arg("--root")
        .arg(&root)
        .args(["plan", "test"])
        .output()
        .unwrap();
    std::fs::remove_dir_all(root).unwrap();
    output
}

pub(crate) fn audit_profile(changes: &[(&str, &str, &str)]) -> std::process::Output {
    use std::fs;
    let root = std::env::temp_dir().join(format!(
        "mcm-audit-{}-{:?}",
        std::process::id(),
        std::thread::current().id()
    ));
    fs::create_dir_all(root.join("config")).unwrap();
    fs::create_dir_all(root.join("locales")).unwrap();
    fs::create_dir_all(root.join("routers/test")).unwrap();
    fs::copy("config/manager.toml", root.join("config/manager.toml")).unwrap();
    for item in fs::read_dir("locales").unwrap() {
        let item = item.unwrap();
        if item.path().is_file() {
            fs::copy(item.path(), root.join("locales").join(item.file_name())).unwrap();
        }
    }
    for item in fs::read_dir("routers/test").unwrap() {
        let item = item.unwrap();
        if item.path().is_file() {
            fs::copy(
                item.path(),
                root.join("routers/test").join(item.file_name()),
            )
            .unwrap();
        }
    }
    for (file, old, new) in changes {
        let path = root.join("routers/test").join(file);
        let data = read_active_toml(&path);
        assert!(
            data.contains(old),
            "У файлі {} немає очікуваного значення",
            file
        );
        fs::write(path, data.replacen(old, new, 1)).unwrap();
    }
    let output = Command::new(env!("CARGO_BIN_EXE_mikrotik-config-manager"))
        .args(["--root", root.to_str().unwrap(), "plan", "test", "dns"])
        .output()
        .unwrap();
    fs::remove_dir_all(&root).unwrap();
    output
}
