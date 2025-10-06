use codex_protocol::config_types::ReasoningEffort;

/// Variants of the gpt-oss family we support.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum GptOssVariant {
    V20B,
    V120B,
}

impl GptOssVariant {
    pub fn canonical_family(self) -> &'static str {
        match self {
            GptOssVariant::V20B => "gpt-oss-20b",
            GptOssVariant::V120B => "gpt-oss-120b",
        }
    }

    pub fn default_reasoning_effort(self) -> ReasoningEffort {
        match self {
            GptOssVariant::V20B => ReasoningEffort::Low,
            GptOssVariant::V120B => ReasoningEffort::High,
        }
    }

    pub fn developer_appendix(self) -> &'static str {
        match self {
            GptOssVariant::V20B => include_str!("gpt_oss_prompt_20b.md"),
            GptOssVariant::V120B => include_str!("gpt_oss_prompt_120b.md"),
        }
    }
}

/// Normalize common slug representations into an `Option<GptOssVariant>`.
pub fn detect_variant(slug: &str) -> Option<GptOssVariant> {
    let slug = slug.trim();
    let slug = slug.strip_prefix("openai/").unwrap_or(slug);
    if slug.starts_with("gpt-oss:20b") || slug.starts_with("gpt-oss-20b") {
        Some(GptOssVariant::V20B)
    } else if slug.starts_with("gpt-oss:120b") || slug.starts_with("gpt-oss-120b") {
        Some(GptOssVariant::V120B)
    } else {
        None
    }
}
