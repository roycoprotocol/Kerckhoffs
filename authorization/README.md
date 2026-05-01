## Problem

**1. Signer compromise is a realistic threat, and our timelock coverage is incomplete.**

We have to assume core signers can be compromised — social engineering, phishing, device compromise. Delays are the mitigation: a scheduled action gives us a window to notice and cancel. But delays only work if *both* of these are timelocked:
- **The operations themselves** — partially configured today. Some contracts have real on-chain timelocks (Caliber `_allowedInstrRoot`, strategy rescue), others rely on `onlyRiskManagerTimelock`-style role gating where the "delay" only exists if the role-holder happens to be a TimelockController, and vaults have no native delay at all.
- **The timelock configuration itself** — not addressed anywhere. Nothing stops a compromised signer from shortening delays, reassigning roles, or swapping out the timelock controller as a fast operation, which would let them immediately push through whatever they actually wanted. This is the bigger gap.

**2. No monitoring or response plan for scheduled operations.**

Timelocks are useless if no one watches the mempool/chain for scheduled transactions during the delay window. We have no:
- Automated monitoring for scheduled ops on any of our contracts or (eventually) the AccessManager.
- On-call rotation or alert routing for suspicious scheduled actions.
- Documented response playbook: who cancels, with what key, under what criteria, within what SLA.

A 24h delay with nobody watching is indistinguishable from a 0s delay.

**3. No common pattern across contracts** (secondary, but compounding).

Dawn Markets, concrete vaults, strategies, and Makina each handle privileged actions differently. Inconsistency means every new contract reinvents the pattern, and monitoring/response has to be built per-contract instead of once.

We also don't have a documented multisig structure (signers, threshold, scope, rotation) backing any of this.

## Idea

Define a single, system-wide security model covering three surfaces, with a shared delay taxonomy used everywhere.

**Central control plane: RoycoFactory (AccessManager).** Every privileged role across the entire system — Dawn Markets, concrete vaults, strategies, and Makina/Caliber — routes authorization through the existing RoycoFactory, which is already an instance of OpenZeppelin's `AccessManager`. One contract holds every role, assigns every delay, and emits every schedule/cancel/execute event. This gives us:
- A single place to enumerate "who can do what, how fast" across the stack.
- A single place to monitor scheduled operations (one event stream, not N).
- A uniform cancel/veto path (`GUARDIAN_ROLE`) that works the same regardless of which contract the target action lives on.
- One control plane to harden rather than N bespoke role systems.

**Timelock the admin role itself.** `ADMIN_ROLE` (the root role that grants/revokes every other role and reconfigures delays) runs at Root (7d) — strictly slower than every other privileged path. This is what closes problem #1: a compromised FNDN can't shorten delays, reassign roles, or swap out the guardian as a fast operation — any change to the authorization configuration itself is delayed and cancellable by WAY. The only ways to act without a delay are the specific roles that explicitly hold Immediate execution (LP ops, pause, sync, allocator, guardian cancel), and those are narrowly scoped by design.

Exceptions (things that stay on-chain instead of going through AM):
- Caliber `_allowedInstrRoot` on-chain timelock — already has real scheduling with a veto path; no reason to move it.

### Delay levels (applied across all surfaces)

| Level | Duration | When to use |
|---|---|---|
| **Immediate** | 0 | User-facing ops (LP deposit/redeem), pause, guardian cancel, accounting sync, allocator/withdrawal operations — anything where a delay would make the action useless or harm UX. |
| **Standard** | 24h | Operational admins that warrant monitoring but aren't catastrophic — `DEPLOYER_ROLE_ADMIN_ROLE`, `ADMIN_UNPAUSER_ROLE`. |
| **Critical** | 48h | Parameter changes, oracle config, contract upgrades, concrete-vault admins — highest blast radius short of the root admin. |
| **Root** | 7d | `ADMIN_ROLE` itself. Strictly slower than every other privileged path so attacking the meta-timelock is the slowest possible attack. |

Exception: strategy rescue keeps its existing **30d on-chain timelock**. It's an explicit guarantee to depositors that funds can't be extracted quickly and doesn't fit the four tiers above.

### 1. Royco Dawn Markets — roles and delays

Dawn Markets already uses a role model with `ADMIN_ROLE` / `GUARDIAN_ROLE` admin and guardian slots per role. Apply the delay taxonomy:

| Role | Description | Admin Role | Guardian Role | Assignee | Delay |
|---|---|---|---|---|---|
| `ADMIN_ROLE` (0) | Root admin — grants/revokes all roles | `ADMIN_ROLE` (self) | `ADMIN_ROLE` (self) | FNDN | Root (7d) |
| `ADMIN_PAUSER_ROLE` | Pause all protocol contracts | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN, WAY | Immediate |
| `ADMIN_UNPAUSER_ROLE` | Unpause all protocol contracts | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Standard (24h) |
| `ADMIN_UPGRADER_ROLE` | Upgrade protocol contracts (UUPS) | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| `ST_LP_ROLE` | LP ops (deposit/redeem) on senior tranche | `LP_ROLE_ADMIN_ROLE` | `GUARDIAN_ROLE` | Any LP | Immediate |
| `JT_LP_ROLE` | LP ops (deposit/redeem) on junior tranche | `LP_ROLE_ADMIN_ROLE` | `GUARDIAN_ROLE` | Any LP | Immediate |
| `LP_ROLE_ADMIN_ROLE` | Grants/revokes LP roles | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN, WAY | Immediate |
| `SYNC_ROLE` | Triggers accounting sync on kernel | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN, WAY | Immediate |
| `ADMIN_KERNEL_ROLE` | Configure kernel (fee recipient, redemption delay) | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN, WAY | Critical (48h) |
| `ADMIN_ACCOUNTANT_ROLE` | Configure accountant (YDM, coverage, beta, LLTV) | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN, WAY | Critical (48h) |
| `ADMIN_PROTOCOL_FEE_SETTER_ROLE` | Set protocol fee % on ST/JT yields | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN, WAY | Critical (48h) |
| `ADMIN_ORACLE_QUOTER_ROLE` | Oracle/quoter settings (conversion rate, oracle addr) | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| `GUARDIAN_ROLE` | Cancels delayed operations for other roles | `ADMIN_ROLE` | `ADMIN_ROLE` | WAY | Immediate |
| `DEPLOYER_ROLE` | Deploys new Royco markets via factory | `DEPLOYER_ROLE_ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Immediate |
| `DEPLOYER_ROLE_ADMIN_ROLE` | Grants/revokes `DEPLOYER_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Standard (24h) |
| `TRANSFER_AGENT` | (description TBD) | `ADMIN_ROLE` | `ADMIN_ROLE` | Securitize | TBD |

Notes:
- `TRANSFER_AGENT` is held by Securitize and doesn't fit the standard delay tiers — flag for separate treatment.

#### Entry Point — roles and selectors

The Royco Entry Point handles asynchronous deposit/redemption flows on top of the tranches. One per chain (Ethereum / Avalanche / Arbitrum) — same address on every chain via CREATE3: `0x63dA1229be88Fb4D20210147954a1a3e05f2581B`. The migration mirrors the role config originally applied by `lib/royco-dawn/script/independent/DeployEntryPoint.s.sol:128-173`.

**Two new roles** introduced specifically for the entry point:

| Role | Description | Admin Role | Guardian Role | Assignee | Delay |
|---|---|---|---|---|---|
| `ADMIN_ENTRY_POINT_ROLE` | Configure per-tranche params (`modifyTrancheConfigs`) | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE` | Collect accumulated protocol fees (`collectProtocolFees`) | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Immediate |

**Selector → role bindings on the entry point target:**

| Function | Role | Effective Delay | Why |
|---|---|---|---|
| `requestDeposit`, `executeDeposit`, `executeDeposits`, `cancelDepositRequest`, `cancelDepositRequests`, `requestRedemption`, `executeRedemption`, `executeRedemptions`, `cancelRedemptionRequest`, `cancelRedemptionRequests` | `PUBLIC_ROLE` | Immediate | LP ops — open at AM; tranches still gate on `ST_LP_ROLE` / `JT_LP_ROLE` |
| `modifyTrancheConfigs` | `ADMIN_ENTRY_POINT_ROLE` | Critical 48h (FNDN) | Per-tranche entry-point params |
| `collectProtocolFees` | `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE` | Immediate (FNDN) | Fee collection |
| `pause` | `ADMIN_PAUSER_ROLE` | Immediate (FNDN, WAY) | Protocol-wide pause |
| `unpause` | `ADMIN_UNPAUSER_ROLE` | Standard 24h (FNDN) | Protocol-wide unpause — can't rush an unpause to clear an attacker's pause |
| `upgradeToAndCall` | `ADMIN_UPGRADER_ROLE` | Critical 48h (FNDN) | UUPS impl upgrade |

**Self-grants on the entry point contract** (the entry point itself must hold these so it can call into the tranches when relaying user ops):

| Role | Holder | Delay |
|---|---|---|
| `ST_LP_ROLE` | EntryPoint (`0x63dA…81B`) | Immediate |
| `JT_LP_ROLE` | EntryPoint (`0x63dA…81B`) | Immediate |
| `BURNER_ROLE` | EntryPoint (`0x63dA…81B`) | Immediate |

`ST_LP_ROLE` / `JT_LP_ROLE` let the entry point call `deposit` / `redeem` on the senior/junior tranche; `BURNER_ROLE` is required for the yield-forfeiture path on redemption.

### 2. Vaults — roles and access manager

Concrete vaults don't natively support delays on role-gated actions. To get delays without forking the vault contracts, we route role authorization through the existing **RoycoFactory**, which is an instance of OpenZeppelin's `AccessManager`:

1. Enumerate the concrete vault roles (table below).
2. Map each concrete vault role 1:1 to an `AccessManager` role on RoycoFactory.
3. Grant all concrete vault roles to the `AccessManager` (i.e., the vault only recognizes the AM as the holder).
4. In the `AccessManager`, assign each AM role to the appropriate party (FNDN multisig, DIAL, etc.) with its own execution delay.

This gives us per-role delays enforced at the authorization layer, without touching vault code. It also unifies role management across all vaults under a single control plane.

**Concrete Vault roles:**

Each concrete role maps to an AM role with an admin role (who can grant/revoke it) and a guardian role (who can cancel its scheduled operations). All concrete admin roles collapse into a single root `ADMIN_ROLE` — no per-family admin roles. `ADMIN_ROLE` is held by FNDN (Critical); `GUARDIAN_ROLE` is held by WAY (Immediate).

The Ownable owner of `ConcreteFactory` (which gates `updateManagementFeeRecipient` / `updatePerformanceFeeRecipient` and vault-implementation upgrades) is **out of scope** for this migration and remains where it is today.

Only roles that need a non-zero delay are remapped to AM. `ALLOCATOR` / `WITHDRAWAL_MANAGER` are Immediate operations roles held by DIAL — they stay as native AccessControl roles on the vault, untouched by this migration. The whitelist hook contract's ownership is also out of scope; only the vault's `HOOK_MANAGER` role (which gates `setHooks` on the vault) is migrated.

| Concrete Role | Mapped AM Role | Admin Role | Guardian Role | Assignee | Delay |
|---|---|---|---|---|---|
| Vault Manager Admin | `ADMIN_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| Vault Manager | `VAULT_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| Strategy Manager Admin | `ADMIN_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| Strategy Manager | `STRATEGY_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| Hook Manager Admin | `ADMIN_ROLE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| Hook Manager | `HOOK_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |

**Strategy contract roles:**

Strategies are separate contracts that sit under the vaults. They have their own role surface, which also routes through the AccessManager.

| Concrete Role | Permissions | Mapped AM Role | Admin Role | Guardian Role | Assignee | Delay |
|---|---|---|---|---|---|---|
| Pauser | Pause | `STRATEGY_PAUSER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Immediate |
| Unpauser | Unpause | `STRATEGY_UNPAUSER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Standard (24h) |
| Rescue | Rescue stuck funds | `STRATEGY_RESCUE` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | 30d (on-chain; AM delay 0) |
| AllocatorRole | Allocate, deallocate | `STRATEGY_ALLOCATOR` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | DIAL | Immediate |

Notes:
- Pause and unpause are split: pause is Immediate for incident response, unpause is Standard (24h) so an attacker who triggered a pause can't then rush an unpause to clear their own block.
- Rescue is intentionally non-upgradable with a 1-month timelock — the long delay is the guarantee to depositors that funds can't be quietly extracted. The AM role (`STRATEGY_RESCUE`) sits on top with 0 additional delay; the 30d on-chain timelock is what actually gates the action, and `GUARDIAN_ROLE` can still cancel during that window.

**Makina contracts (Caliber) roles:**

Caliber has two different delay mechanisms today; 

- **On-chain timelock for `_allowedInstrRoot`** — stays on-chain as-is. The contract already stores a pending value + expiry and exposes schedule/cancel/execute with a real veto path (Security Council / Root Guardian). No reason to move it.
- **Role-gated immediate setters (`onlyRiskManagerTimelock`)** — move these to the AccessManager. Today the setter is immediate on-chain and the "delay" only exists if the role-holding address happens to be a TimelockController. Routing through AM replaces that ad-hoc pattern with real scheduled execution, uniform cancel/veto, and explicit per-operation delays.

**Stays on-chain (unchanged):**

| Operation | Function | Authority | Delay |
|---|---|---|---|
| Schedule allowed instruction root update | `scheduleAllowedInstrRootUpdate` (Caliber.sol:524) | Risk Manager | Critical (48h) |
| Cancel pending root update | `cancelAllowedInstrRootUpdate` (Caliber.sol:539) | Risk Manager / Security Council / Root Guardian | 0 (veto during delay window) |

**Moves to AccessManager:**

Caliber setters map to two per-vault roles, both at **Critical (48h)**: `<Vault>_RISK_MANAGER` for routine risk parameters and `<Vault>_TIMELOCK_MANAGER` for `setTimelockDuration` only. They share the same delay tier today but stay separate roles — splitting the meta-timelock means it can be reassigned / locked down independently if we ever need to.

| Operation | Function | Mapped AM Role | Admin Role | Guardian Role | Assignee | Delay |
|---|---|---|---|---|---|---|
| Set position stale threshold | `setPositionStaleThreshold` (Caliber.sol:510) | `<Vault>_RISK_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| Set timelock duration | `setTimelockDuration` (Caliber.sol:517) | `<Vault>_TIMELOCK_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| Set max position increase loss bps | `setMaxPositionIncreaseLossBps` (Caliber.sol:557) | `<Vault>_RISK_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| Set max position decrease loss bps | `setMaxPositionDecreaseLossBps` (Caliber.sol:568) | `<Vault>_RISK_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| Set max swap loss bps | `setMaxSwapLossBps` (Caliber.sol:579) | `<Vault>_RISK_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| Set cooldown duration | `setCooldownDuration` (Caliber.sol:586) | `<Vault>_RISK_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| Add base token | `addBaseToken` (Caliber.sol:298) | `<Vault>_RISK_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |
| Remove base token | `removeBaseToken` (Caliber.sol:303) | `<Vault>_RISK_MANAGER` | `ADMIN_ROLE` | `GUARDIAN_ROLE` | FNDN | Critical (48h) |

The corresponding Machine setters (`setCaliberStaleThreshold`, `setMaxFixedFeeAccrualRate`, `setMaxPerfFeeAccrualRate`, `setFeeMintCooldown`, `setMaxSharePriceChangeRate`, `setOutTransferEnabled`, `setMaxBridgeLossBps`) are gated by the same Caliber-side `onlyRiskManagerTimelock` chain and are bound to `<Vault>_RISK_MANAGER` (also Critical 48h).

Notes:
- After migration, the `onlyRiskManagerTimelock` modifier becomes a plain `restricted` (AM) check; the Risk Manager role on the contract is granted to the AccessManager.
- `setTimelockDuration` (the meta-timelock that governs `_allowedInstrRoot`'s on-chain delay) is split into its own role so it can be locked down independently if ever needed; both roles run at Critical (48h) today.

### 3. Multisig structure

**FNDN — Royco Foundation multisig (executor)**
- Ultimately holds the privileged roles across Dawn, vaults, strategies, and Makina (via AccessManager).
- Currently **3/4**. Target: **3/5** — add one more signer to reduce single-signer dominance without raising quorum friction.
- Still to define: signer identities, geographic/jurisdictional spread, hardware requirements, rotation/revocation policy, lost-key and compromise procedures.

**WAY multisig (proposer + guardian)**
- Proposes scheduled actions into the AccessManager; FNDN executes after the delay.
- Also holds `GUARDIAN_ROLE` — can cancel any scheduled operation during its delay window (Immediate). A compromised FNDN can be blocked in real time.
- Splitting propose from execute means a compromise on either side alone can't push a change through — proposer can schedule but not execute, executor executes only what was proposed. Combining proposer + guardian in WAY means the party watching every scheduled op is also the one who can cancel it, which is the monitoring/response workflow for problem #2.
- **Migration:** the proposer is currently an EOA. Replace it with the WAY multisig before treating this model as in effect — an EOA proposer is a single-key path that bypasses the whole propose-monitor-cancel design.

### 4. Monitoring and response (Hypernative + human-in-the-loop Slack)

Problem #2 says a delay nobody watches is a 0s delay. We'll use **Hypernative** as the monitoring layer — they already do real-time transaction monitoring, decoded calldata, alert routing, and Slack/PagerDuty integration for exactly this use case. Building an indexer + decoder + Slack bot ourselves is the wrong use of engineering time when a purpose-built vendor exists.

Setup:
- Subscribe Hypernative to the AccessManager's `OperationScheduled` / `OperationExecuted` / `OperationCanceled` events on every chain we deploy on.
- Route every event into a dedicated `#royco-scheduled-ops` Slack channel with decoded selector + args, current delay, earliest-execution timestamp, explorer link, and a pre-filled Safe cancel link for WAY.
- Configure high-priority policies (PagerDuty) for sensitive selectors: `setTimelockDuration`, `upgradeTo`, any `ADMIN_ROLE` / `GUARDIAN_ROLE` reassignment.
- Also subscribe to upstream protocols our strategies touch (Morpho, Aave, etc.) — Hypernative covers cross-protocol monitoring natively, so we're not blind to external governance changes that affect us.

WAY signers live in the channel and eyeball every scheduled op against what's expected; if anything looks wrong, they hit the pre-filled cancel link and collect signatures within the delay window. Humans make the veto call, Hypernative does the detection and delivery. The 24h Standard delay gives margin over the end-to-end alert → decide → sign → cancel timeline.

Drill requirement: before treating this model as in effect, run one full cold-start drill — WAY cancels a test scheduled op end-to-end under timer. If that can't complete in under 6 hours, the delay tiers need to be longer or the on-call rotation needs restructuring.
