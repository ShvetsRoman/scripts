// Єдиний CLI-диспетчер: аргументи -> контекст -> реєстр -> обробник.
pub mod args;
pub mod commands;
pub mod context;
pub mod reference_diagnostics;
pub mod registry;

use crate::i18n::Messages;
use crate::logging::Logger;
use context::Context;
use std::path::Path;

// Структурована межа CLI: локалізаційна першопричина доступна через source().
#[derive(Debug)]
pub(crate) enum CliError {
    Arguments(args::ArgsError),
    Locale(crate::i18n::LocaleError),
    Command(commands::error::CommandError),
}
impl std::fmt::Display for CliError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Arguments(error) => write!(f, "{error}"),
            Self::Command(error) => write!(f, "{error}"),
            Self::Locale(error) => write!(f, "{error}"),
        }
    }
}
impl std::error::Error for CliError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Arguments(error) => Some(error),
            Self::Locale(error) => Some(error),
            Self::Command(error) => Some(error),
        }
    }
}

pub(crate) fn run(args: &[String], root: &Path) -> Result<(), CliError> {
    let parsed = self::args::parse(args, root).map_err(CliError::Arguments)?;
    let msg = Messages::load(root, &parsed.language).map_err(CliError::Locale)?;
    let log = Logger::new(&parsed.color);
    let command = parsed.tokens.first().map(String::as_str).unwrap_or("help");
    let router = parsed
        .tokens
        .get(1)
        .map(String::as_str)
        .unwrap_or(&parsed.default_router);
    let context = Context {
        root,
        router,
        tokens: &parsed.tokens,
        msg: &msg,
        log: &log,
    };
    // Кожен модуль повертає типізовану помилку, якщо має її визначений код.
    // CLI не відкриває TOML повторно та не класифікує повідомлення за текстом.
    registry::dispatch(command, &context).map_err(CliError::Command)
}

// Регресія: код CLI не втрачає оригінальну помилку локалізації.
#[cfg(test)]
mod regression_coherent_cli_tests {
    use super::*;
    use std::error::Error;
    #[test]
    fn locale_error_keeps_original_source_and_text() {
        let error = CliError::Locale(crate::i18n::LocaleError::Read {
            path: std::path::PathBuf::from("/tmp/locales/uk.lang"),
            source: std::io::Error::from(std::io::ErrorKind::NotFound),
        });
        assert!(error.source().is_some());
        assert!(error.to_string().contains("uk.lang"));
    }
    #[test]
    fn command_error_keeps_message_without_guessing_code() {
        let error = CliError::Command(commands::error::CommandError::Blocked {
            detail: "команду відхилено".into(),
        });
        assert_eq!(error.to_string(), "команду відхилено");
    }
}
