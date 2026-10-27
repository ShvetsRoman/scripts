// Застосування без окремого явного reset заборонене.
use crate::cli::context::Context;
pub(crate) fn execute(ctx: &Context<'_>) -> Result<(), super::error::CommandError> {
    Err(super::error::CommandError::Blocked {
        detail: ctx.msg.get("blocked").to_string(),
    })
}
