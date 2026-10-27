// Структуровані помилки профілів: першопричина I/O і TOML не втрачається.
#[derive(Debug)]
pub enum ProfileError {
    InvalidName,
    MissingProfile {
        name: String,
    },
    InvalidDirectory,
    MissingFile {
        name: String,
        file: String,
        source: std::io::Error,
    },
    UnsafeFile {
        name: String,
        file: String,
    },
    ReadFile {
        name: String,
        file: String,
        source: std::io::Error,
    },
    InvalidToml {
        detail: String,
        source: toml::de::Error,
    },
    ReadRouters {
        source: std::io::Error,
    },
    ReadEntry {
        source: std::io::Error,
    },
}
impl std::fmt::Display for ProfileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidName => f.write_str("Invalid router name"),
            Self::MissingProfile { name } => write!(f, "Router profile not found: {name}"),
            Self::InvalidDirectory => {
                f.write_str("routers/ повинен бути звичайним каталогом, не symlink")
            }
            Self::MissingFile { name, file, .. } => {
                write!(f, "Router profile {name}: відсутній {file}")
            }
            Self::UnsafeFile { name, file } => write!(
                f,
                "Router profile {name}: небезпечний або некоректний {file}"
            ),
            Self::ReadFile { name, file, source } => {
                write!(f, "Router profile {name}: {file}: {source}")
            }
            Self::InvalidToml { detail, .. } => f.write_str(detail),
            Self::ReadRouters { source } => write!(f, "Не вдалося прочитати routers/: {source}"),
            Self::ReadEntry { source } => write!(f, "{source}"),
        }
    }
}
impl std::error::Error for ProfileError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::MissingFile { source, .. }
            | Self::ReadFile { source, .. }
            | Self::ReadRouters { source }
            | Self::ReadEntry { source } => Some(source),
            Self::InvalidToml { source, .. } => Some(source),
            _ => None,
        }
    }
}

use std::path::{Path, PathBuf};

// Усі профілі мають однаковий набір обов'язкових декларативних файлів.
const REQUIRED: [&str; 14] = [
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

fn valid_key(value: &str) -> bool {
    !value.is_empty()
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-'))
}

pub fn config_root() -> PathBuf {
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

// Перевіряємо форму профілю до виконання CLI-команди, не читаючи секретів.
fn validate_profile(dir: &Path, name: &str) -> Result<(), ProfileError> {
    if !dir.is_dir() || dir.is_symlink() {
        return Err(ProfileError::MissingProfile { name: name.into() });
    }
    for file in REQUIRED {
        let path = dir.join(file);
        let metadata =
            std::fs::symlink_metadata(&path).map_err(|source| ProfileError::MissingFile {
                name: name.into(),
                file: file.into(),
                source,
            })?;
        if !metadata.file_type().is_file() {
            return Err(ProfileError::UnsafeFile {
                name: name.into(),
                file: file.into(),
            });
        }
        let content = std::fs::read_to_string(&path).map_err(|source| ProfileError::ReadFile {
            name: name.into(),
            file: file.into(),
            source,
        })?;
        content
            .parse::<toml::Value>()
            .map_err(|source| ProfileError::InvalidToml {
                detail: mikrotik_config_manager::typed_config::format_toml_error(
                    &path, &content, &source,
                ),
                source,
            })?;
    }
    Ok(())
}

// Не дозволяємо routers/ перенаправляти в інший каталог через symlink.
fn profiles_root(root: &Path) -> Result<PathBuf, ProfileError> {
    let dir = root.join("routers");
    let meta =
        std::fs::symlink_metadata(&dir).map_err(|source| ProfileError::ReadRouters { source })?;
    if !meta.file_type().is_dir() {
        return Err(ProfileError::InvalidDirectory);
    }
    Ok(dir)
}

// Профілі визначаються за структурою routers/, а не за назвами моделей.
pub fn discover_profiles(root: &Path) -> Result<Vec<String>, ProfileError> {
    let mut profiles = Vec::new();
    let entries = std::fs::read_dir(profiles_root(root)?)
        .map_err(|source| ProfileError::ReadRouters { source })?;
    for entry in entries {
        let entry = entry.map_err(|source| ProfileError::ReadEntry { source })?;
        let name = match entry.file_name().into_string() {
            Ok(name) if valid_key(&name) => name,
            _ => continue,
        };
        if validate_profile(&entry.path(), &name).is_ok() {
            profiles.push(name);
        }
    }
    profiles.sort();
    Ok(profiles)
}

pub fn router_dir(root: &Path, name: &str) -> Result<PathBuf, ProfileError> {
    if !valid_key(name) {
        return Err(ProfileError::InvalidName);
    }
    let dir = profiles_root(root)?.join(name);
    validate_profile(&dir, name)?;
    Ok(dir)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    static COUNTER: AtomicUsize = AtomicUsize::new(0);

    struct Fixture(PathBuf);
    impl Fixture {
        fn new() -> Self {
            let id = COUNTER.fetch_add(1, Ordering::Relaxed);
            let path =
                std::env::temp_dir().join(format!("mcm-profiles-{}-{id}", std::process::id()));
            std::fs::create_dir_all(path.join("routers")).unwrap();
            Self(path)
        }
        fn add(&self, name: &str) {
            let dir = self.0.join("routers").join(name);
            std::fs::create_dir_all(&dir).unwrap();
            for file in REQUIRED {
                std::fs::write(dir.join(file), "[test]\nvalue = true\n").unwrap();
            }
        }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn discovers_new_models_without_hardcoded_names_and_sorts() {
        let root = Fixture::new();
        for name in ["hap-ac-lite", "test", "hap-ac2", "hap-ac"] {
            root.add(name);
        }
        assert_eq!(
            discover_profiles(&root.0).unwrap(),
            vec!["hap-ac", "hap-ac-lite", "hap-ac2", "test"]
        );
        assert!(router_dir(&root.0, "hap-ac2").is_ok());
    }

    #[test]
    fn rejects_incomplete_invalid_toml_and_unsafe_names() {
        let root = Fixture::new();
        root.add("valid");
        root.add("broken");
        std::fs::remove_file(root.0.join("routers/broken/dns.toml")).unwrap();
        root.add("syntax");
        std::fs::write(root.0.join("routers/syntax/network.toml"), "[invalid\n").unwrap();
        root.add("bad.name");
        assert_eq!(discover_profiles(&root.0).unwrap(), vec!["valid"]);
        assert!(router_dir(&root.0, "broken")
            .unwrap_err()
            .to_string()
            .contains("dns.toml"));
        assert!(router_dir(&root.0, "syntax")
            .unwrap_err()
            .to_string()
            .contains("network.toml"));
        assert!(router_dir(&root.0, "../valid").is_err());
    }

    #[cfg(unix)]
    #[test]
    fn rejects_symlinked_profiles_and_toml_files() {
        use std::os::unix::fs::symlink;
        let root = Fixture::new();
        root.add("valid");
        symlink(root.0.join("routers/valid"), root.0.join("routers/alias")).unwrap();
        root.add("linked_file");
        let file = root.0.join("routers/linked_file/dns.toml");
        std::fs::remove_file(&file).unwrap();
        symlink(root.0.join("routers/valid/dns.toml"), &file).unwrap();
        assert_eq!(discover_profiles(&root.0).unwrap(), vec!["valid"]);
        assert!(router_dir(&root.0, "alias").is_err());
        assert!(router_dir(&root.0, "linked_file").is_err());
    }
    #[cfg(unix)]
    #[test]
    fn rejects_symlinked_routers_directory_for_list_and_direct_selection() {
        use std::os::unix::fs::symlink;
        let outside = Fixture::new();
        outside.add("home-main");
        let root = Fixture::new();
        std::fs::remove_dir(root.0.join("routers")).unwrap();
        symlink(outside.0.join("routers"), root.0.join("routers")).unwrap();
        assert!(discover_profiles(&root.0)
            .unwrap_err()
            .to_string()
            .contains("symlink"));
        assert!(router_dir(&root.0, "home-main")
            .unwrap_err()
            .to_string()
            .contains("symlink"));
    }

    // Регресія: I/O та TOML-помилки зберігають тип першопричини й профіль.
    #[test]
    fn stage3_profile_errors_preserve_sources_and_selected_profile() {
        use std::error::Error;
        let root = Fixture::new();
        root.add("first");
        root.add("second");
        std::fs::remove_file(root.0.join("routers/first/dns.toml")).unwrap();
        let missing = router_dir(&root.0, "first").unwrap_err();
        assert!(matches!(
            &missing,
            ProfileError::MissingFile { name, file, .. }
                if name == "first" && file == "dns.toml"
        ));
        assert!(missing
            .source()
            .unwrap()
            .downcast_ref::<std::io::Error>()
            .is_some());
        assert!(router_dir(&root.0, "second").is_ok());

        std::fs::write(root.0.join("routers/second/network.toml"), "[bad\n").unwrap();
        let invalid = router_dir(&root.0, "second").unwrap_err();
        assert!(matches!(&invalid, ProfileError::InvalidToml { .. }));
        assert!(invalid
            .source()
            .unwrap()
            .downcast_ref::<toml::de::Error>()
            .is_some());
        assert!(invalid.to_string().contains("second"));
        assert!(invalid.to_string().contains("network.toml"));
    }

    #[test]
    fn profile_selection_resolves_only_within_the_supplied_root() {
        let first = Fixture::new();
        let second = Fixture::new();
        first.add("home-main");
        second.add("home-guest");
        assert_eq!(discover_profiles(&first.0).unwrap(), vec!["home-main"]);
        assert_eq!(discover_profiles(&second.0).unwrap(), vec!["home-guest"]);
        assert!(router_dir(&first.0, "home-guest").is_err());
        assert!(router_dir(&second.0, "home-main").is_err());
        assert_eq!(
            router_dir(&first.0, "home-main").unwrap(),
            first.0.join("routers/home-main")
        );
    }
}

// Регресійні перевірки: коди зберігаються, а системна причина доступна через source().
#[cfg(test)]
mod typed_profile_boundary_tests {
    use super::*;
    use std::error::Error;
    #[test]
    fn rejects_bad_name_with_a_structured_variant() {
        let error = router_dir(Path::new("/irrelevant"), "../unsafe").unwrap_err();
        assert!(matches!(error, ProfileError::InvalidName));
        assert_eq!(error.to_string(), "Invalid router name");
    }
    #[test]
    fn missing_routers_preserves_io_source() {
        let path = std::env::temp_dir()
            .join(format!("mcm-no-such-router-root-{}", std::process::id()))
            .join("missing-root");
        let error = discover_profiles(&path).unwrap_err();
        assert!(matches!(error, ProfileError::ReadRouters { .. }));
        assert!(error.source().is_some());
    }
}
