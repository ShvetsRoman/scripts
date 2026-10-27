// SCP-завантаження на RouterOS; reset дозволений лише явно.
use crate::cli::args::{profile_script_path, script_options};
use crate::cli::context::Context;
pub(crate) fn execute(ctx: &Context<'_>) -> Result<(), super::error::CommandError> {
    let options = ctx.options();
    let (name, reset) =
        script_options(&options, true).map_err(super::error::CommandError::ScriptOptions)?;
    let path = profile_script_path(ctx.root, ctx.router, &name, false)
        .map_err(super::error::CommandError::ScriptPath)?;
    if !path.is_file() {
        return Err(super::error::CommandError::MissingUploadFile { path });
    }
    if reset {
        let result = crate::routeros::upload_and_reset(ctx.root, ctx.router, &path, true)
            .map_err(|error| super::error::CommandError::Reset(Box::new(error)))?;
        ctx.log.info(&result);
    } else {
        let name = crate::routeros::upload(ctx.root, ctx.router, &path)
            .map_err(super::error::CommandError::Upload)?;
        ctx.log.ok(&format!(
            "Сценарій {name} передано через SCP; наявність у Files без --reset не перевірялася"
        ));
    }
    Ok(())
}
