import React, { createContext, useContext, useState, useEffect, useMemo, useCallback } from 'react';
import { toastError, toastSuccess } from '../toasts';
import Model, { getProviderMetadata } from './settings/models/modelInterface';
import type { ProviderMetadata } from '../types/providers';
import { acpChatSessionActions, acpChatSessionStore } from '../acp/chatSessionStore';
import {
  acpCreateCustomProviderFromRequest,
  acpListProviderDetails,
  acpReadDefaults,
  acpSaveDefaults,
  acpSetSessionProviderModel,
  acpUpdateCustomProviderFromRequest,
  type AppliedSessionProviderModel,
} from '../acp/providers';
import type { UpdateCustomProviderRequest } from '../types/providers';
import { errorMessage } from '../utils/conversionUtils';
import {
  getModelDisplayName,
  getProviderDisplayName,
} from './settings/models/predefinedModelsUtils';
import { defineMessages, useIntl } from '../i18n';

const i18n = defineMessages({
  unknownProviderTitle: {
    id: 'modelAndProviderContext.unknownProviderTitle',
    defaultMessage: 'Provider name lookup',
  },
  unknownProviderMsg: {
    id: 'modelAndProviderContext.unknownProviderMsg',
    defaultMessage: 'Unknown provider in config -- please inspect your config.yaml',
  },
  modelChangedTitle: {
    id: 'modelAndProviderContext.modelChangedTitle',
    defaultMessage: 'Model changed',
  },
  switchModelSuccess: {
    id: 'modelAndProviderContext.switchModelSuccess',
    defaultMessage: 'Successfully switched models -- using {model} from {provider}',
  },
  modelChangeFailed: {
    id: 'modelAndProviderContext.modelChangeFailed',
    defaultMessage: '{provider}/{model} failed',
  },
  selectModel: {
    id: 'modelAndProviderContext.selectModel',
    defaultMessage: 'Select Model',
  },
});

interface ModelAndProviderContextType {
  currentModel: string | null;
  currentProvider: string | null;
  changeModel: (sessionId: string | null, model: Model) => Promise<boolean>;
  getCurrentModelAndProvider: () => Promise<{ model: string; provider: string }>;
  getFallbackModelAndProvider: () => Promise<{ model: string; provider: string }>;
  getCurrentModelAndProviderForDisplay: () => Promise<{ model: string; provider: string }>;
  getCurrentModelDisplayName: () => Promise<string>;
  getCurrentProviderDisplayName: () => Promise<string>; // Gets provider display name from subtext
  refreshCurrentModelAndProvider: () => Promise<void>;
}

interface ModelAndProviderProviderProps {
  children: React.ReactNode;
}

const ModelAndProviderContext = createContext<ModelAndProviderContextType | undefined>(undefined);

export { i18n as modelAndProviderMessages };

type BundledCustomProviderSpec = {
  display_name: string;
  api_url: string;
  models: string[];
  engine?: string;
  base_path?: string;
  headers?: Record<string, string>;
};

// Single-flight guard: on startup several components resolve the fallback in
// parallel, and without it the bundled provider gets created more than once.
let bundledCustomProviderSetup: Promise<{ model: string; provider: string }> | null = null;

function getBundledCustomProvider(): Promise<{ model: string; provider: string }> | null {
  const raw = window.appConfig.get('GOOSE_CUSTOM_PROVIDER') as string | undefined;
  if (!raw) {
    return null;
  }
  if (!bundledCustomProviderSetup) {
    bundledCustomProviderSetup = setupBundledCustomProvider(raw).catch((error) => {
      bundledCustomProviderSetup = null;
      throw error;
    });
  }
  return bundledCustomProviderSetup;
}

async function setupBundledCustomProvider(
  raw: string
): Promise<{ model: string; provider: string }> {
  const spec = JSON.parse(raw) as BundledCustomProviderSpec;
  const request: UpdateCustomProviderRequest = {
    api_key: '',
    api_url: spec.api_url,
    base_path: spec.base_path ?? null,
    display_name: spec.display_name,
    engine: spec.engine ?? 'openai',
    headers: spec.headers ?? null,
    models: spec.models,
    requires_auth: false,
  };

  const providers = await acpListProviderDetails();
  let providerId = providers.find((p) => p.metadata.display_name === spec.display_name)?.name;
  if (!providerId) {
    providerId = (await acpCreateCustomProviderFromRequest(request)).provider_name;
    try {
      // Bind the installer-provisioned Keychain secret (CUSTOM_<ID>_API_KEY):
      // an update with requires_auth and no api_key reuses the stored secret.
      await acpUpdateCustomProviderFromRequest(providerId, { ...request, requires_auth: true });
    } catch {
      // No secret provisioned for this provider — leave it without client auth.
    }
  }

  const model = (window.appConfig.get('GOOSE_DEFAULT_MODEL') as string) || spec.models[0];
  await acpSaveDefaults(providerId, model);
  return { model, provider: providerId };
}

function patchAcpSessionProviderModel(
  sessionId: string,
  { providerId, modelId }: AppliedSessionProviderModel
) {
  if (!providerId && !modelId) return;

  const currentSession = acpChatSessionStore.getSnapshot(sessionId)?.session;
  if (!currentSession) return;

  acpChatSessionActions.setSessionMetadata(sessionId, {
    ...currentSession,
    provider_name: providerId ?? currentSession.provider_name,
    model_config: modelId
      ? {
          ...(currentSession.model_config ?? { toolshim: false }),
          model_name: modelId,
        }
      : currentSession.model_config,
  });
}

export const ModelAndProviderProvider: React.FC<ModelAndProviderProviderProps> = ({ children }) => {
  const [currentModel, setCurrentModel] = useState<string | null>(null);
  const [currentProvider, setCurrentProvider] = useState<string | null>(null);
  const intl = useIntl();

  const changeModel = useCallback(
    async (sessionId: string | null, model: Model) => {
      const modelName = model.name;
      const providerName = model.provider;
      let phase = 'agent';

      try {
        if (sessionId) {
          const applied = await acpSetSessionProviderModel(
            sessionId,
            providerName,
            modelName,
            model.request_params?.thinking_effort ?? null
          );
          patchAcpSessionProviderModel(sessionId, applied);
        }

        // Only update the global config default when there's no session
        // (i.e. changing from settings, not from within an existing chat)
        if (!sessionId) {
          phase = 'config';
          await acpSaveDefaults(providerName, modelName);
        }

        if (!sessionId) {
          setCurrentProvider(providerName);
          setCurrentModel(modelName);
        }

        toastSuccess({
          title: intl.formatMessage(i18n.modelChangedTitle),
          msg: intl.formatMessage(i18n.switchModelSuccess, {
            model: model.alias ?? modelName,
            provider: model.subtext ?? providerName,
          }),
        });
        return true;
      } catch (error) {
        console.error(`Failed to change model at ${phase} step -- ${modelName} ${providerName}`);
        toastError({
          title: intl.formatMessage(i18n.modelChangeFailed, {
            provider: providerName,
            model: modelName,
          }),
          msg: `${error}`,
          traceback: errorMessage(error),
        });
        return false;
      }
    },
    [intl]
  );

  const getFallbackModelAndProvider = useCallback(async () => {
    const customProviderSetup = getBundledCustomProvider();
    if (customProviderSetup) {
      try {
        return await customProviderSetup;
      } catch (error) {
        console.error(
          '[getFallbackModelAndProvider] Failed to set up bundled custom provider',
          error
        );
      }
    }
    const provider = window.appConfig.get('GOOSE_DEFAULT_PROVIDER') as string;
    const model = window.appConfig.get('GOOSE_DEFAULT_MODEL') as string;
    if (provider && model) {
      try {
        await acpSaveDefaults(provider, model);
      } catch (error) {
        console.error('[getFallbackModelAndProvider] Failed to write to config', error);
      }
    }
    return { model: model, provider: provider };
  }, []);

  const getCurrentModelAndProvider = useCallback(async () => {
    let model: string | null;
    let provider: string | null;

    try {
      const defaults = await acpReadDefaults();
      model = defaults.modelId;
      provider = defaults.providerId;
    } catch {
      console.error(`Failed to read default model or provider`);
      throw new Error('Failed to read default model or provider');
    }
    if (!model || !provider) {
      return getFallbackModelAndProvider();
    }
    return { model: model, provider: provider };
  }, [getFallbackModelAndProvider]);

  const getCurrentModelAndProviderForDisplay = useCallback(async () => {
    const modelProvider = await getCurrentModelAndProvider();
    const gooseModel = modelProvider.model;
    const gooseProvider = modelProvider.provider;

    // lookup display name
    let metadata: ProviderMetadata;

    try {
      metadata = await getProviderMetadata(String(gooseProvider));
    } catch {
      return { model: gooseModel, provider: gooseProvider };
    }
    const providerDisplayName = metadata.display_name;

    return { model: gooseModel, provider: providerDisplayName };
  }, [getCurrentModelAndProvider]);

  const getCurrentModelDisplayName = useCallback(async () => {
    try {
      const { modelId } = await acpReadDefaults();
      return getModelDisplayName(modelId ?? '');
    } catch {
      return intl.formatMessage(i18n.selectModel);
    }
  }, [intl]);

  const getCurrentProviderDisplayName = useCallback(async () => {
    try {
      const { modelId } = await acpReadDefaults();
      const providerDisplayName = getProviderDisplayName(modelId ?? '');
      if (providerDisplayName) {
        return providerDisplayName;
      }
      // Fall back to regular provider display name lookup
      const { provider } = await getCurrentModelAndProviderForDisplay();
      return provider;
    } catch {
      return '';
    }
  }, [getCurrentModelAndProviderForDisplay]);

  const refreshCurrentModelAndProvider = useCallback(async () => {
    try {
      const { model, provider } = await getCurrentModelAndProvider();
      setCurrentModel(model);
      setCurrentProvider(provider);
    } catch (_error) {
      console.error('Failed to refresh current model and provider:', _error);
    }
  }, [getCurrentModelAndProvider]);

  // Load initial model and provider on mount
  useEffect(() => {
    refreshCurrentModelAndProvider();
  }, [refreshCurrentModelAndProvider]);

  const contextValue = useMemo(
    () => ({
      currentModel,
      currentProvider,
      changeModel,
      getCurrentModelAndProvider,
      getFallbackModelAndProvider,
      getCurrentModelAndProviderForDisplay,
      getCurrentModelDisplayName,
      getCurrentProviderDisplayName,
      refreshCurrentModelAndProvider,
    }),
    [
      currentModel,
      currentProvider,
      changeModel,
      getCurrentModelAndProvider,
      getFallbackModelAndProvider,
      getCurrentModelAndProviderForDisplay,
      getCurrentModelDisplayName,
      getCurrentProviderDisplayName,
      refreshCurrentModelAndProvider,
    ]
  );

  return (
    <ModelAndProviderContext.Provider value={contextValue}>
      {children}
    </ModelAndProviderContext.Provider>
  );
};

export const useModelAndProvider = () => {
  const context = useContext(ModelAndProviderContext);
  if (context === undefined) {
    throw new Error('useModelAndProvider must be used within a ModelAndProviderProvider');
  }
  return context;
};
