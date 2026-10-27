// Точка входу CLI: викликає єдиний модульний диспетчер.
use std::path::Path;

pub(crate) fn run(args: &[String], root: &Path) -> Result<(), crate::cli::CliError> {
    crate::cli::run(args, root)
}
