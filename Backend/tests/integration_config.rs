use std::path::PathBuf;

#[test]
fn test_config_load_from_file() {
    let config_path = PathBuf::from("config.toml");
    assert!(config_path.exists(), "config.toml should exist");

    let content = std::fs::read_to_string(&config_path).unwrap();
    let config: nebula_backend::config::Config = toml::from_str(&content).unwrap();

    assert_eq!(config.input_port, 3001);
    assert_eq!(config.output_port, 3002);
    assert!(config.addon.enabled);
    assert_eq!(config.agent.command, "echo");
    assert_eq!(config.agent.mode, "stdio");
}

#[test]
fn test_session_manager_full_lifecycle() {
    let dir = std::env::temp_dir().join(format!("nebula_int_test_{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&dir).unwrap();

    let base = dir.join("session-history");
    let mut manager = nebula_backend::session::SessionManager::new(
        base.to_str().unwrap(),
    )
    .unwrap();

    assert!(manager.list_sessions().is_empty());

    let session = manager.create_session().unwrap();
    assert!(!session.id.is_empty());
    assert_eq!(manager.list_sessions().len(), 1);

    manager
        .record_message(&session.id, "User", "Integration test message")
        .unwrap();
    manager
        .record_message(&session.id, "Agent", "Integration test response")
        .unwrap();

    let updated = manager.get_session(&session.id).unwrap();
    assert_eq!(updated.message_count, 2);

    let asset_path = manager
        .save_asset(&session.id, "integration_test.txt", b"integration data")
        .unwrap();
    assert!(asset_path.exists());
    assert_eq!(
        std::fs::read_to_string(&asset_path).unwrap(),
        "integration data"
    );

    let chat_path = updated.folder_path.join("chat.md");
    let chat = std::fs::read_to_string(&chat_path).unwrap();
    assert!(chat.contains("Integration test message"));
    assert!(chat.contains("Integration test response"));

    std::fs::remove_dir_all(&dir).unwrap();
}
