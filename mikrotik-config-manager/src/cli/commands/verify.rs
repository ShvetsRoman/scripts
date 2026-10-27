// Безпечна read-only перевірка SSH і RouterOS.
use crate::cli::context::Context;
pub(crate) fn execute(ctx: &Context<'_>) -> Result<(), super::error::CommandError> {
    println!(
        "{}",
        crate::routeros::verify_connection(ctx.root, ctx.router)
            .map_err(super::error::CommandError::Verify)?
    );
    Ok(())
}
