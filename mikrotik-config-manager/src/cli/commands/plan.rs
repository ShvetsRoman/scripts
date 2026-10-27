// Генерація локального плану без виконання команд.
use crate::cli::context::Context;
pub(crate) fn execute(ctx: &Context<'_>) -> Result<(), super::error::CommandError> {
    ctx.log.info(ctx.msg.get("plan"));
    let rendered =
        crate::modules::plan(ctx.root, ctx.router, ctx.tokens.get(2).map(String::as_str)).map_err(
            |error| {
                let rendered = crate::cli::reference_diagnostics::describe_plan_error_ref(
                    ctx.msg, ctx.router, &error,
                );
                super::error::CommandError::Plan {
                    rendered,
                    source: Box::new(error),
                }
            },
        )?;
    println!("{rendered}");
    Ok(())
}
