// Список повних, синтаксично коректних профілів із routers/.
use crate::cli::context::Context;

pub(crate) fn execute(ctx: &Context<'_>) -> Result<(), super::error::CommandError> {
    for router in
        crate::config::discover_profiles(ctx.root).map_err(super::error::CommandError::Profile)?
    {
        println!("{router}");
    }
    Ok(())
}
