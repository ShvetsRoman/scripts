// Локалізуємо структуровані коди; не читаємо TOML і не аналізуємо текст помилок.
use crate::i18n::Messages;
use crate::modules::reference_error::ReferenceCode;

pub fn describe(msg: &Messages, profile: &str, code: ReferenceCode) -> String {
    let (file, field) = code.location();
    format!(
        "{} '{profile}', {} '{file}', {} '{field}': {}",
        msg.get("ref_diag_profile"),
        msg.get("ref_diag_file"),
        msg.get("ref_diag_field"),
        msg.get(code.locale_key())
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    #[test]
    fn output_does_not_expose_secret_values() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let msg = Messages::load(root, "uk").unwrap();
        let output = describe(&msg, "home", ReferenceCode::WifiSecurity);
        assert!(!output.contains("ADMIN_PASSWORD"));
        assert!(!output.contains("WIFI_PASSWORD"));
    }
    #[test]
    fn locales_render_structured_errors_without_secrets() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        for (lang, prefix) in [("uk", "Профіль"), ("en", "Profile")] {
            let messages = Messages::load(root, lang).unwrap();
            for code in [
                ReferenceCode::WifiInterface,
                ReferenceCode::WifiBridge,
                ReferenceCode::WifiSecurity,
                ReferenceCode::BridgePort,
                ReferenceCode::NetworkLan,
            ] {
                let actual = describe(&messages, "custom-profile", code);
                assert!(actual.starts_with(prefix));
                assert!(actual.contains("custom-profile"));
                assert!(actual.contains(code.location().0));
                assert!(actual.contains(code.location().1));
                assert!(!actual.contains("WIFI_PASSWORD"));
            }
        }
    }
}

// Один формат для всіх типізованих доменів. Профіль передається з CLI,
// а файл і поле беруться з enum, без читання іншого профілю або TOML.
fn describe_domain(
    msg: &Messages,
    profile: &str,
    code_key: &str,
    location: Option<(&str, &str)>,
    detail: Option<&str>,
) -> String {
    let mut result = format!("{} '{profile}'", msg.get("ref_diag_profile"));
    if let Some((file, field)) = location {
        result.push_str(&format!(
            ", {} '{file}', {} '{field}'",
            msg.get("ref_diag_file"),
            msg.get("ref_diag_field"),
        ));
    }
    result.push_str(&format!(": {}", msg.get(code_key)));
    if let Some(detail) = detail {
        // Залишаємо попередню деталізацію лише для validation/configuration.
        // Security.detail не виводимо, щоб не розкривати облікові дані.
        result.push_str(&format!(": {detail}"));
    }
    result
}

// Тип домену визначаємо виключно через PlanError, не за рядком повідомлення.
#[cfg(test)]
pub fn describe_plan_error(
    msg: &Messages,
    profile: &str,
    error: crate::modules::reference_error::PlanError,
) -> String {
    describe_plan_error_ref(msg, profile, &error)
}

// Незнищувальна діагностика для типізованих Result: source() доступний далі.
pub fn describe_plan_error_ref(
    msg: &Messages,
    profile: &str,
    error: &crate::modules::reference_error::PlanError,
) -> String {
    use crate::modules::reference_error::PlanError;
    match error {
        PlanError::Reference(code) => describe(msg, profile, *code),
        PlanError::Validation(error) => describe_domain(
            msg,
            profile,
            error.code.locale_key(),
            error.code.location(),
            Some(&error.detail),
        ),
        PlanError::Configuration(error) => describe_domain(
            msg,
            profile,
            error.code.locale_key(),
            Some(error.code.location()),
            Some(&error.detail),
        ),
        PlanError::Security(error) => describe_domain(
            msg,
            profile,
            error.code.locale_key(),
            Some(error.code.location()),
            None,
        ),
        PlanError::Module(error) => describe_domain(
            msg,
            profile,
            error.code.locale_key(),
            Some(error.code.location()),
            Some(&error.detail),
        ),
        // Перевірки між модулями зберігають історичний текст CLI та тип у Result.
        PlanError::Cross(error) => error.detail.clone(),
        PlanError::Shared(error) => error.detail.clone(),
        PlanError::PlanValidation(error) => error.detail.clone(),
        PlanError::TypedConfig(error) => error.to_string(),
        PlanError::Profile(error) => error.to_string(),
        PlanError::Boundary(error) => error.to_string(),
    }
}

#[cfg(test)]
mod regression_localized_tests {
    use super::*;
    use crate::modules::reference_error::{PlanError, SecurityCode, SecurityError};
    #[test]
    fn same_typed_security_code_localizes_without_values() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        for (lang, expected) in [("uk", "SSH"), ("en", "SSH")] {
            let messages = Messages::load(root, lang).unwrap();
            let result = describe_plan_error(
                &messages,
                "test",
                PlanError::Security(SecurityError {
                    code: SecurityCode::WeakSshCrypto,
                    detail: "SUPER_SECRET_PASSWORD".into(),
                    cause: None,
                }),
            );
            assert!(result.contains(expected));
            assert!(!result.contains("SUPER_SECRET_PASSWORD"));
        }
    }
}

#[cfg(test)]
mod regression_router_context_tests {
    use super::*;
    use crate::modules::reference_error::{
        ConfigurationCode, ConfigurationError, PlanError, SecurityCode, SecurityError,
        ValidationCode, ValidationError,
    };

    // Перевіряємо обидва незалежні профілі та обидві мови повідомлень.
    #[test]
    fn typed_domains_show_selected_router_and_known_field() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        for lang in ["uk", "en"] {
            let msg = Messages::load(root, lang).unwrap();
            for router in ["hap-ac", "test"] {
                let cases = [
                    (
                        PlanError::Validation(ValidationError {
                            code: ValidationCode::UnknownBridgePort,
                            detail: "invalid port".into(),
                        }),
                        "bridge.toml",
                        "ports.*",
                    ),
                    (
                        PlanError::Configuration(ConfigurationError {
                            code: ConfigurationCode::WireguardPortZero,
                            detail: "zero".into(),
                        }),
                        "wireguard.toml",
                        "wireguard.listen_port",
                    ),
                    (
                        PlanError::Security(SecurityError {
                            code: SecurityCode::AutoInstall,
                            detail: "SECRET_SAMPLE".into(),
                            cause: None,
                        }),
                        "system.toml",
                        "updates.auto_install",
                    ),
                ];
                for (error, file, field) in cases {
                    let output = describe_plan_error(&msg, router, error);
                    assert!(output.contains(&format!("'{router}'")));
                    assert!(output.contains(file));
                    assert!(output.contains(field));
                    assert!(!output.contains("SECRET_SAMPLE"));
                }
            }
        }
    }

    // Для спільної перевірки назв не вигадуємо конкретний TOML-файл.
    #[test]
    fn ambiguous_validation_location_is_not_invented() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        let msg = Messages::load(root, "uk").unwrap();
        let output = describe_plan_error(
            &msg,
            "test",
            PlanError::Validation(ValidationError {
                code: ValidationCode::DuplicateOrEmptyName,
                detail: "resource names".into(),
            }),
        );
        assert!(output.contains("'test'"));
        assert!(!output.contains(".toml"));
    }

    // Невідомі (ще не типізовані) помилки не отримують вигаданого коду.
    #[test]
    fn other_error_keeps_previous_output_contract() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        let msg = Messages::load(root, "en").unwrap();
        assert_eq!(
            describe_plan_error(
                &msg,
                "test",
                crate::modules::reference_error::PlanBoundaryError::new(
                    crate::modules::reference_error::PlanBoundaryCode::BridgeId,
                    "original"
                )
                .into()
            ),
            "original"
        );
    }
}

// Stage 6: тестуємо локалізацію усіх кодів, а не лише вибіркових прикладів.
#[cfg(test)]
mod regression_locale_isolation_tests {
    use super::*;
    use crate::modules::reference_error::{
        ConfigurationCode, ConfigurationError, PlanError, SecurityCode, SecurityError,
        ValidationCode, ValidationError,
    };
    use std::path::Path;

    #[test]
    fn all_domain_codes_have_uk_and_en_translations() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        let keys = [
            ValidationCode::DuplicateOrEmptyName.locale_key(),
            ValidationCode::UnknownBridgePort.locale_key(),
            ConfigurationCode::ConnectionPortZero.locale_key(),
            ConfigurationCode::WireguardPortZero.locale_key(),
            ConfigurationCode::InvalidPhysicalInterface.locale_key(),
            ConfigurationCode::InvalidBridgePort.locale_key(),
            ConfigurationCode::DisabledLanBridge.locale_key(),
            ConfigurationCode::WanInBridge.locale_key(),
            SecurityCode::MissingAdmin.locale_key(),
            SecurityCode::InvalidAdminGroup.locale_key(),
            SecurityCode::InvalidUserGroup.locale_key(),
            SecurityCode::WeakSshCrypto.locale_key(),
            SecurityCode::InvalidMacAccess.locale_key(),
            SecurityCode::InvalidUpdateChannel.locale_key(),
            SecurityCode::AutoInstall.locale_key(),
            SecurityCode::AutoReboot.locale_key(),
            SecurityCode::RouterboardUpgrade.locale_key(),
        ];
        for lang in ["uk", "en"] {
            let msg = Messages::load(root, lang).unwrap();
            for key in keys {
                // Невідомий ключ повертається як є, тому це пряма перевірка покриття.
                assert_ne!(msg.get(key), key, "missing {lang} translation for {key}");
            }
        }
    }

    #[test]
    fn router_context_is_from_selected_profile_only() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR"));
        for lang in ["uk", "en"] {
            let msg = Messages::load(root, lang).unwrap();
            for (router, other) in [("hap-ac", "test"), ("test", "hap-ac")] {
                let cases = [
                    PlanError::Validation(ValidationError {
                        code: ValidationCode::UnknownBridgePort,
                        detail: "invalid-port".into(),
                    }),
                    PlanError::Configuration(ConfigurationError {
                        code: ConfigurationCode::WireguardPortZero,
                        detail: "zero-port".into(),
                    }),
                    PlanError::Security(SecurityError {
                        code: SecurityCode::InvalidMacAccess,
                        detail: "PRIVATE_VALUE".into(),
                        cause: None,
                    }),
                ];
                for error in cases {
                    let output = describe_plan_error(&msg, router, error);
                    assert!(output.contains(&format!("'{router}'")));
                    assert!(!output.contains(&format!("'{other}'")));
                    assert!(!output.contains("PRIVATE_VALUE"));
                }
            }
        }
    }
}

// Stage 7: обидва профілі та обидві локалі використовують однаковий enum.
#[cfg(test)]
mod regression_localized_coverage_tests {
    use super::*;
    use crate::modules::reference_error::{ConfigurationCode, ConfigurationError, PlanError};

    #[test]
    fn lan_bridge_and_wan_bridge_diagnostics_are_scoped_and_localized() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        for (lang, prefix) in [("uk", "Профіль"), ("en", "Profile")] {
            let msg = Messages::load(root, lang).unwrap();
            for (profile, other) in [("hap-ac", "test"), ("test", "hap-ac")] {
                for (code, file, field) in [
                    (
                        ConfigurationCode::DisabledLanBridge,
                        "bridge.toml",
                        "bridge.lan.enabled",
                    ),
                    (
                        ConfigurationCode::WanInBridge,
                        "network.toml",
                        "wan.interface",
                    ),
                ] {
                    let out = describe_plan_error(
                        &msg,
                        profile,
                        PlanError::Configuration(ConfigurationError {
                            code,
                            detail: "diagnostic-marker".into(),
                        }),
                    );
                    assert!(out.starts_with(prefix));
                    assert!(out.contains(profile));
                    assert!(!out.contains(&format!("'{other}'")));
                    assert!(out.contains(file));
                    assert!(out.contains(field));
                    assert_ne!(msg.get(code.locale_key()), code.locale_key());
                    assert!(!out.contains("SUPER_SECRET_PASSWORD"));
                }
            }
        }
    }
}

// Stage 8: локалізація нових кодів і незалежність домашніх профілів.
#[cfg(test)]
mod regression_network_management_locales_tests {
    use super::*;
    use crate::modules::reference_error::{ConfigurationCode, ConfigurationError, PlanError};

    #[test]
    fn management_codes_are_localized_for_each_router() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        for lang in ["uk", "en"] {
            let msg = Messages::load(root, lang).unwrap();
            for (router, unrelated) in [("hap-ac", "test"), ("test", "hap-ac")] {
                for code in [
                    ConfigurationCode::InvalidManagementReference,
                    ConfigurationCode::WanManagementConflict,
                ] {
                    let output = describe_plan_error(
                        &msg,
                        router,
                        PlanError::Configuration(ConfigurationError {
                            code,
                            detail: "audit-marker".into(),
                        }),
                    );
                    let (file, field) = code.location();
                    assert!(output.contains(&format!("'{router}'")));
                    assert!(!output.contains(&format!("'{unrelated}'")));
                    assert!(output.contains(file));
                    assert!(output.contains(field));
                    assert!(output.contains("audit-marker"));
                    assert_ne!(msg.get(code.locale_key()), code.locale_key());
                    assert!(!output.contains("ADMIN_PASSWORD"));
                }
            }
        }
    }
}

#[cfg(test)]
mod regression_parser_locales_tests {
    use super::*;
    use crate::modules::reference_error::{ModuleCode, ModuleError, PlanError};
    // Різні профілі не змішуються; однаковий код має переклад обома мовами.
    #[test]
    fn typed_parser_error_is_localized_and_scoped() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        for language in ["uk", "en"] {
            let msg = Messages::load(root, language).unwrap();
            for profile in ["hap-ac", "test"] {
                let error = PlanError::Module(ModuleError::new(
                    ModuleCode::DnsDuplicateServers,
                    "Дубль DNS",
                ));
                let rendered = describe_plan_error(&msg, profile, error);
                assert!(rendered.contains(profile));
                assert!(rendered.contains("dns.toml"));
                assert!(rendered.contains("dns.servers"));
                assert!(!rendered.contains("WIFI_PASSWORD"));
            }
        }
    }
}

#[cfg(test)]
mod regression_localized_module_tests {
    use super::*;
    use crate::modules::reference_error::{ModuleCode, ModuleError, PlanError};

    #[test]
    fn network_nat_firewall_errors_are_localized_for_each_router() {
        // Кожен профіль перевіряємо незалежно; текст помилки не визначає її код.
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        for language in ["uk", "en"] {
            let messages = Messages::load(root, language).unwrap();
            for profile in ["hap-ac", "test"] {
                for code in [
                    ModuleCode::NetworkLanPrefix,
                    ModuleCode::NatDuplicateForward,
                    ModuleCode::FirewallManagementOverlap,
                ] {
                    let diagnostic = describe_plan_error(
                        &messages,
                        profile,
                        PlanError::Module(ModuleError::new(code, "Stage11-test-detail")),
                    );
                    assert!(diagnostic.contains(profile));
                    assert!(diagnostic.contains(code.location().0));
                    assert!(diagnostic.contains(code.location().1));
                    assert!(diagnostic.contains("Stage11-test-detail"));
                    assert!(!diagnostic.contains("WIFI_PASSWORD"));
                    assert!(!diagnostic.contains("ADMIN_PASSWORD"));
                }
            }
        }
    }
}

#[cfg(test)]
mod regression_cli_contract_tests {
    use super::*;
    use crate::modules::{PlanValidationCode, PlanValidationError};

    #[test]
    fn plan_validation_stays_typed_without_changing_cli_text() {
        let error = PlanValidationError {
            code: PlanValidationCode::UnsafeCharacter,
            detail: "Plan Validation: небезпечний символ у рядку 1".into(),
        };
        let message =
            Messages::load(std::path::Path::new(env!("CARGO_MANIFEST_DIR")), "uk").unwrap();
        let rendered = describe_plan_error(&message, "test", error.into());
        assert_eq!(rendered, "Plan Validation: небезпечний символ у рядку 1");
    }
}
