// Єдиний реєстр CLI-команд: ім'я, аліаси й типобезпечний обробник.
use super::commands;
use super::context::Context;

pub(crate) type Handler = fn(&Context<'_>) -> Result<(), commands::error::CommandError>;

pub(crate) struct Command {
    pub name: &'static str,
    pub aliases: &'static [&'static str],
    pub handler: Handler,
}

pub(crate) static COMMANDS: &[Command] = &[
    Command {
        name: "help",
        aliases: &["--help", "-h"],
        handler: commands::help::execute,
    },
    Command {
        name: "version",
        aliases: &["--version", "-V"],
        handler: commands::version::execute,
    },
    Command {
        name: "list",
        aliases: &[],
        handler: commands::list::execute,
    },
    Command {
        name: "connect",
        aliases: &[],
        handler: commands::connect::execute,
    },
    Command {
        name: "status",
        aliases: &[],
        handler: commands::status::execute,
    },
    Command {
        name: "verify",
        aliases: &[],
        handler: commands::verify::execute,
    },
    Command {
        name: "plan",
        aliases: &[],
        handler: commands::plan::execute,
    },
    Command {
        name: "build",
        aliases: &[],
        handler: commands::build::execute,
    },
    Command {
        name: "upload",
        aliases: &[],
        handler: commands::upload::execute,
    },
    Command {
        name: "apply",
        aliases: &[],
        handler: commands::apply::execute,
    },
];

pub(crate) fn find(name: &str) -> Option<&'static Command> {
    COMMANDS
        .iter()
        .find(|cmd| cmd.name == name || cmd.aliases.contains(&name))
}

// Одна точка виконання всіх команд; невідомі команди обробляються однаково.
pub(crate) fn dispatch(
    name: &str,
    context: &Context<'_>,
) -> Result<(), commands::error::CommandError> {
    let command = find(name).ok_or_else(|| commands::error::CommandError::UnknownCommand {
        detail: format!("{}: {name}", context.msg.get("unknown")),
    })?;
    (command.handler)(context)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn registers_all_original_commands_and_aliases() {
        for name in [
            "help",
            "--help",
            "-h",
            "version",
            "--version",
            "-V",
            "list",
            "connect",
            "status",
            "verify",
            "plan",
            "build",
            "upload",
            "apply",
        ] {
            assert!(find(name).is_some(), "Немає команди {name}");
        }
        assert!(find("nonsense").is_none());
    }
    #[test]
    fn commands_have_unique_names_and_aliases() {
        let mut names = std::collections::HashSet::new();
        for command in COMMANDS {
            assert!(names.insert(command.name));
            for alias in command.aliases {
                assert!(names.insert(*alias));
            }
        }
    }
}
