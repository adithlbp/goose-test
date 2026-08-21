import { listLocalModels } from '../../../acp/local-inference';
import {
  acpListProviderDetails,
  acpListProviderModels,
  acpListProviderSupportedModels,
} from '../../../acp/providers';
import type { ProviderDetails, ThinkingEffort } from '../../../types/providers';
import { errorMessage as getErrorMessage } from '../../../utils/conversionUtils';
import { fetchCanonicalModelInfo } from '../../../utils/canonical';

export default interface Model {
  id?: number; // Make `id` optional to allow user-defined models
  name: string;
  provider: string;
  lastUsed?: string;
  alias?: string; // optional model display name
  subtext?: string; // goes below model name if not the provider
  context_limit?: number; // optional context limit override
  reasoning?: boolean; // optional reasoning/thinking support metadata
  request_params?: Record<string, unknown> & { thinking_effort?: ThinkingEffort }; // provider-specific request parameters
}

export function createModelStruct(
  modelName: string,
  provider: string,
  id?: number, // Make `id` optional to allow user-defined models
  lastUsed?: string,
  alias?: string, // optional model display name
  subtext?: string
): Model {
  // use the metadata to create a Model
  return {
    name: modelName,
    provider: provider,
    alias: alias,
    id: id,
    lastUsed: lastUsed,
    subtext: subtext,
  };
}

export async function getProviderMetadata(providerName: string) {
  const providers = await acpListProviderDetails();
  const matches = providers.find((providerMatch) => providerMatch.name === providerName);
  if (!matches) {
    throw Error(`No match for provider: ${providerName}`);
  }
  return matches.metadata;
}

export interface ProviderModelsResult {
  provider: ProviderDetails;
  models: Model[] | null;
  error: string | null;
  warning: string | null;
}

export async function fetchModelsForProviders(
  activeProviders: ProviderDetails[]
): Promise<ProviderModelsResult[]> {
  const modelPromises = activeProviders.map(async (p) => {
    try {
      // For local provider, use listLocalModels and filter to only downloaded models
      if (p.name === 'local') {
        const allModels = await listLocalModels();
        const downloadedModels = allModels
          .filter((m) => m.status.state === 'Downloaded')
          .map((m) => ({ name: m.id, provider: p.name }) as Model);
        return { provider: p, models: downloadedModels, error: null, warning: null };
      }

      // Prefer the provider's live model list (e.g. OpenAI `/v1/models`). The
      // inventory list is gated by `dynamic_models`, so for custom providers it
      // only returns the models typed at setup; the live list returns what the
      // gateway actually exposes. Fall back to the inventory on any failure.
      try {
        const supportedIds = await acpListProviderSupportedModels(p.name);
        if (supportedIds.length > 0) {
          const models = supportedIds.map((id) => ({ name: id, provider: p.name }) as Model);
          return { provider: p, models, error: null, warning: null };
        }
      } catch (supportedError) {
        console.warn(`Live model list unavailable for ${p.name}:`, getErrorMessage(supportedError));
      }

      const providerModels = await acpListProviderModels(p.name);
      const models = providerModels.map(
        (m) =>
          ({
            name: m.id,
            provider: p.name,
            context_limit: m.contextLimit ?? undefined,
            reasoning: m.reasoning ?? undefined,
          }) as Model
      );
      return { provider: p, models, error: null, warning: null };
    } catch (e: unknown) {
      // For custom providers, fall back to the configured model list
      if (p.provider_type === 'Custom') {
        const fallbackModels = p.metadata.known_models.map(
          (m) =>
            ({
              name: m.name,
              provider: p.name,
              context_limit: m.context_limit,
              reasoning: m.reasoning ?? undefined,
            }) as Model
        );
        if (fallbackModels.length > 0) {
          console.warn(`Failed to fetch models for ${p.name}:`, getErrorMessage(e));
          return {
            provider: p,
            models: fallbackModels,
            error: null,
            warning: `Could not fetch models from provider — showing configured models instead.`,
          };
        }
      }

      const errMsg = getErrorMessage(e);
      const errorMessage = `Failed to fetch models for ${p.name}${errMsg ? `: ${errMsg}` : ''}`;
      return {
        provider: p,
        models: null,
        error: errorMessage,
        warning: null,
      };
    }
  });

  return await Promise.all(modelPromises);
}

// Mirrors ModelConfig::is_reasoning_model (crates/goose-provider-types/src/model.rs)
// and is_openai_responses_model (formats/openai.rs) — the same heuristic the
// backend applies when it builds requests. Needed because the canonical registry
// bundled in the pinned binary predates newer models (e.g. it knows
// claude-opus-4.8 and claude-sonnet-5 but not claude-opus-5), which would
// otherwise hide the thinking controls for a model the backend does treat as
// reasoning-capable.
const OPENAI_RESPONSES_MODEL = /(?:^|[-/])(?:o\d+(?:$|-)|gpt-5(?:$|[-.]))/i;

function looksLikeReasoningModel(model: string): boolean {
  const name = model.toLowerCase();
  return (
    OPENAI_RESPONSES_MODEL.test(model) ||
    name.includes('claude') ||
    name.startsWith('gemini-3') ||
    name.includes('/gemini-3') ||
    name.includes('-gemini-3')
  );
}

export async function fetchModelReasoning(
  provider: string,
  model: string,
  fallback?: boolean
): Promise<boolean | null> {
  try {
    const models = await acpListProviderModels(provider);
    const match = models.find((m) => m.id === model);
    if (match?.reasoning != null) {
      return match.reasoning;
    }
  } catch {
    // Fall through to the canonical lookup below.
  }

  if (fallback != null) {
    return fallback;
  }

  // Models offered by a provider's live list are absent from the inventory, so
  // they carry no reasoning metadata. The canonical registry resolves it from
  // the model name (gemini-*, claude*, gpt-*), which is what the models served
  // by a custom gateway need for the thinking controls to appear. Models the
  // registry does not know fall back to the shared name heuristic below.
  const canonical = await fetchCanonicalModelInfo(provider, model);
  if (canonical) {
    return canonical.reasoning;
  }

  return looksLikeReasoningModel(model) ? true : null;
}
