// Типізовані помилки CLI-команд: доменна причина не губиться під час dispatch.
#[derive(Debug)]
pub(crate) enum CommandError {
    UnknownCommand {
        detail: String,
    },
    Blocked {
        detail: String,
    },
    MissingUploadFile {
        path: std::path::PathBuf,
    },
    Profile(crate::config::ProfileError),
    ReadOnly(Box<crate::routeros::ReadOnlyError>),
    Upload(crate::routeros::UploadError),
    // Текст локалізації готується один раз, а першопричина лишається типізованою.
    Plan {
        rendered: String,
        source: Box<crate::modules::reference_error::PlanError>,
    },
    Setup {
        rendered: String,
        source: Box<crate::setup::SetupError>,
    },
    ScriptOptions(crate::cli::args::ArgsError),
    ScriptPath(crate::cli::args::ArgsError),
    Reset(Box<crate::routeros::ResetError>),
    Verify(crate::routeros::VerifyConnectionError),
}
impl std::fmt::Display for CommandError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnknownCommand { detail } | Self::Blocked { detail } => f.write_str(detail),
            Self::Reset(error) => write!(f, "{error}"),
            Self::Verify(error) => write!(f, "{error}"),
            Self::ScriptOptions(error) | Self::ScriptPath(error) => write!(f, "{error}"),
            Self::MissingUploadFile { path } => write!(
                f,
                "Файл для upload відсутній: {}. Спочатку виконай build",
                path.display()
            ),
            Self::Profile(e) => write!(f, "{e}"),
            Self::ReadOnly(e) => write!(f, "{e}"),
            Self::Upload(e) => write!(f, "{e}"),
            Self::Plan { rendered, .. } | Self::Setup { rendered, .. } => f.write_str(rendered),
        }
    }
}
impl std::error::Error for CommandError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Profile(e) => Some(e),
            Self::ReadOnly(e) => Some(e),
            Self::Upload(e) => Some(e),
            Self::Plan { source, .. } => Some(source),
            Self::Setup { source, .. } => Some(source),
            Self::ScriptOptions(error) | Self::ScriptPath(error) => Some(error),
            Self::Verify(error) => Some(error),
            Self::Reset(error) => Some(error),
            _ => None,
        }
    }
}

#[cfg(test)]
mod typed_registry_regressions {
    use super::*;
    use std::error::Error;

    #[test]
    fn typed_upload_error_preserves_nested_io_cause() {
        let error = CommandError::Upload(crate::routeros::UploadError::Script(
            crate::routeros::UploadScriptError::Metadata(std::io::Error::from(
                std::io::ErrorKind::NotFound,
            )),
        ));
        assert!(error.source().is_some());
        assert!(error.source().unwrap().source().is_some());
        assert!(error.to_string().contains("Локальний .rsc"));
    }

    #[test]
    fn boxed_read_only_error_preserves_io_source_and_small_command_error() {
        let inner = crate::routeros::ReadOnlyError::Launch {
            source: std::io::Error::from(std::io::ErrorKind::NotFound),
        };
        let error = CommandError::ReadOnly(Box::new(inner));
        assert!(error.source().is_some());
        assert!(error.source().unwrap().source().is_some());
        assert!(std::mem::size_of::<CommandError>() < 128);
    }

    #[test]
    fn unknown_and_blocked_are_different_cli_errors() {
        let missing = CommandError::UnknownCommand {
            detail: "невідома команда: invalid".into(),
        };
        let blocked = CommandError::Blocked {
            detail: "заборонено".into(),
        };
        assert!(matches!(missing, CommandError::UnknownCommand { .. }));
        assert!(matches!(blocked, CommandError::Blocked { .. }));
        assert!(missing.source().is_none());
        assert_eq!(blocked.to_string(), "заборонено");
    }
}
