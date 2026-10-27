// Типізовані помилки спільного розв’язання інтерфейсів без аналізу тексту.
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SharedCode {
    UnknownInterface,
    DisabledInterface,
    InvalidWanReference,
    WanIdMismatch,
    InvalidToken,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SharedError {
    pub code: SharedCode,
    pub detail: String,
    cause: Option<TokenError>,
}

impl SharedError {
    pub fn new(code: SharedCode, detail: impl Into<String>) -> Self {
        Self {
            code,
            detail: detail.into(),
            cause: None,
        }
    }
}

impl SharedError {
    pub fn from_token(code: SharedCode, error: TokenError) -> Self {
        Self {
            code,
            detail: error.to_string(),
            cause: Some(error),
        }
    }
}
impl fmt::Display for SharedError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.detail)
    }
}

impl std::error::Error for SharedError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.cause
            .as_ref()
            .map(|error| error as &(dyn std::error::Error + 'static))
    }
}

// Тип помилки токена формується безпосередньо валідатором, без аналізу тексту.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TokenCode {
    InvalidCharactersOrEmpty,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TokenError {
    pub code: TokenCode,
    pub label: String,
}

impl fmt::Display for TokenError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "Некоректне значення {}", self.label)
    }
}
impl std::error::Error for TokenError {}

// Окремі причини помилок IPv4/prefix без рядкового розпізнавання.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Ipv4Code {
    MissingPrefix,
    InvalidAddress,
    InvalidPrefix,
    PrefixOutOfRange,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Ipv4Error {
    pub code: Ipv4Code,
}

impl fmt::Display for Ipv4Error {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self.code {
            Ipv4Code::MissingPrefix => "Очікується IPv4/prefix",
            Ipv4Code::InvalidAddress => "Некоректний IPv4",
            Ipv4Code::InvalidPrefix => "Некоректний IPv4 prefix",
            Ipv4Code::PrefixOutOfRange => "IPv4 prefix більше 32",
        })
    }
}
impl std::error::Error for Ipv4Error {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shared_codes_remain_structured_and_do_not_change_messages() {
        let error = SharedError::new(SharedCode::DisabledInterface, "Інтерфейс ether2 вимкнений");
        // Перевіряємо передавання помилки через реальну межу Result.
        fn propagate(error: SharedError) -> Result<(), SharedError> {
            Err(error)
        }
        let extracted = propagate(error).expect_err("Очікували типізовану помилку");
        assert_eq!(extracted.code, SharedCode::DisabledInterface);
        assert_eq!(extracted.to_string(), "Інтерфейс ether2 вимкнений");
    }
}

#[cfg(test)]
mod regression_boundary_tests {
    use super::*;
    #[test]
    fn token_codes_and_messages_remain_structured() {
        let invalid = ["", "bad value", "a;run", "ж"];
        for value in invalid {
            let error = super::super::token(value, "interface.name").expect_err("має відмовити");
            assert_eq!(error.code, TokenCode::InvalidCharactersOrEmpty);
            assert_eq!(error.to_string(), "Некоректне значення interface.name");
        }
        for value in ["ether1", "LAN-Bridge", "sfp_sfpplus1", "1.2"] {
            assert!(super::super::token(value, "interface.name").is_ok());
        }
    }
    #[test]
    fn ipv4_codes_and_existing_messages() {
        use super::super::network::parse_address;
        for (input, code, message) in [
            (
                "192.168.88.1",
                Ipv4Code::MissingPrefix,
                "Очікується IPv4/prefix",
            ),
            ("bad/24", Ipv4Code::InvalidAddress, "Некоректний IPv4"),
            (
                "192.168.88.1/word",
                Ipv4Code::InvalidPrefix,
                "Некоректний IPv4 prefix",
            ),
            (
                "192.168.88.1/33",
                Ipv4Code::PrefixOutOfRange,
                "IPv4 prefix більше 32",
            ),
        ] {
            let error = parse_address(input).expect_err("має відмовити");
            assert_eq!(error.code, code);
            assert_eq!(error.to_string(), message);
        }
        assert_eq!(parse_address("192.168.88.1/24").expect("валідно").1, 24);
    }
}
