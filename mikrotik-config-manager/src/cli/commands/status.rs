// Ідентичність та системні ресурси RouterOS без змін.
use crate::cli::context::Context;
pub(crate) fn execute(ctx: &Context<'_>) -> Result<(), super::error::CommandError> {
    let id = crate::routeros::run_read_only(ctx.root, ctx.router, "/system identity print")
        .map_err(|error| super::error::CommandError::ReadOnly(Box::new(error)))?;
    let resource = crate::routeros::run_read_only(ctx.root, ctx.router, "/system resource print")
        .map_err(|error| super::error::CommandError::ReadOnly(Box::new(error)))?;
    ctx.log
        .info(&format!("{}: {}", ctx.msg.get("router"), ctx.router));
    println!("{id}\n{resource}");
    Ok(())
}
