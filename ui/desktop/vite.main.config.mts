import { defineConfig } from 'vite';

// Corporate bundle: bake provider defaults into the build only when set at
// build time, so unset keys keep resolving process.env at runtime.
const CORPORATE_BUNDLE_KEYS = [
  'GOOSE_DEFAULT_PROVIDER',
  'GOOSE_DEFAULT_MODEL',
  'GOOSE_DEFAULT_PROVIDER_HOST',
  'GOOSE_CUSTOM_PROVIDER',
  'GOOSE_PREDEFINED_MODELS',
  'GOOSE_LOCK_BACKEND',
  'GOOSE_LOCK_PROVIDER',
  'SECURITY_PROMPT_ENABLED_OVERRIDE',
  'SECURITY_COMMAND_CLASSIFIER_ENABLED_OVERRIDE',
  'GOOSE_VERSION',
  'GOOSE_DISABLE_AUTO_DOWNLOAD',
  'GOOSE_TELEMETRY_ENABLED',
  'GOOSE_ALLOWLIST_WARNING',
];

const corporateBundleDefines = Object.fromEntries(
  CORPORATE_BUNDLE_KEYS.filter((key) => process.env[key]).map((key) => [
    `process.env.${key}`,
    JSON.stringify(process.env[key]),
  ])
);

// https://vitejs.dev/config
export default defineConfig({
  define: {
    'process.env.GITHUB_OWNER': JSON.stringify(process.env.GITHUB_OWNER || 'aaif-goose'),
    'process.env.GITHUB_REPO': JSON.stringify(process.env.GITHUB_REPO || 'goose'),
    'process.env.GOOSE_BUNDLE_NAME': JSON.stringify(process.env.GOOSE_BUNDLE_NAME || 'Goose'),
    ...corporateBundleDefines,
  },
});
