/**
 * Centralised Rarime / FreedomTool configuration for both Rarimo Mainnet
 * (chainId 7368, the "production" L2 — https://l2.rarimo.com) and Q-Testnet
 * (chainId 7369, https://rpc.qtestnet.org).
 *
 * Why two networks live side-by-side:
 * - Mainnet is where the rarime-app's own French-passport identity
 *   registration succeeded — the on-chain `registerViaNoir(...)` path on
 *   Registration2 `0x11BB4B14AA…`. CSCA chain for HSM_DS_1 is already
 *   permanently in `CertificatesSMT` `0xA8b350d6…` (block 2329) so any
 *   French passport using HSM_DS_1 can register here.
 * - Q-Testnet still hosts the legacy `RegistrationSimple` light-registrator
 *   flow that the @rarimo/rarime-rn-sdk implements. TD3 passports return 400
 *   from the light-registrator endpoint there (Noir-base64 vs Groth16-JSON
 *   schema mismatch) — see HANDOFF-FRENCH-PASSPORT.md. Kept as a fallback /
 *   playground for the light path while the heavy Noir circuit lands.
 *
 * The active network is chosen via NetworkContext (persisted to
 * AsyncStorage); the home screen, voting flow and Step 7 all read through
 * `getRarimeConfig(network)` / `getFreedomToolConfig(network)` so a switch
 * in Settings propagates without prop drilling.
 */

import i18n from 'i18next';

import mainnet from './mainnet.json';
import testnet from './testnet.json';

export type Network = 'testnet' | 'mainnet';

/** Default for fresh installs. Switched to Mainnet on 2026-05-22 once the
 * CNIe registration + voting paths were verified end-to-end. Settings → Dev
 * tools still lets the user flip to Testnet for debugging. */
export const DEFAULT_NETWORK: Network = 'mainnet';

// Q-Testnet (chainId 7369, light-registrator flow — currently broken for TD3)
export const RARIME_TESTNET_CONFIG = testnet.rarime;
export const FREEDOM_TOOL_TESTNET_CONFIG = testnet.freedomTool;

// Rarimo Mainnet (chainId 7368) — the working Noir / registerViaNoir flow.
export const RARIME_MAINNET_CONFIG = mainnet.rarime;
export const FREEDOM_TOOL_MAINNET_CONFIG = mainnet.freedomTool;

// Mainnet-only constants used by the registerViaNoir path (utils/register-via-noir.ts).
// On testnet we don't have a working heavy-path equivalent yet — the helper
// throws on testnet rather than silently switching.
export const MAINNET_REGISTRATION_CONTRACT_ADDRESS = mainnet.registrationContractAddress; // Registration2
export const MAINNET_CERT_POSEIDON_SMT_ADDRESS = mainnet.certPoseidonSmtAddress; // CertificatesSMT (CSCA tree root)

// ---------------------------------------------------------------------------
// Per-network getters. These are the only things callers should reach for —
// the *_CONFIG constants above are implementation detail.
// ---------------------------------------------------------------------------
export const getRarimeConfig = (network: Network) =>
  network === 'mainnet' ? RARIME_MAINNET_CONFIG : RARIME_TESTNET_CONFIG;

export const getFreedomToolConfig = (network: Network) =>
  network === 'mainnet' ? FREEDOM_TOOL_MAINNET_CONFIG : FREEDOM_TOOL_TESTNET_CONFIG;

/** Block explorer base URL for the active network — used to deep-link a tx
 * hash in the verifier tab and in success screens. */
export const getExplorerTxBaseUrl = (network: Network) =>
  network === 'mainnet' ? mainnet.explorerTxBaseUrl : testnet.explorerTxBaseUrl;

/** Default proposal to load on the home screen when no specific one is
 * requested. Mainnet & testnet maintain independent proposal-id spaces; the
 * testnet id `236` was the QA one, mainnet's value comes from the FreedomTool
 * deployment. Either side may be overridden by a deep link param. */
export const getDefaultProposalId = (network: Network) =>
  network === 'mainnet' ? mainnet.defaultProposalId : testnet.defaultProposalId;

// Legacy alias for the testnet FreedomTool config (kept until call sites are
// migrated to getFreedomToolConfig(network)).
export const FREEDOM_TOOL_CONFIG = FREEDOM_TOOL_TESTNET_CONFIG;

export const PRIVATE_KEY_STORAGE_KEY = 'rarime_bjj_private_key';

/**
 * Retry wrapper for flaky RPC calls.
 * Retries up to `maxRetries` times with `delayMs` between attempts.
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  { maxRetries = 2, delayMs = 3000, label = 'RPC call', onRetry }: {
    maxRetries?: number;
    delayMs?: number;
    label?: string;
    onRetry?: (attempt: number, maxAttempts: number, error: unknown) => void;
  } = {}
): Promise<T> {
  let lastError: unknown;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastError = err;
      if (attempt < maxRetries) {
        console.warn(
          `[withRetry] ${label} failed (attempt ${attempt + 1}/${maxRetries + 1}), retrying in ${delayMs}ms...`,
          err
        );
        onRetry?.(attempt + 1, maxRetries + 1, err);
        await new Promise((r) => setTimeout(r, delayMs));
      }
    }
  }
  throw lastError;
}

/**
 * Formats an unknown error into a user-facing message.
 */
export function formatRpcError(err: unknown): string {
  if (!(err instanceof Error)) return i18n.t('voting.errors.unexpected');

  const msg = err.message.toLowerCase();
  if (msg.includes('network') || msg.includes('fetch') || msg.includes('timeout'))
    return i18n.t('voting.errors.network');
  if (msg.includes('already registered') || msg.includes('duplicate'))
    return i18n.t('voting.errors.alreadyRegistered');
  if (msg.includes('already voted')) return i18n.t('voting.errors.alreadyVoted');
  if (msg.includes('403') || msg.includes('forbidden')) return i18n.t('voting.errors.forbidden');
  if (msg.includes('revert') || msg.includes('invalid_proof'))
    return i18n.t('voting.errors.verificationFailed');
  return i18n.t('voting.errors.generic');
}
