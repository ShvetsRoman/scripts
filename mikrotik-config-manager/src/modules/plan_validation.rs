// Код причини визначається під час перевірки, а не за текстом повідомлення.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlanValidationCode {
    UnsupportedCommand,
    UnsafeCharacter,
    InvalidArguments,
    InvalidQuotes,
    InvalidDhcpCleanup,
    WrongOrder,
    AcceptAfterDrop,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanValidationError {
    pub code: PlanValidationCode,
    pub detail: String,
}

impl PlanValidationError {
    fn new(code: PlanValidationCode, detail: impl Into<String>) -> Self {
        Self {
            code,
            detail: detail.into(),
        }
    }
}

impl std::fmt::Display for PlanValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.detail)
    }
}
impl std::error::Error for PlanValidationError {}

// Перевіряємо згенерований RouterOS PLAN без підключення до маршрутизатора.
// Це лексична перевірка дозволених команд, а не повний парсер RouterOS.
const ALLOWED: &[&str] = &[
    "/interface ethernet set ",
    "/interface bridge add ",
    "/interface bridge port add ",
    "/interface list add ",
    "/interface list member add ",
    "/interface wireless security-profiles add ",
    "/interface wireless set ",
    "/interface wifi security add ",
    "/interface wifi set ",
    "/interface wireguard add ",
    "/interface wireguard peers add ",
    "/ip address add ",
    "/ip pool add ",
    "/ip dhcp-server add ",
    "/ip dhcp-server network add ",
    "/ip dhcp-server lease add ",
    "/ip dhcp-client add ",
    "/ip dhcp-client remove [find]",
    "/ip dns set ",
    "/ip firewall filter add ",
    "/ipv6 firewall filter add ",
    "/ipv6 settings set ",
    "/ip firewall nat add ",
    "/ip service set ",
    "/ip neighbor discovery-settings set ",
    "/system identity set ",
    "/system clock set ",
    "/system ntp client set ",
    "/system ntp client servers add ",
    "/system package update set ",
    "/ip ssh set ",
    "/tool mac-server set ",
    "/tool mac-server mac-winbox set ",
];

// Причини лексичних помилок RouterOS PLAN передаються типом, а не розпізнаються з тексту.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ArgumentIssueCode {
    Brackets,
    Unclosed,
    Path,
    DhcpRemove,
    Empty,
    FindShape,
    FindAssignment,
    FindSelector,
    DuplicateFind,
    Assignment,
    InvalidKey,
    DuplicateKey,
    PublicKeyQuotes,
    InvalidValue,
    RequiredKey,
    FirewallChain,
    FirewallAction,
    NatRule,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ArgumentIssue {
    code: ArgumentIssueCode,
    detail: String,
}
impl ArgumentIssue {
    fn new(code: ArgumentIssueCode, detail: impl Into<String>) -> Self {
        Self {
            code,
            detail: detail.into(),
        }
    }
}
impl std::fmt::Display for ArgumentIssue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.detail)
    }
}
impl std::error::Error for ArgumentIssue {}

// Розділяємо аргументи RouterOS лише поза [find ...] та лапками ключа.
// Це запобігає пропуску зайвого аргументу через пробіл у значенні.
fn arguments(line: &str) -> Result<Vec<String>, ArgumentIssue> {
    let mut result = Vec::new();
    let mut item = String::new();
    let (mut brackets, mut quoted) = (false, false);
    for ch in line.chars() {
        match ch {
            '[' if !quoted && !brackets => {
                brackets = true;
                item.push(ch);
            }
            ']' if brackets && !quoted => {
                brackets = false;
                item.push(ch);
            }
            '[' | ']' if !quoted => {
                return Err(ArgumentIssue::new(
                    ArgumentIssueCode::Brackets,
                    "Plan Validation: неправильні дужки",
                ))
            }
            '"' => {
                quoted = !quoted;
                item.push(ch);
            }
            ' ' | '\t' if !quoted && !brackets => {
                if !item.is_empty() {
                    result.push(std::mem::take(&mut item));
                }
            }
            _ => item.push(ch),
        }
    }
    if quoted || brackets {
        return Err(ArgumentIssue::new(
            ArgumentIssueCode::Unclosed,
            "Plan Validation: незакриті дужки або лапки",
        ));
    }
    if !item.is_empty() {
        result.push(item);
    }
    Ok(result)
}

// Перевіряємо аргументи згенерованих команд, а не лише командний шлях.
fn validate_arguments(line: &str) -> Result<(), ArgumentIssue> {
    use std::collections::HashSet;
    let prefix = ALLOWED
        .iter()
        .find(|prefix| line.starts_with(**prefix))
        .ok_or_else(|| {
            ArgumentIssue::new(ArgumentIssueCode::Path, "Plan Validation: невідомий шлях")
        })?;
    // Єдиний дозволений remove — повне очищення IPv4 DHCP Client.
    // Довільні селектори, параметри й видалення інших ресурсів заборонені.
    if *prefix == "/ip dhcp-client remove [find]" {
        return if line == "/ip dhcp-client remove [find]" {
            Ok(())
        } else {
            Err(ArgumentIssue::new(
                ArgumentIssueCode::DhcpRemove,
                "Plan Validation: недозволена форма DHCP Client remove",
            ))
        };
    }
    let suffix = &line[prefix.len()..];
    let args = arguments(suffix)?;
    if args.is_empty() {
        return Err(ArgumentIssue::new(
            ArgumentIssueCode::Empty,
            "Plan Validation: команда без параметрів",
        ));
    }
    let mut keys = HashSet::new();
    let mut values = std::collections::HashMap::new();
    for arg in &args {
        if arg.starts_with('[') {
            if !arg.ends_with(']') || !arg.starts_with("[find ") {
                return Err(ArgumentIssue::new(
                    ArgumentIssueCode::FindShape,
                    "Plan Validation: дозволений тільки [find key=value]",
                ));
            }
            let inside = &arg[6..arg.len() - 1];
            let (key, value) = inside.split_once('=').ok_or_else(|| {
                ArgumentIssue::new(
                    ArgumentIssueCode::FindAssignment,
                    "Plan Validation: некоректний find",
                )
            })?;
            if !matches!(key, "name" | "default-name")
                || value.is_empty()
                || !value
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
            {
                return Err(ArgumentIssue::new(
                    ArgumentIssueCode::FindSelector,
                    "Plan Validation: небезпечний find selector",
                ));
            }
            if !keys.insert("[find]") {
                return Err(ArgumentIssue::new(
                    ArgumentIssueCode::DuplicateFind,
                    "Plan Validation: повторений find",
                ));
            }
            continue;
        }
        let (key, value) = arg.split_once('=').ok_or_else(|| {
            ArgumentIssue::new(
                ArgumentIssueCode::Assignment,
                "Plan Validation: аргумент без key=value",
            )
        })?;
        if key.is_empty()
            || !key
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
            || value.is_empty()
            || value.chars().any(char::is_whitespace)
        {
            return Err(ArgumentIssue::new(
                ArgumentIssueCode::InvalidKey,
                format!("Plan Validation: некоректний аргумент {key}"),
            ));
        }
        if !keys.insert(key) {
            return Err(ArgumentIssue::new(
                ArgumentIssueCode::DuplicateKey,
                format!("Plan Validation: повторений аргумент {key}"),
            ));
        }
        if value.contains('"')
            && (key != "public-key"
                || !value.starts_with('"')
                || !value.ends_with('"')
                || value.len() != 46
                || value[1..value.len() - 1].contains('"'))
        {
            return Err(ArgumentIssue::new(
                ArgumentIssueCode::PublicKeyQuotes,
                "Plan Validation: лапки дозволено лише для public-key",
            ));
        }
        if !value.chars().all(|c| {
            c.is_ascii_alphanumeric()
                || matches!(c, '_' | '-' | '.' | '/' | ':' | ',' | '!' | '+' | '=' | '"')
        }) {
            return Err(ArgumentIssue::new(
                ArgumentIssueCode::InvalidValue,
                format!("Plan Validation: недозволене значення {key}"),
            ));
        }
        values.insert(key, value);
    }
    let required: &[&str] = if matches!(
        *prefix,
        "/ip firewall filter add " | "/ipv6 firewall filter add " | "/ip firewall nat add "
    ) {
        &["chain", "action"]
    } else if *prefix == "/interface wireguard peers add " {
        &["interface", "public-key", "allowed-address"]
    } else if *prefix == "/interface wireguard add " {
        &["name", "listen-port"]
    } else if *prefix == "/ip address add " {
        &["address", "interface"]
    } else {
        &[]
    };
    for key in required {
        if !values.contains_key(key) {
            return Err(ArgumentIssue::new(
                ArgumentIssueCode::RequiredKey,
                format!("Plan Validation: відсутній аргумент {key}"),
            ));
        }
    }
    if *prefix == "/ip firewall filter add " || *prefix == "/ipv6 firewall filter add " {
        if !matches!(values.get("chain").copied(), Some("input" | "forward")) {
            return Err(ArgumentIssue::new(
                ArgumentIssueCode::FirewallChain,
                "Plan Validation: недозволений Firewall chain",
            ));
        }
        if !matches!(
            values.get("action").copied(),
            Some("accept" | "drop" | "fasttrack-connection" | "add-src-to-address-list")
        ) {
            return Err(ArgumentIssue::new(
                ArgumentIssueCode::FirewallAction,
                "Plan Validation: недозволена Firewall action",
            ));
        }
    }
    if *prefix == "/ip firewall nat add "
        && !((values.get("chain") == Some(&"srcnat")
            && values.get("action") == Some(&"masquerade"))
            || (values.get("chain") == Some(&"dstnat")
                && values.get("action") == Some(&"dst-nat")
                && values.contains_key("to-addresses")
                && values.contains_key("to-ports")
                && values.contains_key("dst-port")
                && matches!(values.get("protocol"), Some(&"tcp" | &"udp"))
                && (values.contains_key("in-interface-list")
                    || (values.contains_key("src-address") && values.contains_key("dst-address")))))
    {
        return Err(ArgumentIssue::new(
            ArgumentIssueCode::NatRule,
            "Plan Validation: некоректне правило srcnat/dstnat",
        ));
    }
    Ok(())
}

pub fn check(lines: &[String], full: bool) -> Result<(), PlanValidationError> {
    for (index, line) in lines.iter().enumerate() {
        if line.starts_with('#') {
            continue;
        }
        if !ALLOWED.iter().any(|prefix| line.starts_with(prefix)) {
            return Err(PlanValidationError::new(
                PlanValidationCode::UnsupportedCommand,
                format!("Plan Validation: невідома команда в рядку {}", index + 1),
            ));
        }
        // Забороняємо перенесення команд, керувальні символи та роздільники
        // RouterOS. Лапки дозволені лише як збалансована пара для public-key.
        if line
            .chars()
            .any(|ch| ch.is_control() || matches!(ch, ';' | '{' | '}' | '\\' | '$' | '`'))
        {
            return Err(PlanValidationError::new(
                PlanValidationCode::UnsafeCharacter,
                format!("Plan Validation: небезпечний символ у рядку {}", index + 1),
            ));
        }
        validate_arguments(line).map_err(|issue| {
            let _code = issue.code; // Тип причини доступний без аналізу тексту.
            PlanValidationError::new(PlanValidationCode::InvalidArguments, issue.detail)
        })?;
        let quote_count = line.bytes().filter(|b| *b == b'"').count();
        if quote_count != 0 && (quote_count != 2 || !line.contains("public-key=\"")) {
            return Err(PlanValidationError::new(
                PlanValidationCode::InvalidQuotes,
                format!("Plan Validation: некоректні лапки в рядку {}", index + 1),
            ));
        }
    }
    if full {
        let position = |needle: &str| -> Option<usize> {
            lines.iter().position(|line| line.starts_with(needle))
        };
        // Перевіряємо залежності лише для активних ресурсів.
        // Видалення DHCP Client допускається лише перед його створенням.
        let removals = lines
            .iter()
            .filter(|line| line.as_str() == "/ip dhcp-client remove [find]")
            .count();
        let adds = lines
            .iter()
            .filter(|line| line.starts_with("/ip dhcp-client add "))
            .count();
        if removals > 1 || (removals == 1 && adds != 1) {
            return Err(PlanValidationError::new(
                PlanValidationCode::InvalidDhcpCleanup,
                "Plan Validation: некоректна кількість команд WAN DHCP",
            ));
        }
        if removals == 1
            && position("/ip dhcp-client remove [find]") >= position("/ip dhcp-client add ")
        {
            return Err(PlanValidationError::new(
                PlanValidationCode::InvalidDhcpCleanup,
                "Plan Validation: DHCP Client remove має передувати add",
            ));
        }
        for (earlier, later) in [
            ("/interface bridge add ", "/ip address add "),
            ("/interface list add ", "/ip firewall filter add "),
            ("/interface wireguard add ", "/ip firewall filter add "),
            ("/interface wireguard add ", "/ip firewall nat add "),
        ] {
            if let (Some(a), Some(b)) = (position(earlier), position(later)) {
                if a >= b {
                    return Err(PlanValidationError::new(
                        PlanValidationCode::WrongOrder,
                        format!("Plan Validation: порушено порядок {earlier} → {later}"),
                    ));
                }
            }
        }
        for (chain, marker) in [
            ("chain=input", "comment=mcm-input-final-drop"),
            ("chain=forward", "comment=mcm-forward-final-drop"),
        ] {
            let drop = lines.iter().position(|line| line.contains(marker));
            if let Some(drop) = drop {
                if lines.iter().skip(drop + 1).any(|line| {
                    line.starts_with("/ip firewall filter add ")
                        && line.contains(chain)
                        && line.contains("action=accept")
                }) {
                    return Err(PlanValidationError::new(
                        PlanValidationCode::AcceptAfterDrop,
                        format!("Plan Validation: правило ACCEPT після {marker}"),
                    ));
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::check;
    fn lines(items: &[&str]) -> Vec<String> {
        items.iter().map(|item| (*item).to_owned()).collect()
    }

    #[test]
    fn rejects_unsupported_and_injected_commands() {
        for command in [
            "/system reboot",
            "/import file-name=x",
            "/ip dns set servers=1.1.1.1; /system reboot",
            "/ip dns set servers=1.1.1.1\n/system reboot",
            "/ip dns set servers=$malicious",
        ] {
            assert!(check(&lines(&[command]), false).is_err(), "{command}");
        }
    }

    #[test]
    fn accepts_safe_wireguard_public_key() {
        assert!(check(&lines(&["/interface wireguard peers add interface=WG-HOME public-key=\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\" allowed-address=10.77.0.2/32"]), false).is_ok());
    }

    #[test]
    fn rejects_unbalanced_or_unexpected_quotes() {
        assert!(check(
            &lines(&["/interface wireguard peers add public-key=\"bad"]),
            false
        )
        .is_err());
        assert!(check(&lines(&["/ip dns set servers=\"1.1.1.1\""]), false).is_err());
    }

    #[test]
    fn rejects_missing_required_arguments() {
        for command in [
            "/ip firewall filter add chain=input comment=mcm-example",
            "/ip firewall nat add chain=srcnat comment=mcm-example",
            "/interface wireguard add name=WG-HOME",
            "/interface wireguard peers add interface=WG-HOME allowed-address=10.77.0.2/32",
        ] {
            assert!(check(&lines(&[command]), false).is_err(), "{command}");
        }
        // Повна декларація WireGuard містить обидва обов'язкові параметри.
        assert!(check(
            &lines(&["/interface wireguard add name=WG-HOME listen-port=51820",]),
            false
        )
        .is_ok());
    }

    #[test]
    fn rejects_duplicate_keys_and_unbalanced_find() {
        for command in [
            "/ip firewall filter add chain=input chain=forward action=accept",
            "/ip service set [find name=ssh port=22",
            "/ip service set [find name=ssh] disabled=no disabled=yes",
            "/interface ethernet set [find name=ssh] [find name=ftp] disabled=yes",
        ] {
            assert!(check(&lines(&[command]), false).is_err(), "{command}");
        }
    }

    #[test]
    fn rejects_dangerous_firewall_actions_and_nat() {
        for command in [
            "/ip firewall filter add chain=input action=passthrough",
            "/ip firewall filter add chain=output action=accept",
            "/ip firewall nat add chain=dstnat action=masquerade",
            "/ip firewall nat add chain=srcnat action=redirect",
        ] {
            assert!(check(&lines(&[command]), false).is_err(), "{command}");
        }
    }

    #[test]
    fn permits_safe_find_and_wireguard_values() {
        assert!(check(&lines(&[
            "/ip service set [find name=ssh] disabled=no port=22",
            "/ip firewall filter add chain=forward action=drop connection-nat-state=!dstnat",
            "/interface wireguard peers add interface=WG-HOME public-key=\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\" allowed-address=10.77.0.2/32",
        ]), false).is_ok());
    }

    #[test]
    fn rejects_wrong_dependency_order() {
        assert!(check(
            &lines(&[
                "/ip firewall filter add chain=input action=drop",
                "/interface wireguard add name=WG-HOME listen-port=51820",
            ]),
            true
        )
        .is_err());
        assert!(check(
            &lines(&[
                "/interface wireguard add name=WG-HOME listen-port=51820",
                "/ip firewall filter add chain=input action=drop",
            ]),
            true
        )
        .is_ok());
    }

    #[test]
    fn rejects_accept_after_final_drop() {
        assert!(check(
            &lines(&[
                "/ip firewall filter add chain=input action=drop comment=mcm-input-final-drop",
                "/ip firewall filter add chain=input action=accept protocol=tcp dst-port=22",
            ]),
            true
        )
        .is_err());
    }
}

#[cfg(test)]
mod wan_dhcp_cleanup_tests {
    use super::check;

    #[test]
    fn permits_only_exact_dhcp_cleanup_command() {
        let exact = vec!["/ip dhcp-client remove [find]".to_string()];
        assert!(check(&exact, false).is_ok());
        for unsafe_command in [
            "/ip dhcp-client remove [find] disabled=yes",
            "/ip dhcp-client remove [find interface=00_wan]",
            "/ip dhcp-client remove [find]; /system reboot",
            "/ip address remove [find]",
        ] {
            assert!(
                check(&[unsafe_command.to_string()], false).is_err(),
                "{unsafe_command}"
            );
        }
    }

    #[test]
    fn rejects_reverse_or_repeated_dhcp_cleanup() {
        let remove = "/ip dhcp-client remove [find]".to_string();
        let add =
            "/ip dhcp-client add interface=WAN disabled=no add-default-route=yes use-peer-dns=no"
                .to_string();
        assert!(check(&[remove.clone(), add.clone()], true).is_ok());
        assert!(check(&[add.clone(), remove.clone()], true).is_err());
        assert!(check(&[remove.clone(), remove, add], true).is_err());
    }
}

#[cfg(test)]
mod regression_typed_validation_tests {
    use super::{check, PlanValidationCode};

    #[test]
    fn unsupported_command_keeps_typed_code_and_original_text() {
        let result = check(&["/system reboot".to_string()], false).unwrap_err();
        assert_eq!(result.code, PlanValidationCode::UnsupportedCommand);
        assert_eq!(
            result.to_string(),
            "Plan Validation: невідома команда в рядку 1"
        );
    }

    #[test]
    fn invalid_argument_and_control_character_have_distinct_codes() {
        // Префікс команди дозволений, але необхідні параметри відсутні.
        let invalid = check(&["/ip dns set ".to_string()], false).unwrap_err();
        assert_eq!(invalid.code, PlanValidationCode::InvalidArguments);
        let unsafe_character =
            check(&["/ip dns set servers=1.1.1.1;".to_string()], false).unwrap_err();
        assert_eq!(unsafe_character.code, PlanValidationCode::UnsafeCharacter);
    }
}

// Негативні регресії: розрізняємо причину, зберігаємо історичний текст.
#[cfg(test)]
mod regression_argument_issue_tests {
    use super::*;

    #[test]
    fn bracket_and_quote_errors_have_distinct_codes_and_original_text() {
        let broken = arguments("name=[unexpected").unwrap_err();
        assert_eq!(broken.code, ArgumentIssueCode::Unclosed);
        assert_eq!(
            broken.to_string(),
            "Plan Validation: незакриті дужки або лапки"
        );
        let unmatched = arguments("name=]").unwrap_err();
        assert_eq!(unmatched.code, ArgumentIssueCode::Brackets);
        assert_eq!(unmatched.to_string(), "Plan Validation: неправильні дужки");
    }

    #[test]
    fn forbidden_firewall_action_is_typed_without_message_matching() {
        let err =
            validate_arguments("/ip firewall filter add chain=input action=disable").unwrap_err();
        assert_eq!(err.code, ArgumentIssueCode::FirewallAction);
        assert_eq!(
            err.to_string(),
            "Plan Validation: недозволена Firewall action"
        );
    }

    #[test]
    fn invalid_find_selector_is_typed() {
        let err = validate_arguments("/interface ethernet set [find interface=x] disabled=no")
            .unwrap_err();
        assert_eq!(err.code, ArgumentIssueCode::FindSelector);
        assert_eq!(
            err.to_string(),
            "Plan Validation: небезпечний find selector"
        );
    }
}
