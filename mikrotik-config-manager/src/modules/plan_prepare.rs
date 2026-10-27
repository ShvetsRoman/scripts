use super::*;

// Завантаження, валідація й побудова типізованих модулів перед генерацією RSC.
pub(super) struct Prepared {
    pub(super) interfaces: interfaces::Interfaces,
    pub(super) bridge: bridge::Bridge,
    pub(super) network: network::Network,
    pub(super) lists: lists::Lists,
    pub(super) dhcp: dhcp::Dhcp,
    pub(super) leases: leases::Leases,
    pub(super) dns: dns::Dns,
    pub(super) wan: wan::Wan,
    pub(super) wireguard: wireguard::Wireguard,
    pub(super) nat: nat::Nat,
    pub(super) firewall: firewall::Firewall,
    pub(super) ipv6: ipv6::Ipv6,
    pub(super) wireless: wireless::Wireless,
    pub(super) system: system::System,
    pub(super) services: services::Services,
    pub(super) security: security::Security,
}

// Типізований контракт: підготовлені компоненти передаються генератору без
// проміжних рядкових мап і без повторного читання TOML.
impl Prepared {
    pub(super) fn components(&self) -> plan_render::Components<'_> {
        plan_render::Components {
            interfaces: &self.interfaces,
            bridge: &self.bridge,
            network: &self.network,
            lists: &self.lists,
            dhcp: &self.dhcp,
            leases: &self.leases,
            dns: &self.dns,
            wan: &self.wan,
            wireguard: &self.wireguard,
            nat: &self.nat,
            firewall: &self.firewall,
            ipv6: &self.ipv6,
            wireless: &self.wireless,
            system: &self.system,
            services: &self.services,
            security: &self.security,
        }
    }
}

pub(super) fn prepare(root: &Path, router: &str) -> Result<Prepared, reference_error::PlanError> {
    let dir = router_dir(root, router)?;
    // Навіть невикористану у плані connection-секцію перевіряємо без підключення.
    let typed_connection: mikrotik_config_manager::typed_config::ConnectionConfig =
        read_typed(&dir.join("connection.toml")).map_err(|e| {
            reference_error::PlanBoundaryError::with_config(
                reference_error::PlanBoundaryCode::ConnectionConfig,
                format!("Configuration Integrity: {e}"),
                e,
            )
        })?;
    if typed_connection.connection.port == 0 {
        return Err(reference_error::ConfigurationError {
            code: reference_error::ConfigurationCode::ConnectionPortZero,
            detail: "Configuration Integrity: connection.port: порт 0 заборонено".into(),
        }
        .into());
    }
    let typed_services: ServicesConfig = read_typed(&dir.join("services.toml"))?;
    // Обов'язкові VPN-прапорці перевіряє Serde без значень за замовчуванням.
    // Зберігаємо діагностичний контракт Configuration Integrity для CLI.
    let typed_wg: mikrotik_config_manager::typed_config::WireguardConfig =
        mikrotik_config_manager::typed_config::read_typed(&dir.join("wireguard.toml")).map_err(
            |err| {
                reference_error::PlanBoundaryError::with_config(
                    reference_error::PlanBoundaryCode::WireguardConfig,
                    format!("Configuration Integrity: {err}"),
                    err,
                )
            },
        )?;
    if typed_wg.wireguard.listen_port == 0 {
        return Err(reference_error::ConfigurationError {
            code: reference_error::ConfigurationCode::WireguardPortZero,
            detail: "Configuration Integrity: wireguard:wireguard.listen_port: порт 0 заборонено"
                .into(),
        }
        .into());
    }
    // Суворо перевіряємо формат ID до генерації RouterOS-команд.
    // Набір фізичних портів визначається виключно TOML, без фіксованої верхньої межі.
    // Діагностика зберігає контракт Configuration Integrity без рядкової мапи.
    // Перевірка імен тепер працює лише з типізованими деклараціями.
    let typed_interfaces: InterfacesConfig = read_typed(&dir.join("interfaces.toml"))?;
    let typed_bridge: BridgeConfig = read_typed(&dir.join("bridge.toml"))?;
    let typed_lists: ListsConfig = read_typed(&dir.join("lists.toml"))?;
    let typed_dhcp: DhcpConfig = read_typed(&dir.join("dhcp.toml"))?;
    let typed_wireless: WirelessConfig = read_typed(&dir.join("wireless.toml"))?;
    let typed_network: NetworkConfig = read_typed(&dir.join("network.toml"))?;
    // Перевіряємо міжмодульні посилання один раз, використовуючи вже завантажені
    // serde-структури. Типізована помилка передається до CLI через Result.
    if let Some(code) = reference_error::inspect(
        &typed_wireless,
        &typed_interfaces,
        &typed_bridge,
        &typed_network,
    ) {
        return Err(reference_error::PlanError::Reference(code));
    }
    for id in typed_interfaces.interfaces.keys() {
        if !valid_physical_id(id) {
            return Err(reference_error::ConfigurationError {
                code: reference_error::ConfigurationCode::InvalidPhysicalInterface,
                detail: format!(
                    "Configuration Integrity: невідома таблиця interfaces:interfaces.{id}"
                ),
            }
            .into());
        }
    }
    for id in typed_bridge.ports.keys() {
        if !valid_physical_id(id) {
            return Err(reference_error::ConfigurationError {
                code: reference_error::ConfigurationCode::InvalidBridgePort,
                detail: format!("Configuration Integrity: невідома таблиця bridge:ports.{id}"),
            }
            .into());
        }
    }
    validation::validate_names(
        &typed_interfaces,
        &typed_bridge,
        &typed_lists,
        &typed_dhcp,
        &typed_wireless,
    )?;

    // Bridge та Management: лише типізовані поля; старі рядкові секції видалено.
    // Stage 9: помилка вже має код до передачі через Result, без аналізу тексту.
    let bridge_resource =
        typed_bridge
            .bridge
            .get("lan")
            .ok_or_else(|| reference_error::ConfigurationError {
                code: reference_error::ConfigurationCode::MissingLanBridge,
                detail: "Bridge: немає bridge.lan".into(),
            })?;
    let bridge_name = bridge_resource.name.clone();
    token(&bridge_name, "bridge.name").map_err(|error| {
        reference_error::PlanError::Shared(shared_errors::SharedError::from_token(
            shared_errors::SharedCode::InvalidToken,
            error,
        ))
    })?;
    if !bridge_resource.enabled {
        // Тип помилки задаємо безпосередньо під час перевірки стану LAN bridge.
        return Err(reference_error::ConfigurationError {
            code: reference_error::ConfigurationCode::DisabledLanBridge,
            detail: "LAN bridge вимкнено".into(),
        }
        .into());
    }
    let management_ref = typed_network.management.interface.as_str();
    // Management визначається конфігурацією, не назвою профілю.
    // Поточний контракт домашніх профілів: Management тільки через LAN bridge.
    if management_ref != "@bridge.lan" {
        return Err(reference_error::ConfigurationError {
            code: reference_error::ConfigurationCode::InvalidManagementReference,
            detail: "Недопустиме Management ID".into(),
        }
        .into());
    }
    let management_name = bridge_name.as_str();
    for entry in typed_interfaces.interfaces.values() {
        token(&entry.name, "interface.name").map_err(|error| {
            reference_error::PlanError::Shared(shared_errors::SharedError::from_token(
                shared_errors::SharedCode::InvalidToken,
                error,
            ))
        })?;
    }
    // WAN визначаємо до побудови команд інтерфейсів: відключати його заборонено.
    let wan_physical = typed_network
        .wan
        .interface
        .strip_prefix("@interfaces.")
        .filter(|id| !id.is_empty())
        .ok_or_else(|| {
            shared_errors::SharedError::new(
                shared_errors::SharedCode::InvalidWanReference,
                "WAN: некоректне посилання на фізичний інтерфейс",
            )
        })?;
    // Генератор фізичних інтерфейсів споживає типізовану декларацію напряму.
    let interfaces =
        interfaces::Interfaces::parse(&typed_interfaces.interfaces, management_name, wan_physical)?;
    let resolve = |id: &str| -> Result<String, shared_errors::SharedError> {
        if id == "bridge.lan" {
            return Ok(bridge_name.clone());
        }
        resolved_interface_name(&typed_interfaces, id)
    };
    // Bridge: ресурси Serde без проміжного HashMap<String, String>.
    let mut resolved_ports = Vec::new();
    let mut enabled_port_ids = Vec::new();
    let mut hw_options = HashSet::new();
    for (id, port) in &typed_bridge.ports {
        if port.bridge != "@bridge.lan" {
            return Err(reference_error::PlanBoundaryError::new(
                reference_error::PlanBoundaryCode::BridgeId,
                "Невідомий Bridge ID",
            )
            .into());
        }
        if port.enabled {
            resolved_ports.push(resolve(id)?);
            enabled_port_ids.push(id.clone());
            hw_options.insert(port.hw);
        }
    }
    if resolved_ports.is_empty() {
        return Err(reference_error::ConfigurationError {
            code: reference_error::ConfigurationCode::MissingBridgePorts,
            detail: "LAN Bridge не містить портів".into(),
        }
        .into());
    }
    if hw_options.len() > 1 {
        return Err(reference_error::ConfigurationError {
            code: reference_error::ConfigurationCode::MixedBridgeHardware,
            detail: "Неоднакові HW-властивості портів: потрібен окремий wireless-модуль".into(),
        }
        .into());
    }
    let bridge = bridge::Bridge::parse(
        bridge_resource,
        enabled_port_ids,
        hw_options.contains(&true),
        &interfaces,
    )?;
    if typed_network.network.lan.interface != "@bridge.lan" {
        return Err(reference_error::PlanBoundaryError::new(
            reference_error::PlanBoundaryCode::LanBridgeReference,
            "network.lan повинен посилатися на bridge.lan",
        )
        .into());
    }
    // Network: передаємо строго типізовані поля без рядкового адаптера.
    let network = network::Network::parse(
        &typed_network,
        &bridge_name,
        management_name,
        &resolved_ports,
    )?;
    // Bridge і LAN повинні містити однакові порти, незалежно від порядку.
    if !same_bridge_ports(&bridge.ports, &network.lan_ports) {
        return Err(reference_error::ConfigurationError {
            code: reference_error::ConfigurationCode::BridgePortMismatch,
            detail: "Некоректні Bridge Ports".into(),
        }
        .into());
    }
    // Serde зберігає декларативне @interfaces.ID; нормалізований WAN ID
    // перевіряється у normalized_wan_id перед пошуком фізичного порту.
    let wan_id = normalized_wan_id(&typed_network.wan.interface, wan_physical)?;
    if wan_id == management_ref {
        // Конфлікт WAN/Management перевіряємо в тому самому місці плану.
        return Err(reference_error::ConfigurationError {
            code: reference_error::ConfigurationCode::WanManagementConflict,
            detail: "WAN не може збігатися з Management".into(),
        }
        .into());
    }
    let wan = wan::Wan::parse(&typed_network.wan, resolve(wan_id)?, &network)?;
    if bridge.ports.contains(&wan.interface) {
        // WAN не може бути портом LAN-мосту; зберігаємо початковий порядок перевірок.
        return Err(reference_error::ConfigurationError {
            code: reference_error::ConfigurationCode::WanInBridge,
            detail: "WAN входить до Bridge".into(),
        }
        .into());
    }
    // Lists: зберігаємо логічні посилання й порядок команд без рядкового адаптера.
    let wan_list =
        typed_lists
            .lists
            .get("wan")
            .ok_or_else(|| reference_error::ConfigurationError {
                code: reference_error::ConfigurationCode::MissingWanList,
                detail: "Немає lists.wan".into(),
            })?;
    let lan_list =
        typed_lists
            .lists
            .get("lan")
            .ok_or_else(|| reference_error::ConfigurationError {
                code: reference_error::ConfigurationCode::MissingLanList,
                detail: "Немає lists.lan".into(),
            })?;
    if wan_list.members.as_slice() != ["@wan"] || lan_list.members.as_slice() != ["@bridge.lan"] {
        return Err(reference_error::ConfigurationError {
            code: reference_error::ConfigurationCode::InvalidInterfaceList,
            detail: "Некоректне посилання Interface List".into(),
        }
        .into());
    }
    let lists = lists::Lists::parse(wan_list, lan_list, &network, &wan)?;
    if typed_dhcp.server.lan.interface != "@bridge.lan" || typed_dhcp.server.lan.pool != "@pool.lan"
    {
        return Err(reference_error::ConfigurationError {
            code: reference_error::ConfigurationCode::InvalidDhcpReference,
            detail: "Некоректний DHCP ID".into(),
        }
        .into());
    }
    // DHCP: типізовані pool/server/network із serde без HashMap.
    let dhcp = dhcp::Dhcp::parse(&typed_dhcp, &network)?;
    if typed_dhcp.leases.server != "@server.lan" {
        return Err(reference_error::ConfigurationError {
            code: reference_error::ConfigurationCode::InvalidDhcpServerReference,
            detail: "Невідомий ID DHCP Server".into(),
        }
        .into());
    }
    let leases = leases::Leases::parse(&typed_dhcp.leases, &network, &dhcp)?;
    // DNS отримує bool і список серверів безпосередньо зі схеми Serde.
    let typed_dns: DnsConfig = read_typed(&dir.join("dns.toml"))?;
    let dns = dns::Dns::parse(&typed_dns.dns, &network)?;
    // Генератор NAT отримує безпосередньо типізовані ресурси, без рядкової мапи.
    let typed_nat: NatConfig = read_typed(&dir.join("nat.toml"))?;
    let nat = nat::Nat::parse(&typed_nat, &wan, &lists)?;
    // Порти Firewall не дублюємо: вони визначаються лише сервісами.
    let services = services::Services::parse(&typed_services, &lists, &network)?;
    // Firewall бере типізовану декларацію, а порти SSH/WinBox — із Services.
    let typed_firewall: FirewallConfig = read_typed(&dir.join("firewall.toml"))?;
    let firewall = firewall::Firewall::parse(
        &typed_firewall.firewall,
        &network,
        &lists,
        dns.allow_remote_requests,
        services.ssh_port,
        services.winbox_port,
        services.winbox_enabled,
    )?;
    let typed_ipv6: Ipv6Config = read_typed(&dir.join("ipv6.toml"))?;
    let ipv6 = ipv6::Ipv6::parse(&typed_ipv6.ipv6, &lists.lan, &lists.wan)?;
    let typed_system: SystemConfig = read_typed(&dir.join("system.toml"))?;
    let system = system::System::parse(&typed_system)?;
    let security = security::Security::parse(&typed_system, &lists, router)?;
    let wireless = wireless::Wireless::parse(&typed_wireless, &typed_interfaces, &bridge_name)?;
    let wireguard = wireguard::Wireguard::parse(&typed_wg, &network, &wan, &lists)?;
    consistency::check(&consistency::Context {
        network: &network,
        dhcp: &dhcp,
        dns: &dns,
        wan: &wan,
        nat: &typed_nat,
        firewall: &typed_firewall,
        services: &services,
        wireguard: &typed_wg,
    })?;
    finalization::check(
        &typed_firewall,
        &typed_services,
        &typed_wg,
        &typed_system,
        &typed_lists,
    )?;
    if wireguard.enabled() && !typed_firewall.firewall.enabled {
        return Err(reference_error::ConfigurationError {
            code: reference_error::ConfigurationCode::WireguardRequiresFirewall,
            detail: "WireGuard потребує увімкненого Firewall".into(),
        }
        .into());
    }
    static_audit::check(&static_audit::Context {
        network: &typed_network,
        bridge: &typed_bridge,
        interfaces: &typed_interfaces,
        dhcp: &typed_dhcp,
        dns: &typed_dns,
        firewall: &typed_firewall,
        wireless: &typed_wireless,
        wireguard: &typed_wg,
    })?;
    Ok(Prepared {
        interfaces,
        bridge,
        network,
        lists,
        dhcp,
        leases,
        dns,
        wan,
        wireguard,
        nat,
        firewall,
        ipv6,
        wireless,
        system,
        services,
        security,
    })
}
