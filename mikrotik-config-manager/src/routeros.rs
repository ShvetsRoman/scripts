#[cfg(unix)]
use std::os::unix::fs::DirBuilderExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};

use mikrotik_config_manager::typed_config::{read_typed, ConnectionConfig};

// Типізовані помилки SSH read-only; причина запуску лишається доступною через source().
#[derive(Debug)]
pub enum ReadOnlyError {
    UnsupportedCommand,
    Profile(crate::config::ProfileError),
    Connection(mikrotik_config_manager::typed_config::TypedReadError),
    MissingHome(ExpandHomeError),
    InvalidHost,
    InvalidPort,
    InvalidUser,
    Launch { source: std::io::Error },
    Exit { code: Option<i32>, stderr: String },
}
impl std::fmt::Display for ReadOnlyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnsupportedCommand => f.write_str("Unsupported remote command"),
            Self::Profile(error) => write!(f, "{error}"),
            Self::Connection(error) => write!(f, "{error}"),
            Self::MissingHome(error) => write!(f, "{error}"),
            Self::InvalidHost => f.write_str("Only IP address hosts are supported"),
            Self::InvalidPort => f.write_str("Invalid SSH port"),
            Self::InvalidUser => f.write_str("Invalid SSH user"),
            Self::Launch { source } => write!(f, "Failed to launch ssh: {source}"),
            Self::Exit { code, stderr } => write!(f, "SSH exit {code:?}: {stderr}"),
        }
    }
}
impl std::error::Error for ReadOnlyError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Profile(error) => Some(error),
            Self::Connection(error) => Some(error),
            Self::Launch { source } => Some(source),
            Self::MissingHome(error) => Some(error),
            _ => None,
        }
    }
}

// Лише коректні IPv4: для IPv6 потрібний окремий формат адреси SCP.
fn valid_ssh_host(host: &str) -> bool {
    host.parse::<std::net::Ipv4Addr>().is_ok()
}

pub fn run_read_only(root: &Path, router: &str, remote: &str) -> Result<String, ReadOnlyError> {
    // Лише два дозволені read-only запити, не довільна команда від користувача.
    if remote != "/system identity print" && remote != "/system resource print" {
        return Err(ReadOnlyError::UnsupportedCommand);
    }
    let dir = crate::config::router_dir(root, router).map_err(ReadOnlyError::Profile)?;
    let config: ConnectionConfig =
        read_typed(&dir.join("connection.toml")).map_err(ReadOnlyError::Connection)?;
    let conn = &config.connection;
    let host = conn.host.as_str();
    let user = conn.user.as_str();
    let port = conn.port;
    if !valid_ssh_host(host) {
        return Err(ReadOnlyError::InvalidHost);
    }
    if port == 0 {
        return Err(ReadOnlyError::InvalidPort);
    }
    if user.is_empty()
        || !user
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
    {
        return Err(ReadOnlyError::InvalidUser);
    }
    let key = expand_home(&conn.identity_file).map_err(ReadOnlyError::MissingHome)?;
    let target = format!("{user}@{host}");
    let output = Command::new("ssh")
        .args([
            "-i",
            &key,
            "-p",
            &port.to_string(),
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "StrictHostKeyChecking=yes",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=5",
            "--",
            &target,
            remote,
        ])
        .output()
        .map_err(|source| ReadOnlyError::Launch { source })?;
    if !output.status.success() {
        return Err(ReadOnlyError::Exit {
            code: output.status.code(),
            stderr: String::from_utf8_lossy(&output.stderr).trim().to_owned(),
        });
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}
// Розгортання HOME: зберігаємо std::env::VarError без рядкового fallback.
#[derive(Debug)]
pub enum ExpandHomeError {
    Missing(std::env::VarError),
}
impl std::fmt::Display for ExpandHomeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Missing(_) => f.write_str("HOME is not set"),
        }
    }
}
impl std::error::Error for ExpandHomeError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Missing(source) => Some(source),
        }
    }
}
fn expand_home(p: &str) -> Result<String, ExpandHomeError> {
    if let Some(rest) = p.strip_prefix("~/") {
        let home = std::env::var("HOME").map_err(ExpandHomeError::Missing)?;
        Ok(format!("{home}/{rest}"))
    } else {
        Ok(p.to_string())
    }
}

// Параметри з'єднання читаємо лише з двох підтримуваних профілів.
// Значення перевіряємо до передачі аргументів зовнішнім програмам.
struct UploadConnection {
    host: String,
    user: String,
    port: u16,
    key: String,
}

// Типізована перевірка конфігурації upload без втрати першопричини.
#[derive(Debug)]
pub(crate) enum UploadConnectionError {
    Profile(crate::config::ProfileError),
    Toml(mikrotik_config_manager::typed_config::TypedReadError),
    Home(ExpandHomeError),
    Host,
    User,
    Port,
}
impl std::fmt::Display for UploadConnectionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Profile(error) => write!(f, "{error}"),
            Self::Toml(error) => write!(f, "{error}"),
            Self::Home(error) => write!(f, "{error}"),
            Self::Host => f.write_str("SSH host має бути IP-адресою"),
            Self::User => f.write_str("Некоректне ім'я SSH-користувача"),
            Self::Port => f.write_str("SSH-порт не може бути нульовим"),
        }
    }
}
impl std::error::Error for UploadConnectionError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Profile(error) => Some(error),
            Self::Toml(error) => Some(error),
            Self::Home(error) => Some(error),
            _ => None,
        }
    }
}

fn upload_connection(root: &Path, router: &str) -> Result<UploadConnection, UploadConnectionError> {
    let dir = crate::config::router_dir(root, router).map_err(UploadConnectionError::Profile)?;
    let config: ConnectionConfig =
        read_typed(&dir.join("connection.toml")).map_err(UploadConnectionError::Toml)?;
    let conf = config.connection;
    let host = conf.host;
    let user = conf.user;
    let port = conf.port;
    let key = expand_home(&conf.identity_file).map_err(UploadConnectionError::Home)?;
    if !valid_ssh_host(&host) {
        return Err(UploadConnectionError::Host);
    }
    if user.is_empty()
        || !user
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        return Err(UploadConnectionError::User);
    }
    if port == 0 {
        return Err(UploadConnectionError::Port);
    }
    Ok(UploadConnection {
        host,
        user,
        port,
        key,
    })
}

// Зберігаємо лише безпечне ім'я у корені Files RouterOS; шлях не може
// потрапити до синтаксису CLI RouterOS або віддаленого shell.
// Причини відмови локального RSC визначаємо без аналізу тексту.
#[derive(Debug)]
pub(crate) enum UploadScriptError {
    Metadata(std::io::Error),
    NotRegular,
    MissingName,
    UnsafeName,
    Read(std::io::Error),
    DestructiveCommand,
}
impl std::fmt::Display for UploadScriptError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Metadata(error) => write!(f, "Локальний .rsc недоступний: {error}"),
            Self::NotRegular => f.write_str("Локальний .rsc має бути звичайним файлом, не symlink"),
            Self::MissingName => f.write_str("Некоректне ім'я .rsc"),
            Self::UnsafeName => f.write_str("Ім'я файла має бути безпечним ASCII-іменем із .rsc"),
            Self::Read(error) => write!(f, "Не вдалося прочитати .rsc: {error}"),
            Self::DestructiveCommand => {
                f.write_str(".rsc містить команди RESET/reboot; передавання заблоковано")
            }
        }
    }
}
impl std::error::Error for UploadScriptError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Metadata(error) | Self::Read(error) => Some(error),
            _ => None,
        }
    }
}

fn checked_rsc_name(path: &Path) -> Result<String, UploadScriptError> {
    let metadata = std::fs::symlink_metadata(path).map_err(UploadScriptError::Metadata)?;
    if !metadata.file_type().is_file() || metadata.file_type().is_symlink() {
        return Err(UploadScriptError::NotRegular);
    }
    let name = path
        .file_name()
        .and_then(|n| n.to_str())
        .ok_or(UploadScriptError::MissingName)?;
    if !name.ends_with(".rsc")
        || name.ends_with(".auto.rsc")
        || name.contains("..")
        || name.len() > 80
        || !name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_'))
        || name.starts_with('.')
    {
        return Err(UploadScriptError::UnsafeName);
    }
    Ok(name.to_string())
}

// Спосіб автентифікації визначаємо ДО SCP або RESET.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum AuthMode {
    Key,
    Password,
}

fn common_ssh_options(command: &mut Command, conn: &UploadConnection, mode: AuthMode) {
    command.args([
        "-o",
        "StrictHostKeyChecking=yes",
        "-o",
        "ConnectTimeout=8",
        "-o",
        "ConnectionAttempts=1",
    ]);
    match mode {
        AuthMode::Key => {
            command.args([
                "-i",
                &conn.key,
                "-o",
                "IdentitiesOnly=yes",
                "-o",
                "BatchMode=yes",
                "-o",
                "PreferredAuthentications=publickey",
                "-o",
                "PasswordAuthentication=no",
                "-o",
                "KbdInteractiveAuthentication=no",
            ]);
        }
        AuthMode::Password => {
            // Ті самі параметри, з якими парольна SSH/SCP авторизація
            // користувача RouterOS перевірена вручну. Пароль не зберігаємо.
            command.args([
                "-o",
                "BatchMode=no",
                "-o",
                "PubkeyAuthentication=no",
                "-o",
                "PreferredAuthentications=password,keyboard-interactive",
                "-o",
                "PasswordAuthentication=yes",
                "-o",
                "KbdInteractiveAuthentication=yes",
                "-o",
                "NumberOfPasswordPrompts=1",
            ]);
        }
    }
}

fn key_auth_failed(stderr: &str) -> bool {
    stderr.contains("Permission denied") || stderr.contains("Authentications that can continue")
}

// Помилка автентифікації/виконання SSH з оригінальним I/O джерелом.
// Текст Display залишається сумісним із попереднім CLI.
#[derive(Debug)]
pub(crate) enum SshAuthError {
    Spawn(std::io::Error),
    KeyRejected(String),
    AuthenticationRejected,
    ProcessFailed { code: Option<i32>, details: String },
}
impl std::fmt::Display for SshAuthError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Spawn(error) => write!(f, "Не вдалося запустити SSH: {error}"),
            Self::KeyRejected(detail) => write!(f, "SSH ключ: {detail}"),
            Self::AuthenticationRejected => {
                f.write_str("RouterOS не підтвердив парольну SSH-автентифікацію")
            }
            Self::ProcessFailed { code, details } => {
                write!(f, "SSH завершився з кодом {code:?}{details}")
            }
        }
    }
}
impl std::error::Error for SshAuthError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Spawn(error) => Some(error),
            _ => None,
        }
    }
}

fn select_auth(conn: &UploadConnection) -> Result<AuthMode, SshAuthError> {
    // Перша спроба — ключ. Виконуємо тільки read-only команду.
    if Path::new(&conn.key).is_file() {
        let mut command = Command::new("ssh");
        common_ssh_options(&mut command, conn, AuthMode::Key);
        let output = command
            .args([
                "-p",
                &conn.port.to_string(),
                "--",
                &format!("{}@{}", conn.user, conn.host),
                "/system identity print",
            ])
            .output()
            .map_err(SshAuthError::Spawn)?;
        if output.status.success() {
            return Ok(AuthMode::Key);
        }
        let error = String::from_utf8_lossy(&output.stderr);
        if !key_auth_failed(&error) {
            return Err(SshAuthError::KeyRejected(error.trim().to_owned()));
        }
    }
    // Лише за відсутності ключа або відмови в автентифікації.
    eprintln!("[INFO] SSH-ключ недоступний або відхилений; спроба входу з паролем RouterOS.");
    let identity = ssh_execute_mode(conn, "/system identity print", AuthMode::Password)?;
    if identity.trim().is_empty() {
        return Err(SshAuthError::AuthenticationRejected);
    }
    Ok(AuthMode::Password)
}

fn ssh_execute_mode(
    conn: &UploadConnection,
    remote: &str,
    mode: AuthMode,
) -> Result<String, SshAuthError> {
    let mut command = Command::new("ssh");
    common_ssh_options(&mut command, conn, mode);
    command.args([
        "-p",
        &conn.port.to_string(),
        "--",
        &format!("{}@{}", conn.user, conn.host),
        remote,
    ]);
    if mode == AuthMode::Password {
        // SSH запитує пароль у терміналі, не зберігаємо його в логах або файлах.
        command
            .stdin(std::process::Stdio::inherit())
            .stderr(std::process::Stdio::inherit());
    }
    let out = command.output().map_err(SshAuthError::Spawn)?;
    if !out.status.success() {
        return Err(SshAuthError::ProcessFailed {
            code: out.status.code(),
            details: if mode == AuthMode::Key {
                format!(": {}", String::from_utf8_lossy(&out.stderr).trim())
            } else {
                String::new()
            },
        });
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_owned())
}

// Одне SSH-з'єднання на всю операцію upload. Сокет ізольований від інших користувачів.
static SESSION_SEQUENCE: AtomicUsize = AtomicUsize::new(0);

// Типізовані збої SSH ControlMaster та SCP без повторного аналізу їхнього тексту.
#[derive(Debug)]
pub(crate) enum UploadSessionError {
    DirectoryCreate(std::io::Error),
    DirectoryExhausted,
    DirectoryPermissions(std::io::Error),
    MasterStopped,
    KeyRejected(String),
    PasswordRejected,
    MasterUnavailable,
    MasterLost,
    ScpLost,
    MasterLaunch(std::io::Error),
    SshLaunch(std::io::Error),
    SshExit(Option<i32>),
    ScpLaunch(std::io::Error),
    ScpExit(Option<i32>),
}
impl std::fmt::Display for UploadSessionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::DirectoryCreate(e) => write!(f, "Не вдалося створити каталог SSH: {e}"),
            Self::DirectoryExhausted => f.write_str("Не вдалося створити приватний каталог SSH"),
            Self::DirectoryPermissions(e) => write!(f, "Не вдалося захистити каталог SSH: {e}"),
            Self::MasterStopped => {
                f.write_str("SSH ControlMaster завершився одразу після встановлення")
            }
            Self::KeyRejected(stderr) => write!(f, "SSH-ключ: {}", stderr.trim()),
            Self::PasswordRejected => f.write_str("Парольну SSH-автентифікацію відхилено"),
            Self::MasterUnavailable => {
                f.write_str("SSH ControlMaster недоступний після авторизації")
            }
            Self::MasterLost => {
                f.write_str("Головне SSH-з'єднання втрачено; повторний вхід заборонено")
            }
            Self::ScpLost => f.write_str("SSH-з'єднання втрачено перед SCP"),
            Self::MasterLaunch(e) => write!(f, "Не вдалося запустити SSH: {e}"),
            Self::SshLaunch(e) => write!(f, "Помилка SSH: {e}"),
            Self::SshExit(code) => write!(f, "SSH завершився з кодом {code:?}"),
            Self::ScpLaunch(e) => write!(f, "Помилка запуску SCP: {e}"),
            Self::ScpExit(code) => write!(f, "SCP завершився з кодом {code:?}"),
        }
    }
}
impl std::error::Error for UploadSessionError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::DirectoryCreate(e)
            | Self::DirectoryPermissions(e)
            | Self::MasterLaunch(e)
            | Self::SshLaunch(e)
            | Self::ScpLaunch(e) => Some(e),
            _ => None,
        }
    }
}

struct UploadSession<'a> {
    conn: &'a UploadConnection,
    dir: PathBuf,
    socket: PathBuf,
}

impl<'a> UploadSession<'a> {
    fn open(conn: &'a UploadConnection) -> Result<Self, UploadSessionError> {
        let mut directory = None;
        for _ in 0..16 {
            let seq = SESSION_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!("mcm-ssh-{}-{seq}", std::process::id()));
            // Каталог одразу створюється приватним: немає проміжного стану з ширшими правами.
            let mut builder = std::fs::DirBuilder::new();
            #[cfg(unix)]
            builder.mode(0o700);
            match builder.create(&path) {
                Ok(()) => {
                    directory = Some(path);
                    break;
                }
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(UploadSessionError::DirectoryCreate(e)),
            }
        }
        let dir = directory.ok_or(UploadSessionError::DirectoryExhausted)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            if let Err(e) = std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700)) {
                let _ = std::fs::remove_dir(&dir);
                return Err(UploadSessionError::DirectoryPermissions(e));
            }
        }
        let socket = dir.join("s");
        let session = Self { conn, dir, socket };
        // Ключ перевіряємо окремо. Помилка перевірки host key / мережі НЕ дозволяє fallback.
        if Path::new(&conn.key).is_file() {
            let attempt = session.launch_master(AuthMode::Key, false)?;
            if attempt.0 {
                if !session.is_alive() {
                    return Err(UploadSessionError::MasterStopped);
                }
                return Ok(session);
            }
            if !key_auth_failed(&attempt.1) {
                return Err(UploadSessionError::KeyRejected(attempt.1));
            }
        }
        eprintln!(
            "[INFO] SSH-ключ недоступний або відхилений; один пароль для всієї операції upload."
        );
        let success = session.launch_master(AuthMode::Password, true)?.0;
        if !success {
            return Err(UploadSessionError::PasswordRejected);
        }
        if !session.is_alive() {
            return Err(UploadSessionError::MasterUnavailable);
        }
        Ok(session)
    }

    fn launch_master(
        &self,
        mode: AuthMode,
        interactive: bool,
    ) -> Result<(bool, String), UploadSessionError> {
        let mut command = Command::new("ssh");
        common_ssh_options(&mut command, self.conn, mode);
        command.args(["-M", "-N", "-f", "-S"]);
        command.arg(&self.socket);
        command.args([
            "-o",
            "ControlMaster=yes",
            "-o",
            "ControlPersist=no",
            "-p",
            &self.conn.port.to_string(),
            "--",
        ]);
        command.arg(format!("{}@{}", self.conn.user, self.conn.host));
        if interactive {
            // Спадкуємо TTY, щоб пароль вводився безпосередньо OpenSSH.
            let status = command
                .stdin(std::process::Stdio::inherit())
                .stdout(std::process::Stdio::inherit())
                .stderr(std::process::Stdio::inherit())
                .status()
                .map_err(UploadSessionError::MasterLaunch)?;
            Ok((status.success(), String::new()))
        } else {
            let output = command.output().map_err(UploadSessionError::MasterLaunch)?;
            Ok((
                output.status.success(),
                String::from_utf8_lossy(&output.stderr).to_string(),
            ))
        }
    }

    fn common_client(&self, command: &mut Command) {
        // Якщо сокет раптом зник, НЕ допускаємо нового парольного або ключового входу.
        command
            .arg("-o")
            .arg(format!("ControlPath={}", self.socket.display()));
        command.args([
            "-o",
            "ControlMaster=auto",
            "-o",
            "BatchMode=yes",
            "-o",
            "NumberOfPasswordPrompts=0",
            "-o",
            "PubkeyAuthentication=no",
            "-o",
            "PasswordAuthentication=no",
            "-o",
            "KbdInteractiveAuthentication=no",
            "-o",
            "StrictHostKeyChecking=yes",
            "-o",
            "ConnectTimeout=8",
            "-o",
            "ConnectionAttempts=1",
        ]);
    }

    fn is_alive(&self) -> bool {
        let mut check = Command::new("ssh");
        check
            .arg("-S")
            .arg(&self.socket)
            .args(["-O", "check", "-p", &self.conn.port.to_string(), "--"])
            .arg(format!("{}@{}", self.conn.user, self.conn.host));
        check.output().map(|o| o.status.success()).unwrap_or(false)
    }

    fn execute(&self, remote: &str) -> Result<String, UploadSessionError> {
        if !self.is_alive() {
            return Err(UploadSessionError::MasterLost);
        }
        let mut command = Command::new("ssh");
        self.common_client(&mut command);
        command.args(["-p", &self.conn.port.to_string(), "--"]);
        command
            .arg(format!("{}@{}", self.conn.user, self.conn.host))
            .arg(remote);
        let output = command.output().map_err(UploadSessionError::SshLaunch)?;
        if !output.status.success() {
            return Err(UploadSessionError::SshExit(output.status.code()));
        }
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    }

    fn scp_command(&self, local: &Path, name: &str) -> Command {
        let mut command = Command::new("scp");
        self.common_client(&mut command);
        // OpenSSH 9+ uses SFTP by default. RouterOS requires legacy SCP protocol.
        command.args(["-O", "-P", &self.conn.port.to_string(), "--"]);
        command
            .arg(local)
            .arg(format!("{}@{}:{name}", self.conn.user, self.conn.host));
        command
    }

    fn copy(&self, local: &Path, name: &str) -> Result<(), UploadSessionError> {
        if !self.is_alive() {
            return Err(UploadSessionError::ScpLost);
        }
        let mut command = self.scp_command(local, name);
        let status = command.status().map_err(UploadSessionError::ScpLaunch)?;
        if !status.success() {
            return Err(UploadSessionError::ScpExit(status.code()));
        }
        Ok(())
    }
}

impl Drop for UploadSession<'_> {
    fn drop(&mut self) {
        // Закриваємо тільки власний master та прибираємо власний тимчасовий каталог.
        let mut close = Command::new("ssh");
        let _ = close
            .arg("-S")
            .arg(&self.socket)
            .args(["-O", "exit", "-p", &self.conn.port.to_string(), "--"])
            .arg(format!("{}@{}", self.conn.user, self.conn.host))
            .output();
        let _ = std::fs::remove_file(&self.socket);
        let _ = std::fs::remove_dir(&self.dir);
    }
}

// Типізована read-only діагностика: SSH-автентифікація зберігає першопричину.
#[derive(Debug)]
pub(crate) enum VerifyConnectionError {
    Connection(Box<UploadConnectionError>),
    Authentication(SshAuthError),
    Identity(SshAuthError),
    Resource(SshAuthError),
    EmptyDiagnostics,
}
impl std::fmt::Display for VerifyConnectionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Connection(error) => write!(f, "{error}"),
            Self::Authentication(error) => write!(f, "{error}"),
            Self::Identity(error) => write!(f, "Read-only identity: {error}"),
            Self::Resource(error) => write!(f, "Read-only resource: {error}"),
            Self::EmptyDiagnostics => f.write_str("RouterOS повернув порожню діагностику"),
        }
    }
}
impl std::error::Error for VerifyConnectionError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Connection(error) => Some(error.as_ref()),
            Self::Authentication(error) | Self::Identity(error) | Self::Resource(error) => {
                Some(error)
            }
            Self::EmptyDiagnostics => None,
        }
    }
}

// Діагностика не виконує жодної зміни на пристрої.
pub(crate) fn verify_connection(
    root: &Path,
    router: &str,
) -> Result<String, VerifyConnectionError> {
    let conn = upload_connection(root, router)
        .map_err(|error| VerifyConnectionError::Connection(Box::new(error)))?;
    let mode = select_auth(&conn).map_err(VerifyConnectionError::Authentication)?;
    let identity = ssh_execute_mode(&conn, "/system identity print", mode)
        .map_err(VerifyConnectionError::Identity)?;
    let resource = ssh_execute_mode(&conn, "/system resource print", mode)
        .map_err(VerifyConnectionError::Resource)?;
    if identity.trim().is_empty() || resource.trim().is_empty() {
        return Err(VerifyConnectionError::EmptyDiagnostics);
    }
    Ok(format!(
        "[PASS] SSH та RouterOS read-only\n{identity}\n{resource}"
    ))
}

// Перевіряємо, що сценарій є звичайним .rsc без команди RESET усередині.
// Автоматичний файл *.auto.rsc не використовуємо (він запускається при копіюванні).
fn validate_upload_script(path: &Path) -> Result<(), UploadScriptError> {
    let body = std::fs::read_to_string(path).map_err(UploadScriptError::Read)?;
    if body.lines().any(|line| {
        let line = line.trim_start();
        !line.starts_with('#')
            && (line.contains("reset-configuration") || line.contains("/system reboot"))
    }) {
        return Err(UploadScriptError::DestructiveCommand);
    }
    Ok(())
}

// Типізована зовнішня межа upload: усі внутрішні причини залишаються доступними.
#[derive(Debug)]
pub(crate) enum UploadError {
    Script(UploadScriptError),
    Connection(Box<UploadConnectionError>),
    Session(UploadSessionError),
}
impl std::fmt::Display for UploadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Script(error) => write!(f, "{error}"),
            Self::Connection(error) => write!(f, "{error}"),
            Self::Session(error) => write!(f, "{error}"),
        }
    }
}
impl std::error::Error for UploadError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Script(error) => Some(error),
            // Повертаємо внутрішню типізовану причину, а не Box-обгортку.
            Self::Connection(error) => Some(error.as_ref()),
            Self::Session(error) => Some(error),
        }
    }
}

pub(crate) fn upload(root: &Path, router: &str, local: &Path) -> Result<String, UploadError> {
    // Файл перевіряємо до будь-якого мережевого підключення.
    let name = checked_rsc_name(local).map_err(UploadError::Script)?;
    validate_upload_script(local).map_err(UploadError::Script)?;
    let conn = upload_connection(root, router)
        .map_err(|error| UploadError::Connection(Box::new(error)))?;
    let session = UploadSession::open(&conn).map_err(UploadError::Session)?;
    upload_with_session_typed(local, &name, &session)?;
    Ok(name)
}

// SCP перезаписує однойменний RSC без перевірок його наявності та розміру в RouterOS.
fn upload_with_session_typed(
    local: &Path,
    name: &str,
    session: &UploadSession<'_>,
) -> Result<(), UploadError> {
    session.copy(local, name).map_err(UploadError::Session)
}

// Відмова RESET зберігає доменну причину, а після відправлення — статус UNKNOWN.
#[derive(Debug)]
pub(crate) enum ResetError {
    NotConfirmed,
    Read(std::io::Error),
    InvalidRuntime,
    Script(UploadScriptError),
    Connection(Box<UploadConnectionError>),
    Session(Box<UploadSessionError>),
    Upload(Box<UploadError>),
    RemoteFileMissing(String),
    RemoteFileCheckInvalid(String),
    Unknown {
        name: String,
        source: Box<UploadSessionError>,
    },
}
impl std::fmt::Display for ResetError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotConfirmed => f.write_str("RESET не запущено: потрібен прапорець --reset"),
            Self::Read(error) => write!(f, "Не вдалося прочитати сценарій перед RESET: {error}"),
            Self::InvalidRuntime => f.write_str("RESET заблоковано: потрібен повний захищений setup.rsc із runtime-контролем"),
            Self::Script(error) => write!(f, "{error}"),
            Self::Connection(error) => write!(f, "{error}"),
            Self::Session(error) => write!(f, "{error}"),
            Self::Upload(error) => write!(f, "{error}"),
            Self::RemoteFileMissing(name) => write!(f, "RESET заблоковано: файл {name} не знайдено в RouterOS після SCP"),
            Self::RemoteFileCheckInvalid(output) => write!(f, "RESET заблоковано: RouterOS повернув некоректний результат перевірки файла: {output:?}"),
            Self::Unknown { name, source } => write!(f, "Стан RESET НЕВІДОМИЙ для {name}: {source}. Не повторюйте upload --reset; перевірте консоль RouterOS та журнал MCM"),
        }
    }
}
impl std::error::Error for ResetError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Read(error) => Some(error),
            Self::Script(error) => Some(error),
            Self::Connection(error) => Some(error.as_ref()),
            Self::Session(error) => Some(error.as_ref()),
            Self::Upload(error) => Some(error.as_ref()),
            Self::Unknown { source, .. } => Some(source.as_ref()),
            Self::NotConfirmed
            | Self::InvalidRuntime
            | Self::RemoteFileMissing(_)
            | Self::RemoteFileCheckInvalid(_) => None,
        }
    }
}

pub(crate) fn upload_and_reset(
    root: &Path,
    router: &str,
    local: &Path,
    confirmed: bool,
) -> Result<String, ResetError> {
    if !confirmed {
        return Err(ResetError::NotConfirmed);
    }
    // Зчитування сценарію та всі перевірки ДО відправлення RESET.
    let contents = std::fs::read_to_string(local).map_err(ResetError::Read)?;
    if !contents.contains("# MCM_SECURE_RUNTIME:")
        || !contents.contains("MCM: COMPLETE")
        || !contents.contains("MCM_SETUP_FAILED")
    {
        return Err(ResetError::InvalidRuntime);
    }
    let name = checked_rsc_name(local).map_err(ResetError::Script)?;
    validate_upload_script(local).map_err(ResetError::Script)?;
    let conn =
        upload_connection(root, router).map_err(|error| ResetError::Connection(Box::new(error)))?;
    let session =
        UploadSession::open(&conn).map_err(|error| ResetError::Session(Box::new(error)))?;
    upload_with_session_typed(local, &name, &session)
        .map_err(|error| ResetError::Upload(Box::new(error)))?;
    // Перевірка ТІЛЬКИ після SCP і ТІЛЬКИ перед RESET: файл має існувати.
    // Жодних перевірок унікальності або розміру.
    let remote_check = remote_rsc_check_command(&name);
    let output = session
        .execute(&remote_check)
        .map_err(|error| ResetError::Session(Box::new(error)))?;
    check_remote_rsc_presence(&name, &output)?;
    let cmd = format!(
        "/system reset-configuration no-defaults=yes skip-backup=yes run-after-reset={name}"
    );
    // FnOnce: після першої спроби жодних повторів, навіть коли стан SSH невідомий.
    dispatch_reset_once(|| session.execute(&cmd), &name)
}

// Ім'я вже валідоване checked_rsc_name (безпечні ASCII символи).
fn remote_rsc_check_command(name: &str) -> String {
    format!("/file print count-only where name=\"{name}\"")
}

fn check_remote_rsc_presence(name: &str, output: &str) -> Result<(), ResetError> {
    // count-only повертає число; 1 чи більше означає наявність, не унікальність.
    match output.trim().parse::<u64>() {
        Ok(0) => Err(ResetError::RemoteFileMissing(name.to_owned())),
        Ok(_) => Ok(()),
        Err(_) => Err(ResetError::RemoteFileCheckInvalid(output.to_owned())),
    }
}

fn dispatch_reset_once<F>(send: F, name: &str) -> Result<String, ResetError>
where
    F: FnOnce() -> Result<String, UploadSessionError>,
{
    match send() {
        Ok(_) => Ok(format!(
            "Команду RESET передано для {name}; виконання після перезавантаження не перевірено"
        )),
        Err(source) => Err(ResetError::Unknown {
            name: name.to_owned(),
            source: Box::new(source),
        }),
    }
}

#[cfg(test)]
mod typed_public_upload_error_tests {
    use super::*;
    use std::error::Error;
    #[test]
    fn missing_file_keeps_original_io_cause() {
        let missing = std::env::temp_dir().join(format!(
            "mcm-stage23-missing-{}-{}.rsc",
            std::process::id(),
            823111
        ));
        let error = upload(Path::new("."), "test", &missing).expect_err("Відсутній файл");
        assert!(matches!(
            error,
            UploadError::Script(UploadScriptError::Metadata(_))
        ));
        assert!(error.source().and_then(Error::source).is_some());
        assert!(error.to_string().starts_with("Локальний .rsc недоступний:"));
    }
    #[test]
    fn connection_error_remains_structured_and_small() {
        // Вкладена причина зберігається, а зовнішня помилка компактна для Result.
        let error = UploadError::Connection(Box::new(UploadConnectionError::Host));
        assert!(matches!(error, UploadError::Connection(_)));
        assert!(std::error::Error::source(&error).is_some());
        assert!(std::mem::size_of::<UploadError>() <= 128);
    }
}

#[cfg(test)]
mod upload_tests {
    use super::*;
    #[test]
    fn upload_script_rejects_destructive_command_and_allows_comments() {
        let path =
            std::env::temp_dir().join(format!("mcm-upload-validation-{}.rsc", std::process::id()));
        std::fs::write(&path, "# /system reboot\n/ip address print\n").unwrap();
        assert!(validate_upload_script(&path).is_ok());
        std::fs::write(&path, "/system reboot\n").unwrap();
        assert!(matches!(
            validate_upload_script(&path),
            Err(UploadScriptError::DestructiveCommand)
        ));
        std::fs::remove_file(&path).unwrap();
    }
    #[test]
    fn read_only_connection_errors_are_typed_and_distinct() {
        assert_ne!(
            ReadOnlyError::InvalidHost.to_string(),
            ReadOnlyError::InvalidPort.to_string()
        );
        assert_ne!(
            ReadOnlyError::InvalidUser.to_string(),
            ReadOnlyError::InvalidPort.to_string()
        );
    }
    #[test]
    fn ssh_host_rejects_invalid_ipv4_and_unbracketed_ipv6() {
        for bad in ["", "1.1.1.1.1", "2001:db8::1", "abc", "192.168.56.999"] {
            assert!(!valid_ssh_host(bad), "{bad}");
        }
        assert!(valid_ssh_host("192.168.56.2"));
    }
    #[test]
    fn auth_fallback_only_for_rejected_credentials() {
        assert!(key_auth_failed("Permission denied (publickey)."));
        assert!(!key_auth_failed("Host key verification failed."));
        assert!(!key_auth_failed("Connection timed out"));
    }

    #[test]
    fn password_options_match_verified_ssh_and_scp() {
        let conn = UploadConnection {
            host: "192.0.2.1".into(),
            user: "admin".into(),
            port: 22,
            key: "/tmp/mcm-example-key".into(),
        };
        for binary in ["ssh", "scp"] {
            let mut command = Command::new(binary);
            common_ssh_options(&mut command, &conn, AuthMode::Password);
            let args: Vec<_> = command
                .get_args()
                .map(|a| a.to_string_lossy().into_owned())
                .collect();
            let contains_pair = |key: &str| {
                args.windows(2)
                    .any(|pair| pair[0] == "-o" && pair[1] == key)
            };
            for option in [
                "StrictHostKeyChecking=yes",
                "BatchMode=no",
                "PubkeyAuthentication=no",
                "PreferredAuthentications=password,keyboard-interactive",
                "PasswordAuthentication=yes",
                "KbdInteractiveAuthentication=yes",
                "NumberOfPasswordPrompts=1",
            ] {
                assert!(
                    contains_pair(option),
                    "Відсутній параметр {option} для {binary}"
                );
            }
            assert!(!args.iter().any(|arg| arg == "-O"));
            assert!(!args.iter().any(|arg| arg == "-i"));
        }
    }

    #[test]
    fn key_options_do_not_ask_for_password() {
        let conn = UploadConnection {
            host: "192.0.2.1".into(),
            user: "admin".into(),
            port: 22,
            key: "/tmp/mcm-example-key".into(),
        };
        let mut command = Command::new("ssh");
        common_ssh_options(&mut command, &conn, AuthMode::Key);
        let args: Vec<_> = command
            .get_args()
            .map(|a| a.to_string_lossy().into_owned())
            .collect();
        for option in [
            "BatchMode=yes",
            "PasswordAuthentication=no",
            "KbdInteractiveAuthentication=no",
        ] {
            assert!(args
                .windows(2)
                .any(|pair| pair[0] == "-o" && pair[1] == option));
        }
        assert!(args
            .windows(2)
            .any(|pair| pair[0] == "-i" && pair[1] == conn.key));
    }

    #[test]
    fn multiplexed_client_disables_all_fallback_authentication() {
        let conn = UploadConnection {
            host: "192.0.2.1".into(),
            user: "admin".into(),
            port: 22,
            key: "/tmp/key".into(),
        };
        let session = UploadSession {
            conn: &conn,
            dir: PathBuf::from("/tmp/mcm-test-unused"),
            socket: PathBuf::from("/tmp/mcm-test-unused/s"),
        };
        let mut cmd = Command::new("scp");
        session.common_client(&mut cmd);
        let args: Vec<_> = cmd
            .get_args()
            .map(|a| a.to_string_lossy().to_string())
            .collect();
        for option in [
            "ControlMaster=auto",
            "BatchMode=yes",
            "PubkeyAuthentication=no",
            "PasswordAuthentication=no",
            "KbdInteractiveAuthentication=no",
            "StrictHostKeyChecking=yes",
        ] {
            assert!(args
                .windows(2)
                .any(|pair| pair[0] == "-o" && pair[1] == option));
        }
        assert!(args
            .windows(2)
            .any(|pair| pair[0] == "-o" && pair[1] == "ControlPath=/tmp/mcm-test-unused/s"));
    }

    #[test]
    fn scp_uses_legacy_protocol_with_shared_ssh_session() {
        let conn = UploadConnection {
            host: "192.0.2.1".into(),
            user: "admin".into(),
            port: 2222,
            key: "/tmp/key".into(),
        };
        let session = UploadSession {
            conn: &conn,
            dir: PathBuf::from("/tmp/mcm-test-unused"),
            socket: PathBuf::from("/tmp/mcm-test-unused/s"),
        };
        let command = session.scp_command(Path::new("/tmp/2.rsc"), "2.rsc");
        let args: Vec<_> = command
            .get_args()
            .map(|arg| arg.to_string_lossy().into_owned())
            .collect();
        assert!(args.iter().any(|arg| arg == "-O"));
        assert!(args.windows(2).any(|pair| pair == ["-P", "2222"]));
        assert!(args.iter().any(|arg| arg == "admin@192.0.2.1:2.rsc"));
        assert!(args
            .iter()
            .any(|arg| arg == "ControlPath=/tmp/mcm-test-unused/s"));
    }

    #[test]
    fn remote_rsc_must_exist_after_scp_before_reset() {
        assert_eq!(
            remote_rsc_check_command("2.rsc"),
            "/file print count-only where name=\"2.rsc\""
        );
        assert!(check_remote_rsc_presence("2.rsc", "1\n").is_ok());
        assert!(check_remote_rsc_presence("2.rsc", "2\n").is_ok());
        assert!(matches!(
            check_remote_rsc_presence("2.rsc", "0"),
            Err(ResetError::RemoteFileMissing(_))
        ));
        assert!(matches!(
            check_remote_rsc_presence("2.rsc", ""),
            Err(ResetError::RemoteFileCheckInvalid(_))
        ));
        assert!(matches!(
            check_remote_rsc_presence("2.rsc", "unexpected"),
            Err(ResetError::RemoteFileCheckInvalid(_))
        ));
    }

    #[test]
    fn reset_dispatch_is_single_attempt_even_on_connection_loss() {
        let attempts = std::cell::Cell::new(0);
        let outcome = dispatch_reset_once(
            || {
                attempts.set(attempts.get() + 1);
                Err(UploadSessionError::SshLaunch(std::io::Error::new(
                    std::io::ErrorKind::ConnectionReset,
                    "Connection reset by peer",
                )))
            },
            "safe.rsc",
        );
        assert_eq!(attempts.get(), 1);
        let error = outcome.unwrap_err();
        assert!(error.to_string().contains("НЕВІДОМИЙ"));
        assert!(error.to_string().contains("Не повторюйте"));
    }

    #[test]
    fn reset_dispatch_success_does_not_claim_import_complete() {
        let msg = dispatch_reset_once(|| Ok(String::new()), "safe.rsc").unwrap();
        assert!(msg.contains("не перевірено"));
        assert!(!msg.contains("MCM: COMPLETE"));
    }

    // Stage 4: ці перевірки не створюють SSH-з'єднань та не виконують RESET.
    #[test]
    fn stage4_ssh_and_scp_authentication_modes_are_isolated() {
        let conn = UploadConnection {
            host: "192.0.2.25".into(),
            user: "router_admin".into(),
            port: 2022,
            key: "/tmp/mcm-stage4-key".into(),
        };
        for is_key in [true, false] {
            let mut ssh = Command::new("ssh");
            let mut scp = Command::new("scp");
            common_ssh_options(
                &mut ssh,
                &conn,
                if is_key {
                    AuthMode::Key
                } else {
                    AuthMode::Password
                },
            );
            common_ssh_options(
                &mut scp,
                &conn,
                if is_key {
                    AuthMode::Key
                } else {
                    AuthMode::Password
                },
            );
            let ssh_args: Vec<_> = ssh
                .get_args()
                .map(|arg| arg.to_string_lossy().into_owned())
                .collect();
            let scp_args: Vec<_> = scp
                .get_args()
                .map(|arg| arg.to_string_lossy().into_owned())
                .collect();
            assert_eq!(ssh_args, scp_args);
            let has = |value: &str| {
                ssh_args
                    .windows(2)
                    .any(|pair| pair[0] == "-o" && pair[1] == value)
            };
            assert!(has("StrictHostKeyChecking=yes"));
            if is_key {
                assert!(has("BatchMode=yes"));
                assert!(has("PasswordAuthentication=no"));
                assert!(has("KbdInteractiveAuthentication=no"));
                assert!(ssh_args
                    .windows(2)
                    .any(|pair| pair[0] == "-i" && pair[1] == conn.key));
            } else {
                assert!(has("BatchMode=no"));
                assert!(has("PubkeyAuthentication=no"));
                assert!(has("NumberOfPasswordPrompts=1"));
                assert!(!ssh_args.iter().any(|arg| arg == "-i"));
            }
        }
    }

    #[test]
    fn stage4_scp_target_and_multiplexing_do_not_fall_back_to_new_login() {
        let conn = UploadConnection {
            host: "198.51.100.3".into(),
            user: "router_admin".into(),
            port: 2022,
            key: "/tmp/stage4-key".into(),
        };
        let session = UploadSession {
            conn: &conn,
            dir: PathBuf::from("/tmp/mcm-stage4-no-network"),
            socket: PathBuf::from("/tmp/mcm-stage4-no-network/s"),
        };
        let command = session.scp_command(Path::new("/tmp/stage4.rsc"), "stage4.rsc");
        let args: Vec<_> = command
            .get_args()
            .map(|arg| arg.to_string_lossy().into_owned())
            .collect();
        assert!(args.iter().any(|arg| arg == "-O"));
        assert!(args.windows(2).any(|pair| pair == ["-P", "2022"]));
        assert!(args
            .iter()
            .any(|arg| arg == "router_admin@198.51.100.3:stage4.rsc"));
        for flag in [
            "BatchMode=yes",
            "NumberOfPasswordPrompts=0",
            "PubkeyAuthentication=no",
            "PasswordAuthentication=no",
            "KbdInteractiveAuthentication=no",
            "ControlPath=/tmp/mcm-stage4-no-network/s",
        ] {
            assert!(
                args.windows(2)
                    .any(|pair| pair[0] == "-o" && pair[1] == flag),
                "{flag}"
            );
        }
        // Не запускати Drop, який закриває ControlMaster через зовнішній ssh.
        std::mem::forget(session);
    }

    #[test]
    fn stage4_upload_errors_preserve_typed_io_source() {
        use std::error::Error;
        let error = UploadError::Session(UploadSessionError::ScpLaunch(std::io::Error::from(
            std::io::ErrorKind::NotFound,
        )));
        let session = error
            .source()
            .and_then(|source| source.downcast_ref::<UploadSessionError>());
        assert!(matches!(session, Some(UploadSessionError::ScpLaunch(_))));
        let root_cause = session
            .and_then(Error::source)
            .and_then(|source| source.downcast_ref::<std::io::Error>());
        assert_eq!(
            root_cause.map(std::io::Error::kind),
            Some(std::io::ErrorKind::NotFound)
        );

        let connection = UploadError::Connection(Box::new(UploadConnectionError::Port));
        assert!(matches!(
            connection
                .source()
                .and_then(|source| source.downcast_ref::<UploadConnectionError>()),
            Some(UploadConnectionError::Port)
        ));
        assert!(connection.to_string().contains("SSH-порт"));
    }

    #[test]
    fn stage4_reset_keeps_remote_file_gate_and_single_unknown_attempt() {
        assert!(matches!(
            check_remote_rsc_presence("demo.rsc", "0\n"),
            Err(ResetError::RemoteFileMissing(_))
        ));
        assert!(matches!(
            check_remote_rsc_presence("demo.rsc", "not-an-integer"),
            Err(ResetError::RemoteFileCheckInvalid(_))
        ));
        let mut attempts = 0;
        let error = dispatch_reset_once(
            || {
                attempts += 1;
                Err(UploadSessionError::MasterLost)
            },
            "demo.rsc",
        )
        .unwrap_err();
        assert_eq!(attempts, 1);
        assert!(matches!(error, ResetError::Unknown { .. }));
    }

    #[cfg(unix)]
    #[test]
    fn temporary_control_directory_is_created_private() {
        use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
        let path = std::env::temp_dir().join(format!("mcm-dir-permissions-{}", std::process::id()));
        let mut builder = std::fs::DirBuilder::new();
        builder.mode(0o700);
        builder.create(&path).unwrap();
        assert_eq!(
            std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o700
        );
        std::fs::remove_dir(path).unwrap();
    }

    #[test]
    fn mux_client_cannot_prompt_for_password_on_master_failure() {
        let conn = UploadConnection {
            host: "192.0.2.1".into(),
            user: "admin".into(),
            port: 22,
            key: "/tmp/key".into(),
        };
        let session = UploadSession {
            conn: &conn,
            dir: PathBuf::from("/tmp/mcm-test-unused"),
            socket: PathBuf::from("/tmp/mcm-test-unused/s"),
        };
        let mut cmd = Command::new("ssh");
        session.common_client(&mut cmd);
        let args: Vec<_> = cmd
            .get_args()
            .map(|a| a.to_string_lossy().into_owned())
            .collect();
        for option in [
            "BatchMode=yes",
            "NumberOfPasswordPrompts=0",
            "PasswordAuthentication=no",
            "KbdInteractiveAuthentication=no",
            "PubkeyAuthentication=no",
        ] {
            assert!(args
                .windows(2)
                .any(|pair| pair[0] == "-o" && pair[1] == option));
        }
    }

    #[test]
    fn unsafe_filename_rejected() {
        assert!(checked_rsc_name(Path::new("missing;reboot.rsc")).is_err());
    }
    #[test]
    fn rejects_auto_import_but_accepts_large_and_empty_rsc() {
        assert!(checked_rsc_name(Path::new("setup.auto.rsc")).is_err());
        let path = std::env::temp_dir().join(format!("mcm-unlimited-{}.rsc", std::process::id()));
        let file = std::fs::File::create_new(&path).unwrap();
        // Порожній файл не блокується перевіркою розміру.
        assert!(checked_rsc_name(&path).is_ok());
        // Понад колишній ліміт 10 MiB.
        file.set_len(10 * 1024 * 1024 + 1).unwrap();
        assert!(checked_rsc_name(&path).is_ok());
        std::fs::remove_file(path).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn rejects_symlinked_rsc() {
        use std::os::unix::fs::symlink;
        let dir = std::env::temp_dir().join(format!("mcm-symlink-{}", std::process::id()));
        std::fs::create_dir(&dir).unwrap();
        let target = dir.join("target.rsc");
        let link = dir.join("setup.rsc");
        std::fs::write(&target, "# test\n").unwrap();
        symlink(&target, &link).unwrap();
        assert!(checked_rsc_name(&link).is_err());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn no_reset_without_confirmation() {
        assert!(upload_and_reset(Path::new("."), "test", Path::new("setup.rsc"), false).is_err());
    }
}

// Перевірки не запускають SSH, не читають секрети та не змінюють RouterOS.
#[cfg(test)]
mod regression_coherent_readonly_tests {
    use super::*;
    use std::error::Error;
    #[test]
    fn unsupported_command_is_rejected_before_io() {
        let error = run_read_only(Path::new("/missing"), "hap-ac", "/system reboot").unwrap_err();
        assert!(matches!(error, ReadOnlyError::UnsupportedCommand));
        assert_eq!(error.to_string(), "Unsupported remote command");
    }
    #[test]
    fn spawn_failure_has_original_io_source() {
        let error = ReadOnlyError::Launch {
            source: std::io::Error::from(std::io::ErrorKind::NotFound),
        };
        assert!(error.source().is_some());
        assert!(error.to_string().starts_with("Failed to launch ssh:"));
    }
}

// Негативні регресії: типи помилок upload не залежать від тексту CLI.
#[cfg(test)]
mod typed_upload_boundary_tests {
    use super::*;
    use std::error::Error;

    #[test]
    fn failed_rsc_metadata_preserves_io_source() {
        let path =
            std::env::temp_dir().join(format!("mcm-missing-rsc-{}-typed.rsc", std::process::id()));
        let error = checked_rsc_name(&path).expect_err("Неіснуючий RSC повинен відхилятися");
        assert!(matches!(error, UploadScriptError::Metadata(_)));
        assert!(error.source().is_some());
        assert!(error.to_string().starts_with("Локальний .rsc недоступний:"));
    }

    #[test]
    fn connection_codes_keep_previous_cli_wording() {
        let cases = [
            (UploadConnectionError::Host, "SSH host має бути IP-адресою"),
            (
                UploadConnectionError::User,
                "Некоректне ім'я SSH-користувача",
            ),
            (
                UploadConnectionError::Port,
                "SSH-порт не може бути нульовим",
            ),
        ];
        for (error, expected) in cases {
            assert_eq!(error.to_string(), expected);
        }
    }

    #[test]
    fn unsafe_and_destructive_scripts_have_different_codes() {
        assert!(matches!(
            UploadScriptError::UnsafeName,
            UploadScriptError::UnsafeName
        ));
        assert_ne!(
            UploadScriptError::UnsafeName.to_string(),
            UploadScriptError::DestructiveCommand.to_string()
        );
    }
}

#[cfg(test)]
mod coherent_ssh_auth_error_tests {
    use super::SshAuthError;
    use std::error::Error;

    #[test]
    fn spawn_preserves_io_source_and_previous_text() {
        let error = SshAuthError::Spawn(std::io::Error::from(std::io::ErrorKind::NotFound));
        assert!(error.to_string().starts_with("Не вдалося запустити SSH: "));
        assert_eq!(
            error
                .source()
                .and_then(|e| e.downcast_ref::<std::io::Error>())
                .map(std::io::Error::kind),
            Some(std::io::ErrorKind::NotFound)
        );
    }

    #[test]
    fn authentication_and_status_keep_distinct_variants() {
        assert_eq!(
            SshAuthError::AuthenticationRejected.to_string(),
            "RouterOS не підтвердив парольну SSH-автентифікацію"
        );
        assert_eq!(
            SshAuthError::ProcessFailed {
                code: Some(255),
                details: String::new()
            }
            .to_string(),
            "SSH завершився з кодом Some(255)"
        );
        assert_eq!(
            SshAuthError::KeyRejected("permission denied".into()).to_string(),
            "SSH ключ: permission denied"
        );
    }
}

#[cfg(test)]
mod regression_session_typed_error_tests {
    use super::UploadSessionError;
    use std::error::Error;

    #[test]
    fn io_causes_are_exposed_without_text_parsing() {
        let error = UploadSessionError::DirectoryCreate(std::io::Error::from(
            std::io::ErrorKind::PermissionDenied,
        ));
        assert!(error.source().is_some());
        assert!(error
            .to_string()
            .starts_with("Не вдалося створити каталог SSH:"));
        let error =
            UploadSessionError::ScpLaunch(std::io::Error::from(std::io::ErrorKind::NotFound));
        assert!(error.source().is_some());
        assert!(error.to_string().starts_with("Помилка запуску SCP:"));
    }

    #[test]
    fn session_failure_variants_preserve_old_cli_wording() {
        assert_eq!(
            UploadSessionError::PasswordRejected.to_string(),
            "Парольну SSH-автентифікацію відхилено"
        );
        assert_eq!(
            UploadSessionError::MasterLost.to_string(),
            "Головне SSH-з'єднання втрачено; повторний вхід заборонено"
        );
        assert_eq!(
            UploadSessionError::SshExit(Some(255)).to_string(),
            "SSH завершився з кодом Some(255)"
        );
    }
}

#[cfg(test)]
mod regression_verify_error_tests {
    use super::*;
    use std::error::Error;
    #[test]
    fn failed_identity_keeps_io_source() {
        let error = VerifyConnectionError::Identity(SshAuthError::Spawn(std::io::Error::from(
            std::io::ErrorKind::NotFound,
        )));
        assert!(error.source().and_then(Error::source).is_some());
    }
    #[test]
    fn empty_diagnostics_has_distinct_reason() {
        let error = VerifyConnectionError::EmptyDiagnostics;
        assert_eq!(error.to_string(), "RouterOS повернув порожню діагностику");
        assert!(error.source().is_none());
    }
}

// Регресії Stage 26: RESET ніколи не відправляється вдруге після невідомого стану.
#[cfg(test)]
mod regression_reset_boundary_tests {
    use super::*;
    use std::error::Error;
    #[test]
    fn reset_unknown_preserves_io_source_and_one_attempt() {
        let attempts = std::cell::Cell::new(0);
        let error = dispatch_reset_once(
            || {
                attempts.set(attempts.get() + 1);
                Err(UploadSessionError::SshLaunch(std::io::Error::from(
                    std::io::ErrorKind::ConnectionReset,
                )))
            },
            "safe.rsc",
        )
        .expect_err("Стан RESET невідомий");
        assert_eq!(attempts.get(), 1);
        assert!(matches!(error, ResetError::Unknown { .. }));
        assert!(error.to_string().contains("Не повторюйте upload --reset"));
        assert!(error.source().and_then(Error::source).is_some());
    }
    #[test]
    fn unconfirmed_reset_is_denied_before_file_or_network_io() {
        let error = upload_and_reset(
            Path::new("/unavailable"),
            "test",
            Path::new("/unavailable/script.rsc"),
            false,
        )
        .expect_err("Без дозволу");
        assert!(matches!(error, ResetError::NotConfirmed));
        assert!(error.source().is_none());
    }
    #[test]
    fn missing_runtime_file_preserves_io_source() {
        let error = upload_and_reset(
            Path::new("."),
            "test",
            Path::new("/mcm-does-not-exist-stage26.rsc"),
            true,
        )
        .expect_err("Відсутній файл");
        assert!(matches!(error, ResetError::Read(_)));
        assert!(error.source().is_some());
    }
    #[test]
    fn expand_home_without_prefix_needs_no_environment() {
        assert_eq!(expand_home("/tmp/id_key").unwrap(), "/tmp/id_key");
    }
}

// Регресії Stage 5: першопричини та захист RESET без мережевих операцій.
#[cfg(test)]
mod stage5_reset_failure_contract_tests {
    use super::*;
    use std::error::Error;

    #[test]
    fn boxed_errors_expose_concrete_types_through_source() {
        let verify = VerifyConnectionError::Connection(Box::new(UploadConnectionError::Port));
        assert!(verify
            .source()
            .and_then(|e| e.downcast_ref::<UploadConnectionError>())
            .is_some());

        let reset_connection = ResetError::Connection(Box::new(UploadConnectionError::Port));
        assert!(reset_connection
            .source()
            .and_then(|e| e.downcast_ref::<UploadConnectionError>())
            .is_some());

        let reset_session = ResetError::Session(Box::new(UploadSessionError::MasterLost));
        assert!(matches!(
            reset_session
                .source()
                .and_then(|e| e.downcast_ref::<UploadSessionError>()),
            Some(UploadSessionError::MasterLost)
        ));

        let reset_upload =
            ResetError::Upload(Box::new(UploadError::Session(UploadSessionError::ScpLost)));
        let inner = reset_upload
            .source()
            .and_then(|e| e.downcast_ref::<UploadError>())
            .expect("UploadError має бути доступним");
        assert!(matches!(
            inner
                .source()
                .and_then(|e| e.downcast_ref::<UploadSessionError>()),
            Some(UploadSessionError::ScpLost)
        ));
    }

    #[test]
    fn scp_failure_keeps_io_cause_and_blocks_reset_before_dispatch() {
        let error = ResetError::Upload(Box::new(UploadError::Session(
            UploadSessionError::ScpLaunch(std::io::Error::from(
                std::io::ErrorKind::PermissionDenied,
            )),
        )));
        let upload = error
            .source()
            .and_then(|e| e.downcast_ref::<UploadError>())
            .unwrap();
        let session = upload
            .source()
            .and_then(|e| e.downcast_ref::<UploadSessionError>())
            .unwrap();
        let io = session
            .source()
            .and_then(|e| e.downcast_ref::<std::io::Error>())
            .unwrap();
        assert_eq!(io.kind(), std::io::ErrorKind::PermissionDenied);
        // Невдалий SCP ідентифікується типом Upload, а не UNKNOWN після RESET.
        assert!(matches!(error, ResetError::Upload(_)));
    }

    #[test]
    fn remote_presence_gate_rejects_invalid_counts_and_accepts_nonzero_counts() {
        for output in ["", "invalid", "-1", "1.5", "18446744073709551616"] {
            assert!(matches!(
                check_remote_rsc_presence("safe.rsc", output),
                Err(ResetError::RemoteFileCheckInvalid(_))
            ));
        }
        assert!(matches!(
            check_remote_rsc_presence("safe.rsc", " 0\n"),
            Err(ResetError::RemoteFileMissing(_))
        ));
        for output in ["1", "2\n", " 10 "] {
            assert!(check_remote_rsc_presence("safe.rsc", output).is_ok());
        }
    }

    #[test]
    fn unknown_reset_preserves_ssh_io_cause_without_retry() {
        let mut calls = 0;
        let error = dispatch_reset_once(
            || {
                calls += 1;
                Err(UploadSessionError::SshLaunch(std::io::Error::from(
                    std::io::ErrorKind::ConnectionReset,
                )))
            },
            "safe.rsc",
        )
        .unwrap_err();
        assert_eq!(calls, 1);
        assert!(error.to_string().contains("Не повторюйте upload --reset"));
        let session = error
            .source()
            .and_then(|e| e.downcast_ref::<UploadSessionError>())
            .unwrap();
        assert!(matches!(session, UploadSessionError::SshLaunch(_)));
        assert_eq!(
            session
                .source()
                .and_then(|e| e.downcast_ref::<std::io::Error>())
                .map(std::io::Error::kind),
            Some(std::io::ErrorKind::ConnectionReset)
        );
    }

    #[test]
    fn unconfirmed_reset_returns_before_local_io_or_remote_connection() {
        let error = upload_and_reset(
            Path::new("/unavailable"),
            "unknown",
            Path::new("/unavailable/no-file.rsc"),
            false,
        )
        .unwrap_err();
        assert!(matches!(error, ResetError::NotConfirmed));
        assert!(error.source().is_none());
    }
}
