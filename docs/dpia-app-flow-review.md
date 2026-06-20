# DPIA ⇄ App flow review — passport registration & local checks

**Date:** 2026-06-09
**Source document:** `DPIA_LesGueux_v2_revise.docx` (v1.2, 08 juin 2026, "Pour partage à la CNIL")
**Code reviewed:** `referendum-citoyen-react-native` @ `38cc8c2` (v1.2.1)
**Reviewer:** Claude Code (read-only review against the working tree)

> **Scope note.** The DPIA's own embedded review comments contain this exchange:
> - *[Claude]* « passeport seul, ou CNI électronique également acceptée ? Si passeport uniquement, remplacer « CNI » par « passeport »… »
> - *[author]* « **passeport seul** »
>
> So V1 scope is **passport-only (TD3)**. This analysis is anchored to the TD3 **heavy** registration path. Lingering "CNI"/"TD1" mentions in the document (e.g. line 121, line 34) should be removed — see the forward-looking caveat below.

---

## 1. Finding: passport registration is not captured correctly

The DPIA describes registration **conceptually** (§2.1 "Couche 2") but it is **absent from both the procedural flow (§1.1, Étapes 1-7) and the data-flow inventory (§2.1 table).** For a DPIA, the data-flow omission is the material one.

### What §1.1 says
download → CGU → NFC read → eligibility check → vote expression → **« Étape 6 : génération et transmission du Lot Preuve + Vote »** → blockchain.
It collapses everything into a **single** transmission (the vote).

### What the code actually does — two separate on-chain writes to two separate relayer endpoints

| App step | Action | Network transmission |
|---|---|---|
| Step5 | Camera MRZ scan (OCR) | none |
| Step6 | NFC chip read | none |
| **Step7** | **Registration** — heavy Noir register proof generated on-device, calldata POSTed to `…/registration-relayer/v1/register`; identity written to the on-chain **RegistrationSMT** | **yes — transmission #1** |
| Step9-10 | Vote selection | none |
| Step11 | Vote — Groth16 proof, POSTed to `…/proof-verification-relayer/v3/vote` | **yes — transmission #2** |

- Registration is a **distinct, prior** event. In V1 it happens **once and is reused across votes** (a returning voter hits `Document status: REGISTERED_WITH_THIS_PK` and skips it — confirmed in error logs). The DPIA's own **Risk 4** (liaison inter-scrutins V1) depends on this persistence, yet the flow/table don't show the registration transmission that creates it.
- **What §2.1's table is missing:** a row for *what is POSTed to the registration relayer*. For V1 passport (heavy path) that's the zk-proof + identity commitment + certificates-root calldata — **not** raw identity. Verified in `utils/register-via-noir.ts` (it sends only `{tx_data, destination, no_send}`; the SOD never leaves the device). So the relay's "données anonymisées + logs IP" qualification still holds for V1, but the **registration data flow itself is undocumented.**

### ⚠️ Forward-looking caveat (TD1)
The document still mentions « carte d'identité française (TD1) ». If TD1 is ever enabled, the **"data never leaves the device" guarantee breaks**: TD1 uses Rarimo's **light** registration (`verifySodRequest` → `/registerid`), which transmits the **full SOD + signed attributes + chip signature + document-signer certificate** to the relay. That would change the relay's RGPD qualification from "processor of anonymized data" to "processor of raw identity-document data." Keep the local-only guarantee explicitly scoped to passport/TD3-heavy.

---

## 2. Precise answer: how the passport is checked locally before registration

The DPIA's Étape 4 — *« majeur ? Français ? signature valable ? → refusé sans aucune transmission »* — conflates three things that happen at **different stages, on different data, with different guarantees.**

| Check | Where | On what data | Mechanism | Hard block? |
|---|---|---|---|---|
| **Age ≥ 18** | **Step5** (camera, *before* NFC) | OCR'd MRZ birthdate | `checkBirthDate` → `'underage'` (`utils/mrzDate.ts`, `MIN_VOTING_AGE = 18`) | Yes (prod); **bypassed in dev mode** |
| **Not expired** | Step5 | OCR'd MRZ expiry | `checkExpiryDate` → `'expired'` | Yes (dev-bypassable) |
| **Nationality (French)** | Step5 | OCR'd MRZ nationality | `isCitizenshipAllowed(mrz.nationality, proposal.citizenshipWhitelist)` → `'wrong_country'` | Yes (dev-bypassable) |
| **Document type** | Step5 | MRZ prefix `P<` vs `ID` | regex | Yes |
| **« signature valable » (authenticity / passive auth)** | **Step7 (registration)** | chip SOD | **Proven in-circuit** (heavy Noir circuit proves the SOD's slave-cert chains to a CSCA root; verified on-chain) + on-chain CSCA-presence check (`register-via-noir.ts:399`) | **No local pre-gate** |

### Three precision points the DPIA should reflect

1. **Eligibility checks run on the camera-OCR'd MRZ, not on authenticated chip data, and *before* the NFC read** — the opposite order to the DPIA (NFC at Étape 3, then eligibility at Étape 4). OCR'd MRZ is **not** cryptographically authenticated: a card with a forged printed MRZ could pass Step5 (its forged *chip* would later fail passive-auth at registration). So "majeur ?/Français ?" are **UX eligibility pre-filters, not security controls.**

2. **« signature valable » is not checked locally and is not a refusal-before-transmission gate.** Authenticity is *proven*, not pre-checked — and that proof is generated and transmitted at registration (Step7, post-NFC). The framing "vérifiée localement → refusé sans transmission" is accurate for age/nationality/expiry (Step5 is genuinely offline) but **inaccurate for document authenticity.**

3. **The binding age/nationality enforcement is cryptographic and happens at vote time, in the query circuit** (majority via a birthdate-range constraint, citizenship as a revealed attribute against the on-chain whitelist) — exactly as §2.1 "Couche 3" says. The Step5 checks are a **redundant, spoofable, local convenience layer** on top of that. The real "one person, adult, French" guarantee is the on-chain/circuit layer, not Step5.

---

## 3. Suggested corrections to the DPIA

- **Add registration as an explicit step** in §1.1 (between NFC read and vote) and **a dedicated row in the §2.1 table** for the registration→relayer transmission (recipient: Rarimo registration relayer; content: zk-proof + identity commitment + certificates-root calldata; nature: anonymized; on-chain effect: RegistrationSMT leaf, persistent in V1).
- **Reword Étape 4**: separate the *local, offline, MRZ-based* pre-checks (age/expiry/nationality — refus sans transmission) from *document authenticity*, established cryptographically in-circuit and on-chain at registration. Note the MRZ pre-checks are OCR-based, not authenticated.
- **Scope the « la donnée ne quitte jamais le terminal » guarantee to passport/TD3-heavy explicitly**, and remove/park the TD1/CNI references (or document the SOD-transmission consequence if TD1 is later enabled).
- **Verify before signing (relates to Risk 5 / §3.4 "*à vérifier")**: for the V1 passport path, error reports do **not** contain plaintext DG1/SOD (the heavy path logs only lengths; the SDK's SOD debug-dump is on the unused TD1/light path) — but they **do** contain the full encrypted NFC APDU transcript and some metadata. So "crash reporting excludes NFC data" is true for *plaintext identity on the passport path*, but the logger should be tightened (and the SDK debug patch removed) before any TD1 enablement.

---

## Appendix — key code references

- `components/voting-modal/Step5.tsx` — camera MRZ scan + local `underage`/`expired`/`wrong_country` gating; `allowedCitizenships` from `proposalInfo.criteria.citizenshipWhitelist`.
- `utils/mrzDate.ts` — `MIN_VOTING_AGE = 18`, `checkBirthDate`, `checkExpiryDate`, `ageInYears`, `isExpired`.
- `components/voting-modal/Step7.tsx` — registration: `getDocumentStatus` → route by doc type → register; `[VOTE_INELIGIBLE]` / `RegisteredWithOtherPk` handling. No local age/nationality/signature gate.
- `utils/register-via-noir.ts` — TD3 heavy registration; POSTs `{tx_data, destination, no_send}` only (SOD stays on device); `[CSCA_MISSING]` on-chain CSCA-presence check.
- `node_modules/@rarimo/rarime-rn-sdk/build/Rarime.js::verifySodRequest` — TD1/testnet **light** path that transmits the full SOD (out of V1 scope; relevant only if TD1 is enabled).
- `app/voting-flow.tsx` — step machine; `isPassportFlow`; wires `allowedCitizenships` into Step5.
