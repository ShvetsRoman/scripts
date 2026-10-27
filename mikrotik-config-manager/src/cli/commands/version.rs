// Версія з Cargo.toml.
use crate::cli::context::Context;
pub(crate) fn execute(_: &Context<'_>) -> Result<(), super::error::CommandError> {
    println!("{}", env!("CARGO_PKG_VERSION"));
    Ok(())
}
