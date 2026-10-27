// Лише читання ідентичності RouterOS через SSH.
use crate::cli::context::Context;
pub(crate) fn execute(ctx: &Context<'_>) -> Result<(), super::error::CommandError> {
    let result = crate::routeros::run_read_only(ctx.root, ctx.router, "/system identity print")
        .map_err(|error| super::error::CommandError::ReadOnly(Box::new(error)))?;
    ctx.log.ok(ctx.msg.get("connected"));
    println!("{result}");
    Ok(())
}
