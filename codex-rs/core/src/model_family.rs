use crate::config_types::ReasoningSummaryFormat;
use crate::gpt_oss::GptOssVariant;
use crate::gpt_oss::{self};
use crate::tools::handlers::apply_patch::ApplyPatchToolType;
use codex_protocol::config_types::ReasoningEffort as ReasoningEffortConfig;

/// The `instructions` field in the payload sent to a model should always start
/// with this content.
const BASE_INSTRUCTIONS: &str = include_str!("../prompt.md");
const GPT_5_CODEX_INSTRUCTIONS: &str = include_str!("../gpt_5_codex_prompt.md");

/// A model family is a group of models that share certain characteristics.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelFamily {
    /// The full model slug used to derive this model family, e.g.
    /// "gpt-4.1-2025-04-14".
    pub slug: String,

    /// The model family name, e.g. "gpt-4.1". Note this should able to be used
    /// with [`crate::openai_model_info::get_model_info`].
    pub family: String,

    /// True if the model needs additional instructions on how to use the
    /// "virtual" `apply_patch` CLI.
    pub needs_special_apply_patch_instructions: bool,

    // Whether the `reasoning` field can be set when making a request to this
    // model family. Note it has `effort` and `summary` subfields (though
    // `summary` is optional).
    pub supports_reasoning_summaries: bool,

    // Define if we need a special handling of reasoning summary
    pub reasoning_summary_format: ReasoningSummaryFormat,

    // This should be set to true when the model expects a tool named
    // "local_shell" to be provided. Its contract must be understood natively by
    // the model such that its description can be omitted.
    // See https://platform.openai.com/docs/guides/tools-local-shell
    pub uses_local_shell_tool: bool,

    /// Present if the model performs better when `apply_patch` is provided as
    /// a tool call instead of just a bash command
    pub apply_patch_tool_type: Option<ApplyPatchToolType>,

    /// Optional default reasoning effort to apply when the user has not set one.
    pub default_reasoning_effort: Option<ReasoningEffortConfig>,

    /// When set, identifies which gpt-oss variant this family represents.
    pub gpt_oss_variant: Option<GptOssVariant>,

    // Instructions to use for querying the model
    pub base_instructions: String,

    /// Names of beta tools that should be exposed to this model family.
    pub experimental_supported_tools: Vec<String>,
}

macro_rules! model_family {
    (
        $slug:expr, $family:expr $(, $key:ident : $value:expr )* $(,)?
    ) => {{
        // defaults
        let mut mf = ModelFamily {
            slug: $slug.to_string(),
            family: $family.to_string(),
            needs_special_apply_patch_instructions: false,
            supports_reasoning_summaries: false,
            reasoning_summary_format: ReasoningSummaryFormat::None,
            uses_local_shell_tool: false,
            apply_patch_tool_type: None,
            default_reasoning_effort: None,
            gpt_oss_variant: None,
            base_instructions: BASE_INSTRUCTIONS.to_string(),
            experimental_supported_tools: Vec::new(),
        };
        // apply overrides
        $(
            mf.$key = $value;
        )*
        Some(mf)
    }};
}

/// Returns a `ModelFamily` for the given model slug, or `None` if the slug
/// does not match any known model family.
pub fn find_family_for_model(slug: &str) -> Option<ModelFamily> {
    if slug.starts_with("o3") {
        model_family!(
            slug, "o3",
            supports_reasoning_summaries: true,
            needs_special_apply_patch_instructions: true,
        )
    } else if slug.starts_with("o4-mini") {
        model_family!(
            slug, "o4-mini",
            supports_reasoning_summaries: true,
            needs_special_apply_patch_instructions: true,
        )
    } else if slug.starts_with("codex-mini-latest") {
        model_family!(
            slug, "codex-mini-latest",
            supports_reasoning_summaries: true,
            uses_local_shell_tool: true,
            needs_special_apply_patch_instructions: true,
        )
    } else if slug.starts_with("gpt-4.1") {
        model_family!(
            slug, "gpt-4.1",
            needs_special_apply_patch_instructions: true,
        )
    } else if let Some(variant) = gpt_oss::detect_variant(slug) {
        let appendix = variant.developer_appendix();
        let base_instructions = format!("{}\n{}", BASE_INSTRUCTIONS, appendix.trim());
        model_family!(
            slug, variant.canonical_family(),
            apply_patch_tool_type: Some(ApplyPatchToolType::Function),
            supports_reasoning_summaries: matches!(variant, GptOssVariant::V120B),
            default_reasoning_effort: Some(variant.default_reasoning_effort()),
            gpt_oss_variant: Some(variant),
            base_instructions: base_instructions,
        )
    } else if slug.starts_with("gpt-oss") || slug.starts_with("openai/gpt-oss") {
        model_family!(slug, "gpt-oss", apply_patch_tool_type: Some(ApplyPatchToolType::Function))
    } else if slug.starts_with("gpt-4o") {
        model_family!(slug, "gpt-4o", needs_special_apply_patch_instructions: true)
    } else if slug.starts_with("gpt-3.5") {
        model_family!(slug, "gpt-3.5", needs_special_apply_patch_instructions: true)
    } else if slug.starts_with("codex-") || slug.starts_with("gpt-5-codex") {
        model_family!(
            slug, slug,
            supports_reasoning_summaries: true,
            reasoning_summary_format: ReasoningSummaryFormat::Experimental,
            base_instructions: GPT_5_CODEX_INSTRUCTIONS.to_string(),
            experimental_supported_tools: vec!["read_file".to_string()],
        )
    } else if slug.starts_with("gpt-5") {
        model_family!(
            slug, "gpt-5",
            supports_reasoning_summaries: true,
            needs_special_apply_patch_instructions: true,
        )
    } else {
        None
    }
}

pub fn derive_default_model_family(model: &str) -> ModelFamily {
    ModelFamily {
        slug: model.to_string(),
        family: model.to_string(),
        needs_special_apply_patch_instructions: false,
        supports_reasoning_summaries: false,
        reasoning_summary_format: ReasoningSummaryFormat::None,
        uses_local_shell_tool: false,
        apply_patch_tool_type: None,
        default_reasoning_effort: None,
        gpt_oss_variant: None,
        base_instructions: BASE_INSTRUCTIONS.to_string(),
        experimental_supported_tools: Vec::new(),
    }
}
