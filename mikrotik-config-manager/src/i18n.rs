// Тип помилки локалізації без класифікації за текстом.
#[derive(Debug)]
pub enum LocaleError {
    UnsupportedLanguage,
    Read {
        path: std::path::PathBuf,
        source: std::io::Error,
    },
    InvalidLine,
    EmptyKey {
        line: usize,
    },
    DuplicateKey {
        key: String,
        line: usize,
    },
}
impl std::fmt::Display for LocaleError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnsupportedLanguage => f.write_str("Supported languages: uk, en"),
            Self::Read { path, source } => write!(f, "{}: {source}", path.display()),
            Self::InvalidLine => f.write_str("Invalid locale line"),
            Self::EmptyKey { line } => write!(f, "Empty locale key at line {line}"),
            Self::DuplicateKey { key, line } => {
                write!(f, "Duplicate locale key at line {line}: {key}")
            }
        }
    }
}
impl std::error::Error for LocaleError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Read { source, .. } => Some(source),
            _ => None,
        }
    }
}

// Завантаження повідомлень інтерфейсу з локальних файлів uk/en.
// Якщо ключ не перекладений, повертаємо сам ключ без аварійної зупинки.
use std::collections::HashMap;
use std::fs;
use std::path::Path;

pub struct Messages {
    map: HashMap<String, String>,
}
impl Messages {
    pub fn load(root: &Path, lang: &str) -> Result<Self, LocaleError> {
        if lang != "uk" && lang != "en" {
            return Err(LocaleError::UnsupportedLanguage);
        }
        let path = root.join("locales").join(format!("{lang}.lang"));
        let contents = fs::read_to_string(&path).map_err(|source| LocaleError::Read {
            path: path.clone(),
            source,
        })?;
        let mut map = HashMap::new();
        for (index, line) in contents.lines().enumerate() {
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let (key, value) = line.split_once('=').ok_or(LocaleError::InvalidLine)?;
            if key.trim().is_empty() {
                return Err(LocaleError::EmptyKey { line: index + 1 });
            }
            if map.contains_key(key) {
                return Err(LocaleError::DuplicateKey {
                    key: key.to_string(),
                    line: index + 1,
                });
            }
            map.insert(key.to_string(), value.to_string());
        }
        Ok(Self { map })
    }
    pub fn get<'a>(&'a self, key: &'a str) -> &'a str {
        self.map.get(key).map(String::as_str).unwrap_or(key)
    }
}

#[cfg(test)]
mod locale_audit_tests {
    use super::*;
    use std::collections::HashSet;

    fn locale_keys(contents: &str) -> HashSet<String> {
        let mut keys = HashSet::new();
        for line in contents
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty() && !line.starts_with('#'))
        {
            let (key, value) = line
                .split_once('=')
                .expect("locale line must have key=value");
            assert!(!key.trim().is_empty(), "locale key must not be empty");
            assert!(
                !value.trim().is_empty(),
                "locale translation must not be empty: {key}"
            );
            assert!(keys.insert(key.to_owned()), "duplicate locale key: {key}");
        }
        keys
    }

    #[test]
    fn both_supported_locales_have_identical_unique_keys() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let uk = fs::read_to_string(root.join("locales/uk.lang")).unwrap();
        let en = fs::read_to_string(root.join("locales/en.lang")).unwrap();
        let uk_keys = locale_keys(&uk);
        let en_keys = locale_keys(&en);
        assert_eq!(uk_keys, en_keys, "Ukrainian and English locale keys differ");
        for key in ["ref_diag_profile", "ref_diag_file", "ref_diag_field"] {
            assert!(
                uk_keys.contains(key),
                "missing structured diagnostic locale key: {key}"
            );
        }
    }

    #[test]
    fn rejects_duplicate_keys_in_locale_audit() {
        let duplicate = std::panic::catch_unwind(|| locale_keys("name=one\nname=two\n"));
        assert!(duplicate.is_err());
    }
}

// Тестуємо типи помилок локалізації без аналізу їхніх рядків.
#[cfg(test)]
mod typed_locale_boundary_tests {
    use super::*;
    use std::error::Error;
    #[test]
    fn invalid_locale_has_stable_code() {
        let error = Messages::load(Path::new("."), "ru").err().unwrap();
        assert!(matches!(error, LocaleError::UnsupportedLanguage));
        assert_eq!(error.to_string(), "Supported languages: uk, en");
    }
    #[test]
    fn missing_locale_preserves_io_source() {
        let error = Messages::load(Path::new("/not-a-localization-root"), "uk")
            .err()
            .unwrap();
        assert!(matches!(error, LocaleError::Read { .. }));
        assert!(error.source().is_some());
    }
}

// Регресійні контракти завантажувача: некоректний файл не замінює тихо переклади.
#[cfg(test)]
mod runtime_locale_validation_tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn with_locale(content: &str, check: impl FnOnce(&Path)) {
        let serial = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!("mcm-locale-{}-{serial}", std::process::id()));
        let locales = root.join("locales");
        fs::create_dir_all(&locales).unwrap();
        fs::write(locales.join("uk.lang"), content).unwrap();
        check(&root);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn duplicate_key_reports_typed_error_and_original_line() {
        with_locale("# Коментар\nname=first\nname=second\n", |root| {
            let error = Messages::load(root, "uk").err().unwrap();
            assert!(matches!(
                error,
                LocaleError::DuplicateKey { ref key, line: 3 } if key == "name"
            ));
        });
    }

    #[test]
    fn blank_locale_key_is_rejected_without_accepting_translation() {
        for input in ["=value\n", "   =value\n", "name=ok\n\t=other\n"] {
            with_locale(input, |root| {
                assert!(matches!(
                    Messages::load(root, "uk"),
                    Err(LocaleError::EmptyKey { .. })
                ));
            });
        }
    }

    #[test]
    fn missing_equals_keeps_existing_typed_invalid_line() {
        with_locale("name=value\nwrong-line\n", |root| {
            assert!(matches!(
                Messages::load(root, "uk"),
                Err(LocaleError::InvalidLine)
            ));
        });
    }

    #[test]
    fn valid_locale_keeps_raw_values_and_missing_key_fallback() {
        with_locale(
            "# Пояснення\nfirst=one=two\nsecond=Привіт\n",
            |root| {
                let messages = Messages::load(root, "uk").unwrap();
                assert_eq!(messages.get("first"), "one=two");
                assert_eq!(messages.get("second"), "Привіт");
                assert_eq!(messages.get("unknown"), "unknown");
            },
        );
    }
}
