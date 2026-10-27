use mikrotik_config_manager::typed_config::{read_typed, ConnectionConfig};
use std::path::Path;

#[test]
fn both_profiles_use_strict_connection_schema() {
    for name in ["test", "hap-ac"] {
        let file = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("routers")
            .join(name)
            .join("connection.toml");
        let conf: ConnectionConfig = read_typed(&file).expect("connection.toml");
        assert!(conf.connection.port > 0);
        assert!(!conf.connection.user.is_empty());
        assert!(!conf.connection.identity_file.is_empty());
    }
}

#[test]
fn rejects_unknown_fields_missing_fields_and_wrong_port_types() {
    let valid =
        "[connection]\nhost='192.168.88.1'\nport=22\nuser='admin'\nidentity_file='~/.ssh/id'\n";
    assert!(toml::from_str::<ConnectionConfig>(valid).is_ok());
    for bad in [
        valid.replace("port=22", "port='22'"),
        valid.replace("port=22\n", ""),
        format!("{valid}unknown=true\n"),
        format!("{valid}[another]\nx=1\n"),
        valid.replace("port=22", "port=70000"),
    ] {
        assert!(
            toml::from_str::<ConnectionConfig>(&bad).is_err(),
            "accepted invalid config"
        );
    }
}
