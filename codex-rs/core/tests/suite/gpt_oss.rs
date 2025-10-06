use codex_core::WireApi;
use codex_core::config::Config;
use codex_core::config::ConfigOverrides;
use codex_core::config::ConfigToml;
use codex_core::gpt_oss::GptOssVariant;
use codex_core::protocol_config_types::ReasoningEffort;
use pretty_assertions::assert_eq;
use tempfile::TempDir;

fn load_config(model: &str) -> Config {
    let codex_home = TempDir::new().unwrap_or_else(|err| panic!("failed to create tempdir: {err}"));
    Config::load_from_base_config_with_overrides(
        ConfigToml::default(),
        ConfigOverrides {
            model: Some(model.to_string()),
            model_provider: Some("oss".to_string()),
            ..ConfigOverrides::default()
        },
        codex_home.path().to_path_buf(),
    )
    .unwrap_or_else(|err| panic!("failed to load config: {err}"))
}

#[test]
fn gpt_oss_20b_defaults_low_reasoning() {
    let config = load_config("gpt-oss:20b");

    assert_eq!(config.model, "gpt-oss:20b");
    assert_eq!(config.model_provider.wire_api, WireApi::Responses);
    assert_eq!(
        config.model_provider.base_url.as_deref(),
        Some("http://localhost:8000/v1")
    );
    assert_eq!(config.model_reasoning_effort, Some(ReasoningEffort::Low));
    assert_eq!(
        config.model_family.gpt_oss_variant,
        Some(GptOssVariant::V20B)
    );
    assert!(
        config
            .model_family
            .base_instructions
            .contains("Harmony context for gpt-oss-20b")
    );
    assert!(!config.model_family.supports_reasoning_summaries);
}

#[test]
fn gpt_oss_120b_defaults_high_reasoning() {
    let config = load_config("gpt-oss:120b");

    assert_eq!(config.model, "gpt-oss:120b");
    assert_eq!(config.model_provider.wire_api, WireApi::Responses);
    assert_eq!(
        config.model_provider.base_url.as_deref(),
        Some("http://localhost:8000/v1")
    );
    assert_eq!(config.model_reasoning_effort, Some(ReasoningEffort::High));
    assert_eq!(
        config.model_family.gpt_oss_variant,
        Some(GptOssVariant::V120B)
    );
    assert!(
        config
            .model_family
            .base_instructions
            .contains("Harmony context for gpt-oss-120b")
    );
    assert!(config.model_family.supports_reasoning_summaries);
}
