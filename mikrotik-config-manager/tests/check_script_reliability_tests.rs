//! Перевірки п'яти етапів check.sh без запуску справжніх Cargo та RouterOS.
use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[cfg(unix)]
fn run_mocked_check(failed_command: Option<&str>) -> (std::process::Output, String, String) {
    use std::os::unix::fs::PermissionsExt;
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let folder =
        std::env::temp_dir().join(format!("mcm-check-stage2-{}-{unique}", std::process::id()));
    fs::create_dir_all(folder.join("bin")).unwrap();
    let cargo = folder.join("bin/cargo");
    // Зберігаємо аргументи для перевірки, що форматування не змінює файлів.
    fs::write(&cargo, r#"#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MCM_MOCK_CALLS"
case "$1" in
fmt) if [[ "$MCM_MOCK_FAIL" == fmt ]]; then exit 19; fi; exit 0 ;;
clippy) if [[ "$MCM_MOCK_FAIL" == clippy ]]; then exit 23; fi ;;
test)
    printf 'test result: ok. 7 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out; finished in 0.01s\n'
    printf 'test result: ok. 2 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s\n'
    if [[ "$MCM_MOCK_FAIL" == test ]]; then exit 17; fi ;;
esac
exit 0
"#).unwrap();
    let python = folder.join("bin/python3");
    fs::write(&python, "#!/usr/bin/env bash\nif [[ \"$MCM_MOCK_FAIL\" == documentation ]]; then exit 31; fi\nexit 0\n").unwrap();
    for file in [&cargo, &python] {
        let mut perms = fs::metadata(file).unwrap().permissions();
        perms.set_mode(0o755);
        fs::set_permissions(file, perms).unwrap();
    }
    let report = folder.join("check.txt");
    let calls = folder.join("calls.txt");
    let mut paths = vec![folder.join("bin")];
    paths.extend(std::env::split_paths(
        &std::env::var_os("PATH").unwrap_or_default(),
    ));
    let output = Command::new("bash")
        .arg(root.join("scripts/check.sh"))
        .env("PATH", std::env::join_paths(paths).unwrap())
        .env("REPORT_FILE", &report)
        .env("MCM_MOCK_CALLS", &calls)
        .env("MCM_MOCK_FAIL", failed_command.unwrap_or(""))
        .env("NO_COLOR", "1")
        .output()
        .unwrap();
    let report_text = fs::read_to_string(report).unwrap();
    let calls_text = fs::read_to_string(calls).unwrap();
    fs::remove_dir_all(folder).unwrap();
    (output, report_text, calls_text)
}

#[cfg(unix)]
#[test]
fn five_stages_are_read_only_and_counts_match_successful_mock_run() {
    let (result, report, calls) = run_mocked_check(None);
    assert!(result.status.success(), "{}", report);
    let lines: Vec<_> = calls.lines().collect();
    assert_eq!(
        lines,
        [
            "fmt --all -- --check",
            "fmt --all -- --check",
            "clippy --all-targets -- -D warnings",
            "test"
        ]
    );
    assert!(report.contains("Етапи: PASS 5 | FAIL 0 | SKIP 0"));
    assert!(report.contains("Rust-тести: PASS 9 | FAIL 0 | IGNORED 1"));
    assert!(report.contains("Фінальний статус: PASS (код 0)"));
}

#[cfg(unix)]
#[test]
fn failed_clippy_does_not_hide_exit_status_or_skip_other_stages() {
    let (result, report, _) = run_mocked_check(Some("clippy"));
    assert_eq!(result.status.code(), Some(1));
    assert!(report.contains("[FAIL] Cargo clippy (код 23)"));
    assert!(report.contains("Етапи: PASS 4 | FAIL 1 | SKIP 0"));
    assert!(report.contains("Rust-тести: PASS 9 | FAIL 0 | IGNORED 1"));
    assert!(report.contains("Фінальний статус: FAIL (код 1)"));
}

#[cfg(unix)]
#[test]
fn cargo_test_failure_preserves_summary_and_runs_documentation() {
    let (result, report, _) = run_mocked_check(Some("test"));
    assert_eq!(result.status.code(), Some(1));
    assert!(report.contains("[FAIL] Cargo test (код 17)"));
    assert!(report.contains("[PASS] TOML documentation"));
    assert!(report.contains("Етапи: PASS 4 | FAIL 1 | SKIP 0"));
    assert!(report.contains("Rust-тести: PASS 9 | FAIL 0 | IGNORED 1"));
}

#[cfg(unix)]
#[test]
fn documentation_failure_sets_nonzero_exit_status() {
    let (result, report, _) = run_mocked_check(Some("documentation"));
    assert_eq!(result.status.code(), Some(1));
    assert!(report.contains("[FAIL] TOML documentation (код 31)"));
    assert!(report.contains("Етапи: PASS 4 | FAIL 1 | SKIP 0"));
}

// Невдалий Rustfmt не повинен повторно друкувати однаковий diff.
#[cfg(unix)]
#[test]
fn failed_fmt_skips_duplicate_check_and_keeps_five_stages() {
    let (result, report, calls) = run_mocked_check(Some("fmt"));
    assert_eq!(result.status.code(), Some(1));
    assert!(report.contains("[FAIL] Cargo fmt (код 19)"));
    assert!(report.contains("[SKIP] Cargo fmt check"));
    assert!(report.contains("Етапи: PASS 3 | FAIL 1 | SKIP 1"));
    assert!(report.contains("Rust-тести: PASS 9 | FAIL 0 | IGNORED 1"));
    assert_eq!(
        calls
            .lines()
            .filter(|line| line.starts_with("fmt "))
            .count(),
        1
    );
}
