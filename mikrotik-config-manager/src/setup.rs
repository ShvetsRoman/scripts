use std::fs::OpenOptions;
use std::io::Write;
#[cfg(unix)]
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::Path;

// Підготовка сценарію RouterOS, який виконає сам маршрутизатор
// за параметром run-after-reset. Жодної мережевої дії тут немає.
// Відокремлюємо етапи від команд: назви етапів потрібні для діагностики,
// але жодна команда й жоден пароль не повинні потрапляти до журналу RouterOS.
fn stage_for(line: &str) -> &'static str {
    if line.starts_with("/interface ethernet ") {
        "interfaces"
    } else if line.starts_with("/interface bridge ") {
        "bridge"
    } else if line.starts_with("/ip address ") {
        "network"
    } else if line.starts_with("/interface list ") {
        "lists"
    } else if line.starts_with("/ip dhcp-server ") || line.starts_with("/ip pool ") {
        "dhcp"
    } else if line.starts_with("/ip dns ") {
        "dns"
    } else if line.starts_with("/ip dhcp-client ") {
        "wan"
    } else if line.starts_with("/ip firewall nat ") {
        "nat"
    } else if line.starts_with("/ip firewall filter ") {
        "firewall"
    } else if line.starts_with("/interface wireless ") || line.starts_with("/interface wifi ") {
        "wireless"
    } else if line.starts_with("/interface wireguard ") {
        "wireguard"
    } else if line.starts_with("/ip service ") {
        "services"
    } else if line.starts_with("/system ") {
        "system"
    } else if line.starts_with("/user ") {
        "credentials"
    } else {
        "other"
    }
}

// Обгортка RouterOS: помилка не маскується, наступні команди не виконуються.
// У журнал потрапляють тільки стабільний номер і назва етапу, не сама команда.
fn guarded_command(command: &str, stage: &str, index: usize) -> String {
    format!(":do {{ {command} }} on-error={{ :log error \"MCM: FAIL step={index} stage={stage}\"; :error \"MCM_SETUP_FAILED\" }}")
}

// Структуровані помилки підготовки: зберігаємо вихідний текст CLI, але
// передаємо причину без розпізнавання рядків або повторного читання TOML.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SetupCode {
    WifiReference,
    WifiSecurityName,
    WifiSecurityProfile,
    WifiSecurityCount,
    ProfileDirectory,
    ProfileWirelessConfig,
    SecretsMetadata,
    SecretsNotFile,
    SecretsTooLarge,
    SecretsRead,
    SecretsMalformedLine,
    SecretsInvalidValue,
    SecretsUnexpectedKey,
    SecretsMissingAdmin,
    SecretsMissingWifi,
    SecretsDuplicateUserKey,
    DestinationExtension,
    DestinationCreate,
    DestinationWrite,
    DestinationSync,
    RuntimeMissingAdmin,
    RuntimeAdminName,
    RuntimeAdminGroup,
    RuntimeUserName,
    RuntimeDuplicateAdmin,
    RuntimeUserGroup,
    RuntimeUserPassword,
    RuntimeMissingWifi,
    RuntimeWifiDriver,
    RuntimeInvalidCharacter,
    RuntimeUnknownInstruction,
    RuntimeWifiProfileNotCreated,
}

#[derive(Debug)]
pub struct SetupIssue {
    pub code: SetupCode,
    pub detail: String,
    // Початкова типізована помилка зберігається окремо від тексту CLI.
    source: Option<Box<dyn std::error::Error + Send + Sync>>,
}

impl SetupIssue {
    // Лише для регресійних тестів межі CLI; робочий конструктор не публічний.
    #[cfg(test)]
    pub(crate) fn test_issue(code: SetupCode, detail: impl Into<String>) -> Self {
        Self::new(code, detail)
    }

    fn new(code: SetupCode, detail: impl Into<String>) -> Self {
        Self {
            code,
            detail: detail.into(),
            source: None,
        }
    }

    // Не змінюємо текст повідомлення, але зберігаємо першопричину I/O.
    fn with_io(code: SetupCode, detail: impl Into<String>, source: std::io::Error) -> Self {
        Self::with_source(code, detail, source)
    }

    // Зберігаємо фактичний тип першопричини, а не лише її Display-повідомлення.
    fn with_source<E>(code: SetupCode, detail: impl Into<String>, source: E) -> Self
    where
        E: std::error::Error + Send + Sync + 'static,
    {
        Self {
            code,
            detail: detail.into(),
            source: Some(Box::new(source)),
        }
    }
}

impl std::fmt::Display for SetupIssue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Вичерпно опрацьовуємо тип помилки, зберігаючи попередній текст CLI.
        // Новий код потребуватиме явного додавання до цього зіставлення.
        match self.code {
            SetupCode::WifiReference
            | SetupCode::WifiSecurityName
            | SetupCode::WifiSecurityProfile
            | SetupCode::WifiSecurityCount
            | SetupCode::ProfileDirectory
            | SetupCode::ProfileWirelessConfig
            | SetupCode::SecretsMetadata
            | SetupCode::SecretsNotFile
            | SetupCode::SecretsTooLarge
            | SetupCode::SecretsRead
            | SetupCode::SecretsMalformedLine
            | SetupCode::SecretsInvalidValue
            | SetupCode::SecretsUnexpectedKey
            | SetupCode::SecretsMissingAdmin
            | SetupCode::SecretsMissingWifi
            | SetupCode::SecretsDuplicateUserKey
            | SetupCode::DestinationExtension
            | SetupCode::DestinationCreate
            | SetupCode::DestinationWrite
            | SetupCode::DestinationSync
            | SetupCode::RuntimeMissingAdmin
            | SetupCode::RuntimeAdminName
            | SetupCode::RuntimeAdminGroup
            | SetupCode::RuntimeUserName
            | SetupCode::RuntimeDuplicateAdmin
            | SetupCode::RuntimeUserGroup
            | SetupCode::RuntimeUserPassword
            | SetupCode::RuntimeMissingWifi
            | SetupCode::RuntimeWifiDriver
            | SetupCode::RuntimeInvalidCharacter
            | SetupCode::RuntimeUnknownInstruction
            | SetupCode::RuntimeWifiProfileNotCreated => f.write_str(&self.detail),
        }
    }
}

impl std::error::Error for SetupIssue {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.source
            .as_deref()
            .map(|error| error as &(dyn std::error::Error + 'static))
    }
}

// Знаходимо профіль безпеки за посиланнями активних радіо, а не за
// зафіксованим ID (home/wifi). Один WIFI_PASSWORD використовується лише
// для одного спільного профілю безпеки; іншу схему відхиляємо явно.
fn wifi_security_name(
    settings: &mikrotik_config_manager::typed_config::WirelessConfig,
) -> Result<String, SetupIssue> {
    let mut names = std::collections::BTreeSet::new();
    for (id, radio) in &settings.wireless.radios {
        if !id.starts_with("wlan") || !radio.enabled {
            continue;
        }
        let Some(target) = radio.security.strip_prefix("@security.") else {
            return Err(SetupIssue::new(
                SetupCode::WifiReference,
                format!("wireless.{id}.security: очікується @security.id"),
            ));
        };
        if target.is_empty()
            || !target
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-'))
        {
            return Err(SetupIssue::new(
                SetupCode::WifiReference,
                format!("wireless.{id}.security: некоректне посилання"),
            ));
        }
        let profile = settings.security.get(target).ok_or_else(|| {
            SetupIssue::new(
                SetupCode::WifiSecurityProfile,
                format!("Не знайдено security.{target}.name"),
            )
        })?;
        crate::modules::token(&profile.name, "wireless.security.name").map_err(|error| {
            SetupIssue::with_source(SetupCode::WifiSecurityName, error.to_string(), error)
        })?;
        names.insert(profile.name.clone());
    }
    if names.len() != 1 {
        return Err(SetupIssue::new(
            SetupCode::WifiSecurityCount,
            "Для WIFI_PASSWORD потрібен один спільний Security Profile активних Wi-Fi інтерфейсів",
        ));
    }
    Ok(names.into_iter().next().unwrap())
}

// Потреба в Wi-Fi паролі визначається тільки типізованою конфігурацією.
// Назва профілю або модель маршрутизатора на рішення не впливають.
fn requires_wifi_password(
    settings: &mikrotik_config_manager::typed_config::WirelessConfig,
) -> bool {
    settings.wireless.enabled && settings.wireless.radios.values().any(|radio| radio.enabled)
}

fn profile_requires_wifi(root: &Path, router: &str) -> Result<bool, SetupIssue> {
    let dir = crate::config::router_dir(root, router)
        .map_err(|e| SetupIssue::with_source(SetupCode::ProfileDirectory, e.to_string(), e))?;
    let settings: mikrotik_config_manager::typed_config::WirelessConfig =
        mikrotik_config_manager::typed_config::read_typed(&dir.join("wireless.toml")).map_err(
            |e| SetupIssue::with_source(SetupCode::ProfileWirelessConfig, e.to_string(), e),
        )?;
    Ok(requires_wifi_password(&settings))
}

// Помилки зберігають структурований код до виходу з CLI.
#[derive(Debug)]
pub enum SetupError {
    Plan(Box<crate::modules::reference_error::PlanError>),
    Issue(SetupIssue),
    Profile(crate::config::ProfileError),
    TypedConfig(mikrotik_config_manager::typed_config::TypedReadError),
}
impl std::fmt::Display for SetupError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Plan(error) => write!(f, "{error}"),
            Self::Issue(error) => write!(f, "{error}"),
            Self::Profile(error) => write!(f, "{error}"),
            Self::TypedConfig(error) => write!(f, "{error}"),
        }
    }
}
impl From<SetupIssue> for SetupError {
    fn from(value: SetupIssue) -> Self {
        Self::Issue(value)
    }
}
impl From<crate::config::ProfileError> for SetupError {
    fn from(value: crate::config::ProfileError) -> Self {
        Self::Profile(value)
    }
}
impl From<mikrotik_config_manager::typed_config::TypedReadError> for SetupError {
    fn from(value: mikrotik_config_manager::typed_config::TypedReadError) -> Self {
        Self::TypedConfig(value)
    }
}
impl std::error::Error for SetupError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Plan(error) => Some(error),
            Self::Issue(error) => Some(error),
            Self::Profile(error) => Some(error),
            Self::TypedConfig(error) => Some(error),
        }
    }
}
impl From<crate::modules::reference_error::PlanError> for SetupError {
    fn from(value: crate::modules::reference_error::PlanError) -> Self {
        Self::Plan(Box::new(value))
    }
}

// Єдиний рендерер для повного сценарію з опційними секретами.
// Режим без секретів призначено для перегляду, а не для upload.
fn render_runtime(
    root: &Path,
    router: &str,
    credentials: Option<(
        &str,
        Option<&str>,
        &std::collections::HashMap<String, String>,
    )>,
) -> Result<String, SetupError> {
    let plan = crate::modules::plan(root, router, None)?;
    let mut steps: Vec<(String, String)> = Vec::new();
    let mut admin_command = None;
    let mut wifi_command = None;
    let mut extra_users = Vec::new();
    if let Some((admin, wifi, user_passwords)) = credentials {
        let dir = crate::config::router_dir(root, router)?;
        // Зберігаємо повні TOML-ключі users.admin.name і users.<id>.group.
        let security: mikrotik_config_manager::typed_config::SystemConfig =
            mikrotik_config_manager::typed_config::read_typed(&dir.join("system.toml"))?;
        let admin_user = security.users.get("admin").ok_or_else(|| {
            SetupIssue::new(SetupCode::RuntimeMissingAdmin, "Немає users.admin.name")
        })?;
        let account = admin_user.name.as_str();
        crate::modules::token(account, "users.admin.name").map_err(|error| {
            SetupIssue::with_source(SetupCode::RuntimeAdminName, error.to_string(), error)
        })?;
        let admin_group = admin_user.group.as_str();
        if admin_group != "full" {
            return Err(SetupIssue::new(
                SetupCode::RuntimeAdminGroup,
                "Адміністративна група повинна бути full",
            )
            .into());
        }
        admin_command = Some(format!(
            "/user set [find name=admin] name={account} group={admin_group} password=\"{admin}\""
        ));
        for (id, user) in &security.users {
            if id == "admin" || !user.managed {
                continue;
            }
            crate::modules::token(&user.name, "users.name").map_err(|error| {
                SetupIssue::with_source(SetupCode::RuntimeUserName, error.to_string(), error)
            })?;
            if user.name == "admin" || user.name == account {
                return Err(SetupIssue::new(
                    SetupCode::RuntimeDuplicateAdmin,
                    "Дублювання адміністративного користувача",
                )
                .into());
            }
            if !matches!(user.group.as_str(), "full" | "read" | "write") {
                return Err(SetupIssue::new(
                    SetupCode::RuntimeUserGroup,
                    "Непідтримувана група користувача",
                )
                .into());
            }
            let secret_key = format!("USER_{}_PASSWORD", id.to_ascii_uppercase());
            let password = user_passwords.get(&secret_key).ok_or_else(|| {
                SetupIssue::new(
                    SetupCode::RuntimeUserPassword,
                    format!("Відсутній пароль {secret_key} у .secrets"),
                )
            })?;
            extra_users.push(format!(
                "/user add name={} group={} password=\"{password}\"",
                user.name, user.group
            ));
        }
        // Пароль у .secrets не вмикає Wi-Fi сам по собі: CHR не має радіо.
        // Генеруємо Wi-Fi-команди лише за наявності відповідного профілю.
        let settings: mikrotik_config_manager::typed_config::WirelessConfig =
            mikrotik_config_manager::typed_config::read_typed(&dir.join("wireless.toml"))?;
        if requires_wifi_password(&settings) {
            let pass = wifi.ok_or_else(|| {
                SetupIssue::new(SetupCode::RuntimeMissingWifi, "Відсутній WIFI_PASSWORD")
            })?;
            // Security Profile обираємо за @security.id активних Wi-Fi радіо.
            let name = wifi_security_name(&settings)?;
            wifi_command = Some(match settings.wireless.driver.as_str() {
                "legacy" => format!("/interface wireless security-profiles set [find name={name}] wpa2-pre-shared-key=\"{pass}\""),
                "wifi-qcom-ac" => format!("/interface wifi security set [find name={name}] passphrase=\"{pass}\""),
                _ => return Err(SetupIssue::new(SetupCode::RuntimeWifiDriver, "Непідтримуваний Wi-Fi драйвер").into()),
            });
        }
    }
    // Пароль адміністратора ставимо до інших мережевих дій.
    if let Some(cmd) = admin_command {
        steps.push(("credentials".into(), cmd));
    }
    // Створюємо керованих користувачів після налаштування адміністратора.
    for cmd in extra_users {
        steps.push(("credentials".into(), cmd));
    }
    let mut wifi_inserted = false;
    for line in plan.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.chars().any(|c| c == '\0' || c == '\r' || c == '\n') {
            return Err(SetupIssue::new(
                SetupCode::RuntimeInvalidCharacter,
                "Сценарій містить заборонений символ",
            )
            .into());
        }
        if !line.starts_with('/') {
            return Err(SetupIssue::new(
                SetupCode::RuntimeUnknownInstruction,
                "Невідома інструкція у плані RouterOS",
            )
            .into());
        }
        steps.push((stage_for(line).into(), line.into()));
        // Профіль захисту має існувати до встановлення пароля й увімкнення Wi-Fi.
        if line.contains("comment=mcm-wifi-security") && line.contains(" add ") {
            if let Some(cmd) = wifi_command.as_ref() {
                steps.push(("wifi-credentials".into(), cmd.clone()));
                wifi_inserted = true;
            }
        }
    }
    if wifi_command.is_some() && !wifi_inserted {
        return Err(SetupIssue::new(
            SetupCode::RuntimeWifiProfileNotCreated,
            "Не знайдено створення Wi-Fi Security Profile",
        )
        .into());
    }
    let secure = credentials.is_some();
    let mut lines = vec![
        "# MikroTik Config Manager — RouterOS 7, початкове налаштування".into(),
        format!(
            "# Профіль: {router}; генератор: {}",
            env!("CARGO_PKG_VERSION")
        ),
        "# Виконувати після reset-configuration no-defaults=yes".into(),
        if secure {
            "# MCM_SECURE_RUNTIME: requires protected secrets".into()
        } else {
            "# MCM_PREVIEW_ONLY: паролі не налаштовано; RESET заборонено".into()
        },
        ":log info \"MCM: START\"".into(),
        ":log info \"MCM: initial setup started\"".into(),
    ];
    let mut previous = "";
    for (i, (stage, command)) in steps.iter().enumerate() {
        if stage != previous {
            lines.push(format!(":log info \"MCM: STAGE {stage}\""));
            previous = stage;
        }
        lines.push(guarded_command(command, stage, i + 1));
    }
    lines.push(":log info \"MCM: COMPLETE\"".into());
    Ok(format!("{}\n", lines.join("\n")))
}

#[cfg(test)]
fn render(root: &Path, router: &str) -> Result<String, SetupError> {
    render_runtime(root, router, None)
}

// Локальні секрети читаємо лише з окремого файла; у TOML і репозиторії їх немає.
// Файл не допускає перенаправлень і неочікуваних полів.
// Небезпечні права доступу лише попереджають, не блокуючи генерацію.
struct ValidatedSecrets {
    admin: String,
    wifi: Option<String>,
    users: std::collections::HashMap<String, String>,
}

fn validated_secrets(path: &Path, require_wifi: bool) -> Result<ValidatedSecrets, SetupIssue> {
    let meta = std::fs::symlink_metadata(path).map_err(|e| {
        SetupIssue::with_io(
            SetupCode::SecretsMetadata,
            format!("Файл секретів недоступний: {e}"),
            e,
        )
    })?;
    if !meta.file_type().is_file() {
        return Err(SetupIssue::new(
            SetupCode::SecretsNotFile,
            "Секрети мають бути звичайним файлом",
        ));
    }
    #[cfg(unix)]
    if meta.permissions().mode() & 0o777 != 0o600 {
        // Права можуть дозволяти читання стороннім користувачам.
        // Не виводимо вміст файла або значення паролів до діагностики.
        eprintln!(
            "[WARNING] Файл секретів {} має права {:04o}; рекомендовано 0600 (chmod 600). Продовжуємо роботу.",
            path.display(),
            meta.permissions().mode() & 0o777
        );
    }
    if meta.len() > 4096 {
        return Err(SetupIssue::new(
            SetupCode::SecretsTooLarge,
            "Файл секретів завеликий",
        ));
    }
    let source = std::fs::read_to_string(path).map_err(|e| {
        SetupIssue::with_io(
            SetupCode::SecretsRead,
            format!("Не вдалося прочитати секрети: {e}"),
            e,
        )
    })?;
    let mut admin = None;
    let mut wifi = None;
    let mut users = std::collections::HashMap::new();
    for line in source.lines() {
        if line.trim().is_empty() || line.trim_start().starts_with('#') {
            continue;
        }
        let (key, val) = line.split_once('=').ok_or_else(|| {
            SetupIssue::new(
                SetupCode::SecretsMalformedLine,
                "Некоректний рядок секретів",
            )
        })?;
        let value = val.to_string();
        // Не дозволяємо символи інтерполяції та керування RouterOS.
        if !(8..=30).contains(&value.len())
            || !value.bytes().all(|b| {
                (33..=126).contains(&b)
                    && !matches!(b, b'"' | b'\\' | b'$' | b';' | b'`' | b'{' | b'}')
            })
        {
            return Err(SetupIssue::new(
                SetupCode::SecretsInvalidValue,
                "Секрет має бути 8–30 безпечних ASCII-символів без пробілів або символів RouterOS",
            ));
        }
        match key {
            "ADMIN_PASSWORD" if admin.is_none() => admin = Some(value),
            "WIFI_PASSWORD" if wifi.is_none() => wifi = Some(value),
            key if key.starts_with("USER_")
                && key.ends_with("_PASSWORD")
                && !key[5..key.len() - 9].is_empty()
                && key[5..key.len() - 9]
                    .chars()
                    .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_') =>
            {
                if users.insert(key.to_owned(), value).is_some() {
                    return Err(SetupIssue::new(
                        SetupCode::SecretsDuplicateUserKey,
                        format!("Повторений ключ {key} у .secrets"),
                    ));
                }
            }
            _ => {
                return Err(SetupIssue::new(
                    SetupCode::SecretsUnexpectedKey,
                    "Повторений або невідомий параметр секретів",
                ))
            }
        }
    }
    let admin = admin.ok_or_else(|| {
        SetupIssue::new(SetupCode::SecretsMissingAdmin, "Відсутній ADMIN_PASSWORD")
    })?;
    if require_wifi && wifi.is_none() {
        return Err(SetupIssue::new(
            SetupCode::SecretsMissingWifi,
            "Відсутній WIFI_PASSWORD",
        ));
    }
    Ok(ValidatedSecrets { admin, wifi, users })
}

#[cfg(test)]
fn load_secrets(path: &Path, require_wifi: bool) -> Result<(String, Option<String>), SetupIssue> {
    let secrets = validated_secrets(path, require_wifi)?;
    Ok((secrets.admin, secrets.wifi))
}

// Секрети в самому RSC неминуче присутні до імпорту: створюємо його з 0600,
// ніколи не друкуємо в журнал і не записуємо до TOML.
pub fn export_secure(
    root: &Path,
    router: &str,
    destination: &Path,
    secret_path: &Path,
) -> Result<(), SetupError> {
    if destination.extension().and_then(|v| v.to_str()) != Some("rsc") {
        return Err(SetupIssue::new(
            SetupCode::DestinationExtension,
            "Потрібен вихідний файл із розширенням .rsc",
        )
        .into());
    }
    // Один прочитаний та валідований знімок секретів використовується для всіх користувачів.
    let ValidatedSecrets { admin, wifi, users } =
        validated_secrets(secret_path, profile_requires_wifi(root, router)?)?;
    // Прив'язка секретів до етапів відбувається ДО формування захищених команд.
    // Рендерер не друкує паролі навіть у повідомленні про помилку.
    let content = render_runtime(root, router, Some((&admin, wifi.as_deref(), &users)))?;
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    options.mode(0o600);
    let file = options.open(destination).map_err(|e| {
        SetupIssue::with_io(
            SetupCode::DestinationCreate,
            format!("Не вдалося створити RSC: {e}"),
            e,
        )
    })?;
    write_complete_rsc(file, destination, content.as_bytes())
}

// Запис нового RSC: у разі помилки не залишаємо неповний файл.
fn write_complete_rsc(
    file: std::fs::File,
    destination: &Path,
    content: &[u8],
) -> Result<(), SetupError> {
    // Помилка запису або синхронізації не повинна залишати частково готовий RSC.
    // Очищаємо тільки файл, який щойно створено через create_new(true).
    let mut file = file;
    let result = (|| -> Result<(), SetupError> {
        file.write_all(content).map_err(|e| {
            SetupIssue::with_io(
                SetupCode::DestinationWrite,
                format!("Не вдалося записати RSC: {e}"),
                e,
            )
        })?;
        file.sync_all().map_err(|e| {
            SetupIssue::with_io(
                SetupCode::DestinationSync,
                format!("Не вдалося синхронізувати RSC: {e}"),
                e,
            )
        })?;
        Ok(())
    })();
    if result.is_err() {
        drop(file);
        let _ = std::fs::remove_file(destination);
    }
    result
}

#[cfg(test)]
mod stage4_output_cleanup_tests {
    use super::*;
    use std::error::Error;

    // Непридатний для запису дескриптор імітує збій після створення файлу.
    #[test]
    fn failed_rsc_write_removes_incomplete_file_and_preserves_io_source() {
        let path = std::env::temp_dir().join(format!(
            "mcm-stage4-output-{}-{:?}.rsc",
            std::process::id(),
            std::thread::current().id()
        ));
        // Спочатку створюємо новий файл із правом запису: Rust вимагає
        // write(true) або append(true) разом із create_new(true).
        let created = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
            .unwrap();
        drop(created);
        // Повторно відкриваємо лише для читання, щоб write_all() гарантовано
        // повернув I/O-помилку й перевірив очищення неповного RSC.
        let file = OpenOptions::new().read(true).open(&path).unwrap();
        let error = write_complete_rsc(file, &path, b"INCOMPLETE")
            .expect_err("Запис у дескриптор без права запису повинен завершитися помилкою");
        assert!(
            !path.exists(),
            "Неповний RSC не можна залишати після помилки"
        );
        assert!(
            error.source().is_some(),
            "Початкова I/O-причина повинна зберігатися"
        );
    }
}

#[cfg(test)]
mod tests {

    #[test]
    fn security_reference_uses_configured_id_not_hardcoded_home() {
        use mikrotik_config_manager::typed_config::WirelessConfig;
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        let path = root.join("routers/hap-ac/wireless.toml");
        let config: WirelessConfig =
            mikrotik_config_manager::typed_config::read_typed(&path).unwrap();
        let name = super::wifi_security_name(&config).unwrap();
        assert!(!name.is_empty());
        let mut invalid = config;
        invalid.security.clear();
        assert!(super::wifi_security_name(&invalid).is_err());
        let active = invalid
            .wireless
            .radios
            .values_mut()
            .find(|r| r.enabled)
            .unwrap();
        active.security = "legacy".into();
        assert!(super::wifi_security_name(&invalid).is_err());
    }
    use super::*;

    #[test]
    fn wifi_requirement_comes_from_typed_configuration_not_router_name() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        assert!(super::profile_requires_wifi(root, "hap-ac").unwrap());
        assert!(!super::profile_requires_wifi(root, "test").unwrap());

        let wireless: mikrotik_config_manager::typed_config::WirelessConfig =
            mikrotik_config_manager::typed_config::read_typed(
                &root.join("routers/hap-ac/wireless.toml"),
            )
            .unwrap();
        assert!(super::requires_wifi_password(&wireless));
        let mut disabled = wireless;
        disabled.wireless.enabled = false;
        assert!(!super::requires_wifi_password(&disabled));
        disabled.wireless.enabled = true;
        for radio in disabled.wireless.radios.values_mut() {
            radio.enabled = false;
        }
        assert!(!super::requires_wifi_password(&disabled));
    }

    #[cfg(unix)]
    #[test]
    fn copied_wifi_profile_needs_password_without_hardcoded_name() {
        use std::os::unix::fs::OpenOptionsExt;
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let tmp = std::env::temp_dir().join(format!(
            "mcm-wifi-independent-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let router_dir = tmp.join("routers/home-wifi-copy");
        std::fs::create_dir_all(&router_dir).unwrap();
        for entry in std::fs::read_dir(root.join("routers/hap-ac")).unwrap() {
            let entry = entry.unwrap();
            if entry.path().extension().and_then(|v| v.to_str()) == Some("toml") {
                std::fs::copy(entry.path(), router_dir.join(entry.file_name())).unwrap();
            }
        }
        assert!(super::profile_requires_wifi(&tmp, "home-wifi-copy").unwrap());
        let secrets = tmp.join("secrets");
        let mut opts = OpenOptions::new();
        opts.write(true).create_new(true).mode(0o600);
        let mut file = opts.open(&secrets).unwrap();
        file.write_all(b"ADMIN_PASSWORD=AdminPass123\n").unwrap();
        file.sync_all().unwrap();
        let output = tmp.join("setup.rsc");
        let err = super::export_secure(&tmp, "home-wifi-copy", &output, &secrets).unwrap_err();
        assert!(err.to_string().contains("WIFI_PASSWORD"), "{err}");
        assert!(!output.exists());
        std::fs::remove_dir_all(&tmp).unwrap();
    }

    #[test]
    fn validated_secret_snapshot_includes_only_validated_user_passwords() {
        let path =
            std::env::temp_dir().join(format!("mcm-secret-once-{}.secrets", std::process::id()));
        std::fs::write(
            &path,
            "ADMIN_PASSWORD=AdminPass123\nUSER_GUEST_PASSWORD=GuestPass123\n",
        )
        .unwrap();
        let snapshot = super::validated_secrets(&path, false).unwrap();
        assert_eq!(
            snapshot
                .users
                .get("USER_GUEST_PASSWORD")
                .map(String::as_str),
            Some("GuestPass123")
        );
        std::fs::write(
            &path,
            "ADMIN_PASSWORD=AdminPass123\nUSER_GUEST_PASSWORD=bad\n",
        )
        .unwrap();
        assert_eq!(
            snapshot
                .users
                .get("USER_GUEST_PASSWORD")
                .map(String::as_str),
            Some("GuestPass123")
        );
        assert!(super::validated_secrets(&path, false).is_err());
        std::fs::remove_file(&path).unwrap();
    }

    #[test]
    fn render_profiles_without_reset_or_private_keys() {
        for router in ["hap-ac", "test"] {
            let script = render(Path::new(env!("CARGO_MANIFEST_DIR")), router).unwrap();
            assert!(script.contains(":log info \"MCM: START\""));
            assert!(script.contains("/interface bridge add "));
            assert!(script.contains("MCM: COMPLETE"));
            assert!(script.contains("MCM_SETUP_FAILED"));
            assert!(script.contains("/ip firewall filter add "));
            assert!(!script.contains("/system reset-configuration"));
            assert!(!script.contains("private-key="));
        }
    }
    #[test]
    fn runtime_stops_on_error_and_marks_completion_last() {
        let script = render(Path::new(env!("CARGO_MANIFEST_DIR")), "test").unwrap();
        assert!(script.contains("on-error={ :log error"));
        assert!(script.contains(":error \"MCM_SETUP_FAILED\""));
        let last = script.lines().last().unwrap();
        assert_eq!(last, ":log info \"MCM: COMPLETE\"");
        assert!(script.contains("MCM_PREVIEW_ONLY"));
    }

    #[cfg(unix)]
    #[test]
    fn secure_rsc_builds_for_both_profiles_with_nested_toml_sections() {
        // Перевіряємо справжню генерацію .rsc з паролями, не торкаючись робочих .secrets.
        use std::sync::atomic::{AtomicUsize, Ordering};
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        for profile in ["test", "hap-ac"] {
            let id = NEXT.fetch_add(1, Ordering::Relaxed);
            let dir = std::env::temp_dir().join(format!(
                "mcm-build-nested-{}-{id}-{profile}",
                std::process::id()
            ));
            std::fs::create_dir(&dir).unwrap();
            let secrets = dir.join("test.secrets");
            let output = dir.join("setup.rsc");
            // Формуємо ізольовані тестові секрети за фактичними керованими
            // користувачами профілю. Нові users.<id> не повинні ламати тест.
            let config: mikrotik_config_manager::typed_config::SystemConfig =
                mikrotik_config_manager::typed_config::read_typed(
                    &root.join("routers").join(profile).join("system.toml"),
                )
                .unwrap();
            let mut content =
                String::from("ADMIN_PASSWORD=AdminPass123\nWIFI_PASSWORD=WifiPass123\n");
            let mut managed_ids: Vec<String> = config
                .users
                .iter()
                .filter(|&(id, user)| id != "admin" && user.managed)
                .map(|(id, _)| id.clone())
                .collect();
            managed_ids.sort();
            for id in &managed_ids {
                content.push_str(&format!(
                    "USER_{}_PASSWORD=UserPass123\n",
                    id.to_ascii_uppercase()
                ));
            }
            // Створюємо тестовий файл із правами 0600 від самого початку.
            // Не використовуємо робочі секрети користувача й не залишаємо їх у каталозі проєкту.
            let mut opts = OpenOptions::new();
            opts.write(true).create_new(true).mode(0o600);
            let mut secret_file = opts.open(&secrets).unwrap();
            secret_file.write_all(content.as_bytes()).unwrap();
            secret_file.sync_all().unwrap();
            assert_eq!(
                std::fs::metadata(&secrets).unwrap().permissions().mode() & 0o777,
                0o600
            );
            // Паролі беруться лише із зовнішнього тестового файлу секретів.
            export_secure(root, profile, &output, &secrets).unwrap();
            let script = std::fs::read_to_string(&output).unwrap();
            assert!(script.contains("MCM_SECURE_RUNTIME"));
            assert!(script.contains("/user set "));
            assert!(script.contains("AdminPass123"));
            if profile == "hap-ac" {
                assert!(script.contains("WifiPass123"));
                assert!(script.contains("wifi-credentials"));
                assert!(script.contains("mcm-wifi-security"));
            } else {
                // Зайвий Wi-Fi пароль у .secrets не створює команд на CHR.
                assert!(!script.contains("WifiPass123"));
                assert!(!script.contains("wifi-credentials"));
            }
            assert_eq!(
                std::fs::metadata(&output).unwrap().permissions().mode() & 0o777,
                0o600
            );
            std::fs::remove_dir_all(&dir).unwrap();
        }
    }

    #[test]
    fn guarded_steps_do_not_log_command_values() {
        let wrapped = guarded_command(
            "/user set [find name=admin] password=\"secret\"",
            "credentials",
            1,
        );
        let diagnostic = wrapped.split("on-error=").nth(1).unwrap();
        assert!(!diagnostic.contains("secret"));
        assert!(diagnostic.contains("step=1 stage=credentials"));
    }
}

#[cfg(test)]
mod secret_tests {
    use super::*;
    #[cfg(unix)]
    #[test]
    fn secret_length_boundaries() {
        // Перевіряємо межі 8–30 для двох обов'язкових паролів.
        let path = std::env::temp_dir().join(format!(
            "mcm-secret-length-{}-{:?}.secrets",
            std::process::id(),
            std::thread::current().id()
        ));
        for length in [7_usize, 8, 30, 31] {
            let password = "A".repeat(length);
            let content = format!("ADMIN_PASSWORD={password}\nWIFI_PASSWORD={password}\n");
            std::fs::write(&path, content).unwrap();
            assert_eq!(
                load_secrets(&path, true).is_ok(),
                (8..=30).contains(&length)
            );
        }
        std::fs::remove_file(&path).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn additional_user_secret_is_accepted() {
        // Окремий пароль для нового облікового запису не порушує формат .secrets.
        let path = std::env::temp_dir().join(format!(
            "mcm-user-secret-{}-{:?}.secrets",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::write(
            &path,
            "ADMIN_PASSWORD=AdminPass123\nUSER_GUEST_PASSWORD=GuestPass123\n",
        )
        .unwrap();
        assert!(load_secrets(&path, false).is_ok());
        std::fs::remove_file(&path).unwrap();
    }

    #[test]
    fn missing_secret_file_is_rejected() {
        assert!(load_secrets(Path::new("/nonexistent/mcm-secrets"), true).is_err());
    }
    #[cfg(unix)]
    #[test]
    fn non_private_permissions_warn_but_allow_valid_secrets() {
        // Файл 0644 більше не блокує локальне завантаження секретів.
        let path = std::env::temp_dir().join(format!(
            "mcm-secret-permissions-{}-{:?}.secrets",
            std::process::id(),
            std::thread::current().id()
        ));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true).mode(0o644);
        let mut file = options.open(&path).unwrap();
        file.write_all(b"ADMIN_PASSWORD=SecurePassword123\n")
            .unwrap();
        drop(file);
        let (admin, wifi) = load_secrets(&path, false).unwrap();
        assert_eq!(admin, "SecurePassword123");
        assert!(wifi.is_none());
        // Валідація обов'язкового Wi-Fi пароля залишається активною.
        assert!(load_secrets(&path, true).is_err());
        std::fs::remove_file(&path).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn symlinked_secrets_remain_forbidden() {
        // Символічні посилання як і раніше заборонені.
        use std::os::unix::fs::symlink;
        let base = std::env::temp_dir().join(format!(
            "mcm-secret-link-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir(&base).unwrap();
        let real = base.join("real.secrets");
        let link = base.join("link.secrets");
        std::fs::write(&real, "ADMIN_PASSWORD=SecurePassword123\n").unwrap();
        symlink(&real, &link).unwrap();
        assert!(load_secrets(&link, false).is_err());
        std::fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn secret_export_requires_external_file() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let out = std::env::temp_dir().join(format!("mcm-secret-test-{}.rsc", std::process::id()));
        assert!(
            export_secure(root, "hap-ac", &out, Path::new("/nonexistent/mcm-secrets")).is_err()
        );
        assert!(!out.exists());
    }
}

// Stage 19: регресійна перевірка точного коду, не аналізуючи текст.
#[cfg(test)]
mod regression_typed_setup_tests {
    use super::*;

    #[test]
    fn secrets_missing_file_is_structured_and_preserves_message() {
        let path = Path::new("/nonexistent/mcm-stage19-secrets-file");
        let error = load_secrets(path, false).unwrap_err();
        assert_eq!(error.code, SetupCode::SecretsMetadata);
        assert!(error.to_string().starts_with("Файл секретів недоступний:"));
    }

    #[test]
    fn missing_admin_secret_has_distinct_code() {
        let path = std::env::temp_dir().join(format!("mcm-stage19-admin-{}", std::process::id()));
        std::fs::write(&path, "WIFI_PASSWORD=WifiPass123\n").unwrap();
        let error = load_secrets(&path, false).unwrap_err();
        std::fs::remove_file(path).unwrap();
        assert_eq!(error.code, SetupCode::SecretsMissingAdmin);
        assert_eq!(error.to_string(), "Відсутній ADMIN_PASSWORD");
    }

    #[test]
    fn extension_error_survives_setup_boundary() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let result = export_secure(root, "test", Path::new("invalid.txt"), Path::new("missing"));
        match result {
            Err(SetupError::Issue(issue)) => {
                assert_eq!(issue.code, SetupCode::DestinationExtension)
            }
            other => panic!("unexpected setup outcome: {other:?}"),
        }
    }

    #[test]
    fn independent_profiles_keep_wifi_requirement() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        assert!(profile_requires_wifi(root, "hap-ac").unwrap());
        assert!(!profile_requires_wifi(root, "test").unwrap());
    }
}

#[cfg(test)]
mod regression_setup_runtime_tests {
    use super::*;
    use std::error::Error;

    #[test]
    fn runtime_codes_preserve_original_cli_messages() {
        // Рядковий CLI-контракт зберігаємо для кожної нової причини.
        let cases = [
            (SetupCode::RuntimeMissingAdmin, "Немає users.admin.name"),
            (
                SetupCode::RuntimeAdminGroup,
                "Адміністративна група повинна бути full",
            ),
            (
                SetupCode::RuntimeDuplicateAdmin,
                "Дублювання адміністративного користувача",
            ),
            (
                SetupCode::RuntimeUserGroup,
                "Непідтримувана група користувача",
            ),
            (SetupCode::RuntimeMissingWifi, "Відсутній WIFI_PASSWORD"),
            (
                SetupCode::RuntimeWifiDriver,
                "Непідтримуваний Wi-Fi драйвер",
            ),
            (
                SetupCode::RuntimeInvalidCharacter,
                "Сценарій містить заборонений символ",
            ),
            (
                SetupCode::RuntimeUnknownInstruction,
                "Невідома інструкція у плані RouterOS",
            ),
            (
                SetupCode::RuntimeWifiProfileNotCreated,
                "Не знайдено створення Wi-Fi Security Profile",
            ),
        ];
        for (code, message) in cases {
            let error = SetupIssue::new(code, message);
            assert_eq!(error.code, code);
            assert_eq!(error.to_string(), message);
            assert!(error.source().is_none());
        }
    }

    #[test]
    fn io_error_retains_source_without_changing_cli_text() {
        // Зберігаємо тип std::io::Error та безпечний текст окремо.
        let source = std::io::Error::from(std::io::ErrorKind::PermissionDenied);
        let detail = format!("Не вдалося прочитати секрети: {source}");
        let error = SetupIssue::with_io(SetupCode::SecretsRead, detail.clone(), source);
        assert_eq!(error.code, SetupCode::SecretsRead);
        assert_eq!(error.to_string(), detail);
        assert!(error.source().is_some());
        assert_eq!(
            error.source().unwrap().to_string(),
            std::io::Error::from(std::io::ErrorKind::PermissionDenied).to_string()
        );
    }

    #[test]
    fn missing_secret_file_preserves_real_io_source() {
        let path = std::env::temp_dir().join(format!(
            "mcm-stage20-missing-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let error = load_secrets(&path, false).expect_err("відсутній файл повинен відхилятися");
        assert_eq!(error.code, SetupCode::SecretsMetadata);
        let source = error.source().expect("джерело I/O повинно зберігатися");
        assert!(source.downcast_ref::<std::io::Error>().is_some());
        assert!(!error.to_string().contains("ADMIN_PASSWORD="));
    }
}

// Перевірка того, що типізовані першопричини не губляться на межі Setup.
#[cfg(test)]
mod regression_setup_error_boundary_tests {
    use super::*;
    use std::error::Error;
    #[test]
    fn setup_issue_survives_error_boundary() {
        let error = SetupError::Issue(SetupIssue::new(
            SetupCode::RuntimeMissingAdmin,
            "Немає users.admin.name",
        ));
        assert_eq!(error.to_string(), "Немає users.admin.name");
        assert!(error.source().is_some());
    }
    #[test]
    fn setup_io_source_survives_nested_error() {
        let issue = SetupIssue::with_io(
            SetupCode::DestinationCreate,
            "Помилка RSC",
            std::io::Error::from(std::io::ErrorKind::PermissionDenied),
        );
        let error = SetupError::Issue(issue);
        let source = error.source().expect("setup issue source");
        assert!(source.source().is_some());
    }
}

// Негативні регресії для ланцюжка SetupIssue -> початкова причина.
#[cfg(test)]
mod regression_source_chain_tests {
    use super::*;
    use std::error::Error;

    #[test]
    fn profile_error_retains_typed_source_and_original_text() {
        let original = crate::config::ProfileError::InvalidName;
        let message = original.to_string();
        let issue = SetupIssue::with_source(SetupCode::ProfileDirectory, message.clone(), original);
        assert_eq!(issue.to_string(), message);
        assert_eq!(issue.code, SetupCode::ProfileDirectory);
        assert!(issue
            .source()
            .unwrap()
            .downcast_ref::<crate::config::ProfileError>()
            .is_some());
    }

    #[test]
    fn nested_io_chain_survives_through_setup_error() {
        let profile = crate::config::ProfileError::ReadRouters {
            source: std::io::Error::from(std::io::ErrorKind::PermissionDenied),
        };
        let message = profile.to_string();
        let error = SetupError::Issue(SetupIssue::with_source(
            SetupCode::ProfileDirectory,
            message.clone(),
            profile,
        ));
        assert_eq!(error.to_string(), message);
        let issue = error.source().expect("SetupIssue");
        let profile = issue.source().expect("ProfileError");
        assert!(profile
            .downcast_ref::<crate::config::ProfileError>()
            .is_some());
        assert!(profile
            .source()
            .unwrap()
            .downcast_ref::<std::io::Error>()
            .is_some());
    }

    #[test]
    fn token_error_keeps_structured_cause_without_message_parsing() {
        let token = crate::modules::token("invalid name!", "wireless.security.name")
            .expect_err("invalid token");
        let message = token.to_string();
        let issue = SetupIssue::with_source(SetupCode::WifiSecurityName, message.clone(), token);
        assert_eq!(issue.to_string(), message);
        assert_eq!(issue.code, SetupCode::WifiSecurityName);
        assert!(issue.source().is_some());
    }
}

#[cfg(test)]
mod regression_final_setup_token_tests {
    use super::*;
    use std::error::Error;
    #[test]
    fn runtime_user_token_retains_first_cause_and_message() {
        let original = crate::modules::token("invalid user name", "users.name").unwrap_err();
        let expected = original.to_string();
        let error = SetupIssue::with_source(SetupCode::RuntimeUserName, expected.clone(), original);
        assert_eq!(error.to_string(), expected);
        assert_eq!(
            error.source().map(ToString::to_string).as_deref(),
            Some(expected.as_str())
        );
    }
}

// Stage 3: повторюваність BUILD без створення файлів, ключів чи скидання RouterOS.
#[cfg(test)]
mod stage3_build_determinism_tests {
    use super::*;

    #[test]
    fn no_secret_build_is_deterministic_for_each_declared_profile() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let mut checked = 0;
        for entry in std::fs::read_dir(root.join("routers")).unwrap() {
            let entry = entry.unwrap();
            if !entry.path().join("interfaces.toml").is_file() {
                continue;
            }
            let router = entry.file_name().into_string().unwrap();
            let first = render_runtime(root, &router, None).unwrap();
            let second = render_runtime(root, &router, None).unwrap();
            assert_eq!(first, second, "BUILD має бути детермінованим: {router}");
            assert!(
                !first.contains("/system reset-configuration"),
                "BUILD не виконує RESET"
            );
            checked += 1;
        }
        assert!(checked > 0);
    }
}
