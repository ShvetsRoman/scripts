mod app;
mod cli;
mod config;
mod i18n;
mod logging;
mod modules;
mod routeros;
mod setup;

fn main() {
    // --root використовується для тестів і запуску з іншого каталогу.
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let root = if let Some(i) = args.iter().position(|a| a == "--root") {
        if i + 1 >= args.len() {
            logging::Logger::new("auto").error("--root requires path");
            std::process::exit(2);
        }
        let val = args.remove(i + 1);
        args.remove(i);
        std::path::PathBuf::from(val)
    } else {
        config::config_root()
    };
    if let Err(e) = app::run(&args, &root) {
        logging::Logger::new("auto").error(&e.to_string());
        std::process::exit(1);
    }
}
