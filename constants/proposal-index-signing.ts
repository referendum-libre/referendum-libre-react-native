/**
 * Pinned Ed25519 public key used to verify the GitHub-Pages-hosted
 * `proposals.json`. The matching private key lives ONLY as the
 * `PROPOSAL_INDEX_SIGNING_KEY` GitHub Actions secret — the publish
 * workflow signs the JSON at deploy time and uploads both
 * `proposals.json` and `proposals.json.sig` to Pages.
 *
 * Setup (one-time): run `node scripts/generate-proposal-signing-key.mjs`,
 * paste the public key into `.env` (EXPO_PUBLIC_PROPOSAL_INDEX_PUBLIC_KEY_HEX),
 * paste the private key into the PROPOSAL_INDEX_SIGNING_KEY repo secret.
 *
 * Trust model: this key gates which proposals appear in the list. It does
 * NOT gate the proposal contents — those still come from the on-chain
 * ProposalsState contract via `getProposalInfo(id)`. An attacker who
 * forged a signature could only insert a proposal ID into the displayed
 * list; the user would then call `getProposalInfo` on it and see whatever
 * the on-chain contract says (real proposal data, real voting target).
 * So a forgery surface is "phishing-like" — show a misleading list —
 * never "rewrite the ballot".
 *
 * Rotation: regenerate the keypair, replace this constant + the GH
 * secret, ship a new app build. Old installs reject the new list and
 * fall back to their cached previous list (or the bundled defaults in
 * utils/proposal-index.ts) until they update.
 */

// Placeholder default, used if EXPO_PUBLIC_PROPOSAL_INDEX_PUBLIC_KEY_HEX is
// unset in `.env`. Replace the env var with the hex output of
// `node scripts/generate-proposal-signing-key.mjs`.
const PLACEHOLDER_PUBLIC_KEY_HEX =
  '23931f71115aacd5a236ab1a28ebb011ec0dfe8e881f7040071c6fa258fc9539'; //nosec: public key

export const PROPOSAL_INDEX_PUBLIC_KEY_HEX =
  process.env.EXPO_PUBLIC_PROPOSAL_INDEX_PUBLIC_KEY_HEX ?? PLACEHOLDER_PUBLIC_KEY_HEX; //nosec: public key

/**
 * When the placeholder is in place, verification is *soft-disabled*: the
 * app accepts unsigned lists (since no real key is pinned) and just logs
 * a warning. The moment a real public key is committed here, verification
 * becomes mandatory and an unsigned/invalid list is rejected outright.
 *
 * This lets the feature land safely on master before the maintainer has
 * generated the keypair — no chicken-and-egg lockout. Once the public
 * key is set, the soft mode auto-disables.
 */
export const PROPOSAL_INDEX_VERIFICATION_REQUIRED =
  PROPOSAL_INDEX_PUBLIC_KEY_HEX !== PLACEHOLDER_PUBLIC_KEY_HEX;
