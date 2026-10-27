// Спільний контекст, який підготовлюється один раз до диспетчеризації.
use crate::i18n::Messages;
use crate::logging::Logger;
use std::path::Path;

pub struct Context<'a> {
    pub root: &'a Path,
    pub router: &'a str,
    pub tokens: &'a [String],
    pub msg: &'a Messages,
    pub log: &'a Logger,
}

impl Context<'_> {
    // Додаткові параметри команд після назви команди та профілю.
    pub fn options(&self) -> Vec<&str> {
        self.tokens.iter().skip(2).map(String::as_str).collect()
    }
}
