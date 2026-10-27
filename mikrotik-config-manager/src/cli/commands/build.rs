// Генерація захищеного .rsc із конфігурації та .secrets.
use crate::cli::args::{profile_script_path, script_options};
use crate::cli::context::Context;
// Єдиний спосіб відображення помилок експорту для будь-якого роутера.
// Тип зберігається до рівня CLI; повідомлення не розпізнаємо за підрядками,
// а конфігурацію профілю не читаємо повторно для визначення коду.
#[cfg(test)]
fn describe_export_error(
    messages: &crate::i18n::Messages,
    router: &str,
    error: crate::setup::SetupError,
) -> String {
    describe_export_error_ref(messages, router, &error)
}

fn describe_export_error_ref(
    messages: &crate::i18n::Messages,
    router: &str,
    error: &crate::setup::SetupError,
) -> String {
    match error {
        crate::setup::SetupError::Plan(plan_error) => {
            crate::cli::reference_diagnostics::describe_plan_error_ref(messages, router, plan_error)
        }
        crate::setup::SetupError::Issue(error) => error.to_string(),
        crate::setup::SetupError::Profile(error) => error.to_string(),
        crate::setup::SetupError::TypedConfig(error) => error.to_string(),
    }
}

pub(crate) fn execute(ctx: &Context<'_>) -> Result<(), super::error::CommandError> {
    let options = ctx.options();
    let (name, reset) =
        script_options(&options, false).map_err(super::error::CommandError::ScriptOptions)?;
    debug_assert!(!reset);
    let output = profile_script_path(ctx.root, ctx.router, &name, true)
        .map_err(super::error::CommandError::ScriptPath)?;
    let secrets = crate::config::router_dir(ctx.root, ctx.router)
        .map_err(super::error::CommandError::Profile)?
        .join(".secrets");
    crate::setup::export_secure(ctx.root, ctx.router, &output, &secrets).map_err(|error| {
        let rendered = describe_export_error_ref(ctx.msg, ctx.router, &error);
        super::error::CommandError::Setup {
            rendered,
            source: Box::new(error),
        }
    })?;
    ctx.log.ok(&format!(
        "Сценарій із секретами профілю створено: {}",
        output.display()
    ));
    Ok(())
}

#[cfg(test)]
mod regression_export_diagnostics_tests {
    use super::*;
    use crate::modules::reference_error::{
        ConfigurationCode, ConfigurationError, PlanError, ReferenceCode, SecurityCode,
        SecurityError, ValidationCode, ValidationError,
    };
    use std::path::Path;

    // Різні домашні роутери використовують однакову типізовану діагностику.
    #[test]
    fn export_renders_same_reference_code_for_independent_routers() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        for language in ["uk", "en"] {
            let messages = crate::i18n::Messages::load(root, language).unwrap();
            for router in ["hap-ac", "test"] {
                let actual = describe_export_error(
                    &messages,
                    router,
                    crate::setup::SetupError::from(PlanError::Reference(
                        ReferenceCode::WifiSecurity,
                    )),
                );
                assert!(actual.contains(router));
                assert!(actual.contains("wireless.toml"));
                assert!(actual.contains("wireless.wlan*.security"));
            }
        }
    }

    // Усі три домени проходять через enum, а не через текстове визначення помилки.
    #[test]
    fn export_localizes_typed_domains_without_exposing_secret_values() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        for language in ["uk", "en"] {
            let messages = crate::i18n::Messages::load(root, language).unwrap();
            let cases = [
                (
                    PlanError::Validation(ValidationError {
                        code: ValidationCode::UnknownBridgePort,
                        detail: "bridge.ports.invalid".into(),
                    }),
                    ValidationCode::UnknownBridgePort.locale_key(),
                ),
                (
                    PlanError::Configuration(ConfigurationError {
                        code: ConfigurationCode::ConnectionPortZero,
                        detail: "connection.port".into(),
                    }),
                    ConfigurationCode::ConnectionPortZero.locale_key(),
                ),
                (
                    PlanError::Security(SecurityError {
                        code: SecurityCode::WeakSshCrypto,
                        detail: "PRIVATE_TEST_SECRET".into(),
                        cause: None,
                    }),
                    SecurityCode::WeakSshCrypto.locale_key(),
                ),
            ];
            for (error, key) in cases {
                let rendered =
                    describe_export_error(&messages, "test", crate::setup::SetupError::from(error));
                assert!(rendered.contains(messages.get(key)));
                assert!(!rendered.contains("PRIVATE_TEST_SECRET"));
            }
        }
    }

    // Інші помилки експорту (наприклад, відсутній .secrets) не перетворюємо
    // на вигадані коди та не прив'язуємо до іншого профілю.
    #[test]
    fn export_preserves_unclassified_errors() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let messages = crate::i18n::Messages::load(root, "uk").unwrap();
        let actual = describe_export_error(
            &messages,
            "test",
            crate::setup::SetupError::Issue(crate::setup::SetupIssue::test_issue(
                crate::setup::SetupCode::SecretsMetadata,
                "Відсутній файл секретів",
            )),
        );
        assert_eq!(actual, "Відсутній файл секретів");
    }
}

// Stage 6: регресійний аудит однакового формату plan/build для домашніх роутерів.
// Тести не виконують RouterOS-команди та не змінюють файли профілів.
#[cfg(test)]
mod regression_regression_audit_tests {
    use super::*;
    use crate::cli::reference_diagnostics::describe_plan_error;
    use crate::modules::reference_error::{
        ConfigurationCode, ConfigurationError, PlanError, ReferenceCode, SecurityCode,
        SecurityError, ValidationCode, ValidationError,
    };
    use std::path::Path;

    // Порівнюємо два шляхи форматування, не покладаючись на текст деталей.
    fn cases() -> Vec<PlanError> {
        let mut errors = vec![
            PlanError::Validation(ValidationError {
                code: ValidationCode::DuplicateOrEmptyName,
                detail: "duplicate".into(),
            }),
            PlanError::Validation(ValidationError {
                code: ValidationCode::UnknownBridgePort,
                detail: "port".into(),
            }),
        ];
        for code in [
            ConfigurationCode::ConnectionPortZero,
            ConfigurationCode::WireguardPortZero,
            ConfigurationCode::InvalidPhysicalInterface,
            ConfigurationCode::InvalidBridgePort,
        ] {
            errors.push(PlanError::Configuration(ConfigurationError {
                code,
                detail: "configuration detail".into(),
            }));
        }
        for code in [
            SecurityCode::MissingAdmin,
            SecurityCode::InvalidAdminGroup,
            SecurityCode::InvalidUserGroup,
            SecurityCode::WeakSshCrypto,
            SecurityCode::InvalidMacAccess,
            SecurityCode::InvalidUpdateChannel,
            SecurityCode::AutoInstall,
            SecurityCode::AutoReboot,
            SecurityCode::RouterboardUpgrade,
        ] {
            errors.push(PlanError::Security(SecurityError {
                code,
                detail: "STAGE6_PRIVATE_SECRET".into(),
                cause: None,
            }));
        }
        for code in [
            ReferenceCode::WifiInterface,
            ReferenceCode::WifiBridge,
            ReferenceCode::WifiSecurity,
            ReferenceCode::BridgePort,
            ReferenceCode::NetworkLan,
        ] {
            errors.push(PlanError::Reference(code));
        }
        errors
    }

    #[test]
    fn all_typed_codes_render_identically_in_plan_and_build() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        for language in ["uk", "en"] {
            let messages = crate::i18n::Messages::load(root, language).unwrap();
            for router in ["hap-ac", "test"] {
                for (plan_error, export_error) in cases().into_iter().zip(cases()) {
                    let expected = describe_plan_error(&messages, router, plan_error);
                    let actual = describe_export_error(
                        &messages,
                        router,
                        crate::setup::SetupError::from(export_error),
                    );
                    assert_eq!(actual, expected, "{language}: {router}");
                    assert!(actual.contains(&format!("'{router}'")));
                    assert!(!actual.contains("STAGE6_PRIVATE_SECRET"));
                }
            }
        }
    }
}
