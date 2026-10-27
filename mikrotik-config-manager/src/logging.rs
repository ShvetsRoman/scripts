use std::io::IsTerminal;

// ANSI тільки в інтерактивному терміналі; у файлах і pipe — чистий текст.
pub struct Logger {
    color: bool,
}
impl Logger {
    pub fn new(mode: &str) -> Self {
        let color = match mode {
            "always" => true,
            "never" => false,
            _ => std::io::stdout().is_terminal() && std::env::var_os("NO_COLOR").is_none(),
        };
        Self { color }
    }
    pub fn info(&self, s: &str) {
        self.emit("INFO", "36", s);
    }
    pub fn ok(&self, s: &str) {
        self.emit("OK", "32", s);
    }
    pub fn error(&self, s: &str) {
        // Помилки спрямовуємо в stderr, інші повідомлення — у stdout.
        // ANSI використовуємо лише тоді, коли stderr є терміналом.
        let color = self.color && std::io::stderr().is_terminal();
        if color {
            eprintln!("\x1b[31m[ERROR]\x1b[0m {s}");
        } else {
            eprintln!("[ERROR] {s}");
        }
    }
    fn emit(&self, label: &str, ansi: &str, s: &str) {
        if self.color {
            println!("\x1b[{ansi}m[{label}]\x1b[0m {s}");
        } else {
            println!("[{label}] {s}");
        }
    }
}
