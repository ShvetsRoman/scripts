// Типізовані коди міжмодульних перевірок. Текст не використовується для визначення коду.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CrossCode {
    Static01,
    Static02,
    Static03,
    Static04,
    Static05,
    Static06,
    Static07,
    Static08,
    Static09,
    Static10,
    Static11,
    Static12,
    Static13,
    Static14,
    Static15,
    Static16,
    Static17,
    Static18,
    Static19,
    Consistency01,
    Consistency02,
    Consistency03,
    Consistency04,
    Consistency05,
    Consistency06,
    Finalization01,
    Finalization02,
    Finalization03,
    Finalization04,
    Finalization05,
    Finalization06,
    Finalization07,
    Finalization08,
}

// Метадані локалізації та координат потрібні лише регресійним тестам.
// Робочий CLI зберігає оригінальний текст міжмодульної помилки.
#[cfg(test)]
impl CrossCode {
    pub fn locale_key(self) -> &'static str {
        match self {
            Self::Static01 => "cross_static01",
            Self::Static02 => "cross_static02",
            Self::Static03 => "cross_static03",
            Self::Static04 => "cross_static04",
            Self::Static05 => "cross_static05",
            Self::Static06 => "cross_static06",
            Self::Static07 => "cross_static07",
            Self::Static08 => "cross_static08",
            Self::Static09 => "cross_static09",
            Self::Static10 => "cross_static10",
            Self::Static11 => "cross_static11",
            Self::Static12 => "cross_static12",
            Self::Static13 => "cross_static13",
            Self::Static14 => "cross_static14",
            Self::Static15 => "cross_static15",
            Self::Static16 => "cross_static16",
            Self::Static17 => "cross_static17",
            Self::Static18 => "cross_static18",
            Self::Static19 => "cross_static19",
            Self::Consistency01 => "cross_consistency01",
            Self::Consistency02 => "cross_consistency02",
            Self::Consistency03 => "cross_consistency03",
            Self::Consistency04 => "cross_consistency04",
            Self::Consistency05 => "cross_consistency05",
            Self::Consistency06 => "cross_consistency06",
            Self::Finalization01 => "cross_finalization01",
            Self::Finalization02 => "cross_finalization02",
            Self::Finalization03 => "cross_finalization03",
            Self::Finalization04 => "cross_finalization04",
            Self::Finalization05 => "cross_finalization05",
            Self::Finalization06 => "cross_finalization06",
            Self::Finalization07 => "cross_finalization07",
            Self::Finalization08 => "cross_finalization08",
        }
    }
    pub fn location(self) -> (&'static str, &'static str) {
        match self {
            Self::Static01 => ("network.toml", "cross-module"),
            Self::Static02 => ("network.toml", "cross-module"),
            Self::Static03 => ("network.toml", "cross-module"),
            Self::Static04 => ("network.toml", "cross-module"),
            Self::Static05 => ("network.toml", "cross-module"),
            Self::Static06 => ("network.toml", "cross-module"),
            Self::Static07 => ("network.toml", "cross-module"),
            Self::Static08 => ("network.toml", "cross-module"),
            Self::Static09 => ("network.toml", "cross-module"),
            Self::Static10 => ("network.toml", "cross-module"),
            Self::Static11 => ("network.toml", "cross-module"),
            Self::Static12 => ("network.toml", "cross-module"),
            Self::Static13 => ("network.toml", "cross-module"),
            Self::Static14 => ("network.toml", "cross-module"),
            Self::Static15 => ("network.toml", "cross-module"),
            Self::Static16 => ("network.toml", "cross-module"),
            Self::Static17 => ("network.toml", "cross-module"),
            Self::Static18 => ("network.toml", "cross-module"),
            Self::Static19 => ("network.toml", "cross-module"),
            Self::Consistency01 => ("network.toml", "cross-module"),
            Self::Consistency02 => ("network.toml", "cross-module"),
            Self::Consistency03 => ("network.toml", "cross-module"),
            Self::Consistency04 => ("network.toml", "cross-module"),
            Self::Consistency05 => ("network.toml", "cross-module"),
            Self::Consistency06 => ("network.toml", "cross-module"),
            Self::Finalization01 => ("firewall.toml", "cross-module"),
            Self::Finalization02 => ("firewall.toml", "cross-module"),
            Self::Finalization03 => ("firewall.toml", "cross-module"),
            Self::Finalization04 => ("firewall.toml", "cross-module"),
            Self::Finalization05 => ("firewall.toml", "cross-module"),
            Self::Finalization06 => ("firewall.toml", "cross-module"),
            Self::Finalization07 => ("firewall.toml", "cross-module"),
            Self::Finalization08 => ("firewall.toml", "cross-module"),
        }
    }
}

// Фактична причина перевірки: зберігаємо IPv4 або std::net parse error.
#[derive(Debug, Clone, PartialEq, Eq)]
enum CrossCause {
    Ipv4(super::shared_errors::Ipv4Error),
    Address(std::net::AddrParseError),
}

impl std::fmt::Display for CrossCause {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Ipv4(error) => std::fmt::Display::fmt(error, f),
            Self::Address(error) => std::fmt::Display::fmt(error, f),
        }
    }
}
impl std::error::Error for CrossCause {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Ipv4(error) => Some(error),
            Self::Address(error) => Some(error),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CrossError {
    pub code: CrossCode,
    pub detail: String,
    cause: Option<CrossCause>,
}

impl CrossError {
    pub fn new(code: CrossCode, detail: String) -> Self {
        Self {
            code,
            detail,
            cause: None,
        }
    }
}

impl CrossError {
    // Старе CLI-повідомлення залишається, справжній AddrParseError доступний через source().
    pub fn from_address_parse(
        code: CrossCode,
        detail: &'static str,
        error: std::net::AddrParseError,
    ) -> Self {
        Self {
            code,
            detail: detail.into(),
            cause: Some(CrossCause::Address(error)),
        }
    }
    pub fn from_ipv4(code: CrossCode, error: super::shared_errors::Ipv4Error) -> Self {
        Self {
            code,
            detail: error.to_string(),
            cause: Some(CrossCause::Ipv4(error)),
        }
    }
}
impl std::fmt::Display for CrossError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.detail)
    }
}
impl std::error::Error for CrossError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.cause.as_ref().map(|cause| match cause {
            CrossCause::Ipv4(error) => error as &(dyn std::error::Error + 'static),
            CrossCause::Address(error) => error as &(dyn std::error::Error + 'static),
        })
    }
}

#[cfg(test)]
mod regression_tests {
    use super::*;
    use crate::i18n::Messages;
    use crate::modules::reference_error::PlanError;
    #[test]
    fn codes_survive_result_without_parsing_text() {
        for code in [
            CrossCode::Static01,
            CrossCode::Static02,
            CrossCode::Static03,
            CrossCode::Static04,
            CrossCode::Static05,
            CrossCode::Static06,
            CrossCode::Static07,
            CrossCode::Static08,
            CrossCode::Static09,
            CrossCode::Static10,
            CrossCode::Static11,
            CrossCode::Static12,
            CrossCode::Static13,
            CrossCode::Static14,
            CrossCode::Static15,
            CrossCode::Static16,
            CrossCode::Static17,
            CrossCode::Static18,
            CrossCode::Static19,
            CrossCode::Consistency01,
            CrossCode::Consistency02,
            CrossCode::Consistency03,
            CrossCode::Consistency04,
            CrossCode::Consistency05,
            CrossCode::Consistency06,
            CrossCode::Finalization01,
            CrossCode::Finalization02,
            CrossCode::Finalization03,
            CrossCode::Finalization04,
            CrossCode::Finalization05,
            CrossCode::Finalization06,
            CrossCode::Finalization07,
            CrossCode::Finalization08,
        ] {
            let error: PlanError = CrossError::new(code, "TEST_SENTINEL".into()).into();
            assert!(
                matches!(error, PlanError::Cross(CrossError { code: found, .. }) if found == code)
            );
            assert!(!code.location().0.is_empty());
        }
    }
    #[test]
    fn every_cross_code_has_both_locales() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        for lang in ["uk", "en"] {
            let messages = Messages::load(root, lang).unwrap();
            for code in [
                CrossCode::Static01,
                CrossCode::Static02,
                CrossCode::Static03,
                CrossCode::Static04,
                CrossCode::Static05,
                CrossCode::Static06,
                CrossCode::Static07,
                CrossCode::Static08,
                CrossCode::Static09,
                CrossCode::Static10,
                CrossCode::Static11,
                CrossCode::Static12,
                CrossCode::Static13,
                CrossCode::Static14,
                CrossCode::Static15,
                CrossCode::Static16,
                CrossCode::Static17,
                CrossCode::Static18,
                CrossCode::Static19,
                CrossCode::Consistency01,
                CrossCode::Consistency02,
                CrossCode::Consistency03,
                CrossCode::Consistency04,
                CrossCode::Consistency05,
                CrossCode::Consistency06,
                CrossCode::Finalization01,
                CrossCode::Finalization02,
                CrossCode::Finalization03,
                CrossCode::Finalization04,
                CrossCode::Finalization05,
                CrossCode::Finalization06,
                CrossCode::Finalization07,
                CrossCode::Finalization08,
            ] {
                assert_ne!(messages.get(code.locale_key()), code.locale_key());
            }
        }
    }
}

#[cfg(test)]
mod regression_final_source_audit_tests {
    use super::*;
    use std::error::Error;

    #[test]
    fn address_parse_preserves_code_display_and_actual_source() {
        let original = "invalid-ip".parse::<std::net::Ipv4Addr>().unwrap_err();
        let error = CrossError::from_address_parse(
            CrossCode::Static04,
            "Static Audit: некоректна адреса lease",
            original,
        );
        assert_eq!(error.code, CrossCode::Static04);
        assert_eq!(error.to_string(), "Static Audit: некоректна адреса lease");
        let cause = error.source().expect("typed cause");
        assert!(cause.downcast_ref::<std::net::AddrParseError>().is_some());
    }
}
