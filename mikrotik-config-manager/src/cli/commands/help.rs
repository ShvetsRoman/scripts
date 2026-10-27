// Довідка користувача з локалізації.
use crate::cli::context::Context;
pub(crate) fn execute(ctx: &Context<'_>) -> Result<(), super::error::CommandError> {
    println!("{} v{}", ctx.msg.get("app"), env!("CARGO_PKG_VERSION"));
    println!("{}", ctx.msg.get("help"));
    Ok(())
}
