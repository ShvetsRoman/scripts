// Розбір глобальних параметрів з незмінним порядком і правилами CLI.
use mikrotik_config_manager::typed_config::{read_typed, ManagerConfig};
use std::path::Path;

// Предметні помилки аргументів: читання конфігурації не втрачає source().
#[derive(Debug)]
pub(crate) enum ArgsError {
    Manager(Box<mikrotik_config_manager::typed_config::TypedReadError>),
    MissingLanguage,
    ScriptUsage { allow_reset: bool },
    ScriptName(ScriptNameError),
    Profile(Box<crate::config::ProfileError>),
    DirectoryMetadata { source: std::io::Error },
    UnsafeProfileDirectory { path: std::path::PathBuf },
    CreateBuild { source: std::io::Error },
    SecureBuild { source: std::io::Error },
    UnsafeBuildDirectory,
    UnsafeOutputFile,
}
impl std::fmt::Display for ArgsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Manager(e) => write!(f, "{e}"),
            Self::MissingLanguage => f.write_str("--lang needs uk or en"),
            Self::ScriptUsage { allow_reset } => {
                if *allow_reset {
                    f.write_str("Використання: upload <профіль> [--name файл.rsc] [--reset]")
                } else {
                    f.write_str("Використання: build <профіль> [--name файл.rsc]")
                }
            }
            Self::ScriptName(e) => write!(f, "{e}"),
            Self::Profile(e) => write!(f, "{e}"),
            Self::DirectoryMetadata { source } => write!(f, "{source}"),
            Self::UnsafeProfileDirectory { path } => write!(
                f,
                "Каталог профілю не може бути symlink: {}",
                path.display()
            ),
            Self::CreateBuild { source } => write!(f, "Не вдалося створити build/: {source}"),
            Self::SecureBuild { source } => write!(f, "Не вдалося захистити build/: {source}"),
            Self::UnsafeBuildDirectory => {
                f.write_str("build/ повинен бути звичайним каталогом, не symlink")
            }
            Self::UnsafeOutputFile => {
                f.write_str("Вихідний файл не може бути symlink або спеціальним файлом")
            }
        }
    }
}
impl std::error::Error for ArgsError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Manager(e) => Some(e),
            Self::ScriptName(e) => Some(e),
            Self::Profile(e) => Some(e),
            Self::DirectoryMetadata { source }
            | Self::CreateBuild { source }
            | Self::SecureBuild { source } => Some(source),
            _ => None,
        }
    }
}

pub struct ParsedArgs {
    pub language: String,
    pub tokens: Vec<String>,
    pub color: String,
    pub default_router: String,
}

pub fn parse(args: &[String], root: &Path) -> Result<ParsedArgs, ArgsError> {
    let opts: ManagerConfig = read_typed(&root.join("config/manager.toml"))
        .map_err(|error| ArgsError::Manager(Box::new(error)))?;
    let mut language = opts.manager.language;
    let mut tokens = Vec::new();
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--lang" {
            i += 1;
            language = args.get(i).ok_or(ArgsError::MissingLanguage)?.to_string();
        } else {
            tokens.push(args[i].clone());
        }
        i += 1;
    }
    Ok(ParsedArgs {
        language,
        tokens,
        color: opts.manager.color,
        default_router: opts.manager.default_router,
    })
}

// Єдина схема параметрів для build і upload; --reset тільки для upload.
pub(crate) fn script_options(
    args: &[&str],
    allow_reset: bool,
) -> Result<(String, bool), ArgsError> {
    let mut name = "setup.rsc".to_string();
    let mut named = false;
    let mut reset = false;
    let mut i = 0;
    while i < args.len() {
        match args[i] {
            "--name" if !named => {
                i += 1;
                let value = args.get(i).ok_or(ArgsError::ScriptUsage { allow_reset })?;
                validate_script_name(value).map_err(ArgsError::ScriptName)?;
                name = (*value).to_string();
                named = true;
            }
            "--reset" if allow_reset && !reset => reset = true,
            _ => return Err(ArgsError::ScriptUsage { allow_reset }),
        }
        i += 1;
    }
    Ok((name, reset))
}

// Ім'я не може вийти з build/, бути опцією SCP або файлом автоімпорту.
// Відмова має окремий тип; зовнішня CLI-сигнатура не змінюється.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ScriptNameError {
    UnsafeName,
}

impl std::fmt::Display for ScriptNameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnsafeName => write!(
                f,
                "Некоректне ім'я: потрібне безпечне ASCII-ім'я *.rsc (не *.auto.rsc)"
            ),
        }
    }
}

impl std::error::Error for ScriptNameError {}

pub(crate) fn validate_script_name(name: &str) -> Result<(), ScriptNameError> {
    if name.len() > 80
        || !name.ends_with(".rsc")
        || name.ends_with(".auto.rsc")
        || name.starts_with('.')
        || name.starts_with('-')
        || name.contains("..")
        || !name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
    {
        return Err(ScriptNameError::UnsafeName);
    }
    Ok(())
}

// build/ є окремим каталогом усередині профілю, не символьним посиланням.
pub(crate) fn profile_script_path(
    root: &Path,
    router: &str,
    name: &str,
    create: bool,
) -> Result<std::path::PathBuf, ArgsError> {
    validate_script_name(name).map_err(ArgsError::ScriptName)?;
    let profile = crate::config::router_dir(root, router)
        .map_err(|error| ArgsError::Profile(Box::new(error)))?;
    // Усі компоненти профілю мають бути каталогами, а не посиланнями.
    for directory in [root.join("routers"), profile.clone()] {
        let meta = std::fs::symlink_metadata(&directory)
            .map_err(|source| ArgsError::DirectoryMetadata { source })?;
        if !meta.file_type().is_dir() || meta.file_type().is_symlink() {
            return Err(ArgsError::UnsafeProfileDirectory { path: directory });
        }
    }
    let dir = profile.join("build");
    if create && !dir.exists() {
        std::fs::create_dir(&dir).map_err(|source| ArgsError::CreateBuild { source })?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700))
                .map_err(|source| ArgsError::SecureBuild { source })?;
        }
    }
    if std::fs::symlink_metadata(&dir).is_ok() {
        let meta = std::fs::symlink_metadata(&dir)
            .map_err(|source| ArgsError::DirectoryMetadata { source })?;
        if !meta.file_type().is_dir() || meta.file_type().is_symlink() {
            return Err(ArgsError::UnsafeBuildDirectory);
        }
    }
    let path = dir.join(name);
    if let Ok(meta) = std::fs::symlink_metadata(&path) {
        if !meta.file_type().is_file() || meta.file_type().is_symlink() {
            return Err(ArgsError::UnsafeOutputFile);
        }
    }
    Ok(path)
}

#[cfg(test)]
mod script_path_tests {
    use super::*;

    #[test]
    fn script_flags_and_defaults() {
        assert_eq!(
            script_options(&[], false).unwrap(),
            ("setup.rsc".into(), false)
        );
        assert_eq!(
            script_options(&[], true).unwrap(),
            ("setup.rsc".into(), false)
        );
        assert_eq!(
            script_options(&["--name", "setup2.rsc"], false).unwrap(),
            ("setup2.rsc".into(), false)
        );
        assert_eq!(
            script_options(&["--reset", "--name", "setup2.rsc"], true).unwrap(),
            ("setup2.rsc".into(), true)
        );
        assert_eq!(
            script_options(&["--name", "setup2.rsc", "--reset"], true).unwrap(),
            ("setup2.rsc".into(), true)
        );
    }

    #[test]
    fn rejected_invalid_script_names() {
        for value in [
            "setup.auto.rsc",
            "some..rsc",
            "setup.rsc/",
            "setup.rsc;",
            "-setup.rsc",
        ] {
            assert!(validate_script_name(value).is_err(), "{value}");
        }
    }

    #[test]
    fn rejected_names_and_duplicates() {
        for bad in [
            "../escape.rsc",
            "/tmp/a.rsc",
            "sub/a.rsc",
            "x.auto.rsc",
            "-x.rsc",
            "x.txt",
            "a;reboot.rsc",
            "..rsc",
        ] {
            assert!(validate_script_name(bad).is_err(), "{bad}");
        }
        assert!(script_options(&["--reset"], false).is_err());
        assert!(script_options(&["--name"], true).is_err());
        assert!(script_options(&["--name", "a.rsc", "--name", "b.rsc"], true).is_err());
        assert!(script_options(&["--reset", "--reset"], true).is_err());
        assert!(script_options(&["unexpected"], false).is_err());
    }
}

#[cfg(test)]
mod typed_script_name_regression_tests {
    use super::*;

    #[test]
    fn unsafe_name_code_and_text_are_stable() {
        let err = validate_script_name("../unsafe.rsc").expect_err("Шлях заборонено");
        assert_eq!(err, ScriptNameError::UnsafeName);
        assert_eq!(
            err.to_string(),
            "Некоректне ім'я: потрібне безпечне ASCII-ім'я *.rsc (не *.auto.rsc)"
        );
        assert!(validate_script_name("safe_config.rsc").is_ok());
    }
}

#[cfg(test)]
mod regression_typed_args_tests {
    use super::*;
    use std::error::Error;
    #[test]
    fn missing_manager_toml_retains_real_io_source() {
        let root = std::env::temp_dir().join(format!("mcm-args-missing-{}", std::process::id()));
        let error = parse(&[], &root).err().expect("Конфігурації немає");
        assert!(matches!(error, ArgsError::Manager(_)));
        assert!(error.source().and_then(Error::source).is_some());
    }
    #[test]
    fn script_usage_and_invalid_names_are_distinct() {
        assert!(matches!(
            script_options(&["--reset"], false),
            Err(ArgsError::ScriptUsage { allow_reset: false })
        ));
        assert!(matches!(
            script_options(&["--name", "../a.rsc"], true),
            Err(ArgsError::ScriptName(ScriptNameError::UnsafeName))
        ));
    }
}
