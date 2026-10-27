//! Регресійна перевірка українських описів усіх конфігураційних TOML.
use std::fs;
use std::path::Path;

#[test]
fn all_toml_files_have_ukrainian_comments_and_examples() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut names = vec![root.join("Cargo.toml"), root.join("config/manager.toml")];
    for entry in fs::read_dir(root.join("routers")).expect("список профілів") {
        let entry = entry.expect("каталог профілю");
        if !entry.file_type().unwrap().is_dir() {
            continue;
        }
        let dir = entry.path();
        for entry in fs::read_dir(&dir).expect("каталог профілю") {
            let path = entry.expect("запис каталогу").path();
            if path
                .extension()
                .is_some_and(|extension| extension == "toml")
            {
                names.push(path);
            }
        }
    }
    assert!(names.len() > 2, "немає конфігурацій профілів");
    for path in names {
        let text = fs::read_to_string(&path).expect("читання TOML");
        assert!(
            text.contains("# ПРИКЛАД"),
            "немає прикладу: {}",
            path.display()
        );
        assert!(
            text.lines()
                .filter(|line| line.trim_start().starts_with('#'))
                .count()
                >= 5,
            "немає опису: {}",
            path.display()
        );
    }
}
