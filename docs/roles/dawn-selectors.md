# Royco Dawn — function selectors → roles

Every `restricted` (AccessManager-gated) selector on the Dawn surface and the role that gates it. Selectors are from the compiled interfaces (`forge inspect … methodIdentifiers`); roles per `docs/roles/auth.md`, spot-verified on-chain. Not `restricted`: intra-protocol trust gates (`onlyKernel`/`onlyTranche`/`onlyRoycoKernel`) are excluded. `deposit` is `PUBLIC_ROLE` (open); redemption is gated at the tranche layer.

## Kernel

_per market. `setConversionRate` / `setChainlinkOracle` / `setSequencerUptimeFeed` exist only on the matching quoter variant of the deployed kernel._

| Function | Selector | Gating role |
|---|---|---|
| `syncTrancheAccounting()` | `0x9c8e2dc0` | `SYNC_ROLE` |
| `setProtocolFeeRecipient(address)` | `0xe521cb92` | `ADMIN_KERNEL_ROLE` |
| `setSeniorTrancheSelfLiquidationBonus(uint64)` | `0xd2655bbd` | `ADMIN_KERNEL_ROLE` |
| `setBlacklistStatus(bool)` | `0x1e433c0d` | `TRANSFER_AGENT_ROLE` |
| `blacklistAccounts(address[])` | `0x45a0b891` | `TRANSFER_AGENT_ROLE` |
| `unblacklistAccounts(address[])` | `0x6d9311aa` | `TRANSFER_AGENT_ROLE` |
| `pause()` | `0x8456cb59` | `ADMIN_PAUSER_ROLE` |
| `unpause()` | `0x3f4ba83a` | `ADMIN_UNPAUSER_ROLE` |
| `upgradeToAndCall(address,bytes)` | `0x4f1ef286` | `ADMIN_UPGRADER_ROLE` |

### Kernel — oracle/quoter admin (variant-dependent)

_Present only on the matching quoter mix-in of the deployed kernel: admin-oracle variants expose `setConversionRate`; chainlink variants expose `setChainlinkOracle` / `setSequencerUptimeFeed`._

| Function | Selector | Gating role |
|---|---|---|
| `setConversionRate(uint256,bool)` | `0xd97da03e` | `ADMIN_ORACLE_QUOTER_ROLE` |
| `setChainlinkOracle(address,uint48,bool)` | `0xca5dac77` | `ADMIN_ORACLE_QUOTER_ROLE` |
| `setSequencerUptimeFeed(address,uint48)` | `0x6215c6ca` | `ADMIN_ORACLE_QUOTER_ROLE` |

## Accountant

_per market._

| Function | Selector | Gating role |
|---|---|---|
| `setYDM(address,bytes)` | `0x16ffd4a3` | `ADMIN_ACCOUNTANT_ROLE` |
| `setCoverage(uint64)` | `0x4804f610` | `ADMIN_ACCOUNTANT_ROLE` |
| `setBeta(uint96)` | `0x6780b8d9` | `ADMIN_ACCOUNTANT_ROLE` |
| `setLiquidationUtilization(uint256)` | `0x31fe4bc0` | `ADMIN_ACCOUNTANT_ROLE` |
| `setCoverageConfiguration(uint64,uint96,uint256)` | `0x30f32184` | `ADMIN_ACCOUNTANT_ROLE` |
| `setFixedTermDuration(uint24)` | `0x24134973` | `ADMIN_ACCOUNTANT_ROLE` |
| `setSeniorTrancheDustTolerance(uint256)` | `0xf92f8419` | `ADMIN_ACCOUNTANT_ROLE` |
| `setJuniorTrancheDustTolerance(uint256)` | `0x3d3ba86c` | `ADMIN_ACCOUNTANT_ROLE` |
| `setSeniorTrancheProtocolFee(uint64)` | `0x6b013cae` | `ADMIN_PROTOCOL_FEE_SETTER_ROLE` |
| `setJuniorTrancheProtocolFee(uint64)` | `0xf9948b81` | `ADMIN_PROTOCOL_FEE_SETTER_ROLE` |
| `setYieldShareProtocolFee(uint64)` | `0xb2826e1b` | `ADMIN_PROTOCOL_FEE_SETTER_ROLE` |
| `pause()` | `0x8456cb59` | `ADMIN_PAUSER_ROLE` |
| `unpause()` | `0x3f4ba83a` | `ADMIN_UNPAUSER_ROLE` |
| `upgradeToAndCall(address,bytes)` | `0x4f1ef286` | `ADMIN_UPGRADER_ROLE` |

## Senior tranche

_per market. `redeem` → `ST_LP_ROLE`._

| Function | Selector | Gating role |
|---|---|---|
| `deposit(uint256,address)` | `0x6e553f65` | `PUBLIC_ROLE` |
| `redeem(uint256,address,address)` | `0xba087652` | `ST_LP_ROLE` |
| `seizeShares(address,address,uint256)` | `0xf0c73295` | `TRANSFER_AGENT_ROLE` |
| `seizeAndRedeemShares(address,address,uint256)` | `0xa68b1565` | `TRANSFER_AGENT_ROLE` |
| `burn(uint256)` | `0x42966c68` | `BURNER_ROLE` |
| `burnFrom(address,uint256)` | `0x79cc6790` | `BURNER_ROLE` |
| `pause()` | `0x8456cb59` | `ADMIN_PAUSER_ROLE` |
| `unpause()` | `0x3f4ba83a` | `ADMIN_UNPAUSER_ROLE` |
| `upgradeToAndCall(address,bytes)` | `0x4f1ef286` | `ADMIN_UPGRADER_ROLE` |

## Junior tranche

_per market. `redeem` → `JT_LP_ROLE`._

| Function | Selector | Gating role |
|---|---|---|
| `deposit(uint256,address)` | `0x6e553f65` | `PUBLIC_ROLE` |
| `redeem(uint256,address,address)` | `0xba087652` | `JT_LP_ROLE` |
| `seizeShares(address,address,uint256)` | `0xf0c73295` | `TRANSFER_AGENT_ROLE` |
| `seizeAndRedeemShares(address,address,uint256)` | `0xa68b1565` | `TRANSFER_AGENT_ROLE` |
| `burn(uint256)` | `0x42966c68` | `BURNER_ROLE` |
| `burnFrom(address,uint256)` | `0x79cc6790` | `BURNER_ROLE` |
| `pause()` | `0x8456cb59` | `ADMIN_PAUSER_ROLE` |
| `unpause()` | `0x3f4ba83a` | `ADMIN_UNPAUSER_ROLE` |
| `upgradeToAndCall(address,bytes)` | `0x4f1ef286` | `ADMIN_UPGRADER_ROLE` |

## Entry point

_singleton per chain. LP flow is `PUBLIC_ROLE`; the real gate is the tranche layer._

| Function | Selector | Gating role |
|---|---|---|
| `requestDeposit(address,uint256,address,uint64)` | `0xc790b56a` | `PUBLIC_ROLE` |
| `executeDeposit(address,uint256,uint256)` | `0x79ae4439` | `PUBLIC_ROLE` |
| `executeDeposits(address[],uint256[],uint256[])` | `0x98700d25` | `PUBLIC_ROLE` |
| `cancelDepositRequest(uint256,address)` | `0xb9cf0634` | `PUBLIC_ROLE` |
| `cancelDepositRequests(uint256[],address)` | `0x18cbda4a` | `PUBLIC_ROLE` |
| `requestRedemption(address,uint256,address,uint64)` | `0x11c31771` | `PUBLIC_ROLE` |
| `executeRedemption(address,uint256,uint256)` | `0x809ebe06` | `PUBLIC_ROLE` |
| `executeRedemptions(address[],uint256[],uint256[])` | `0x5bee4187` | `PUBLIC_ROLE` |
| `cancelRedemptionRequest(uint256,address)` | `0x74a630ce` | `PUBLIC_ROLE` |
| `cancelRedemptionRequests(uint256[],address)` | `0x4295a78f` | `PUBLIC_ROLE` |
| `modifyTrancheConfigs(address[],(bool,uint8,uint24,uint24)[])` | `0xbed8fdb5` | `ADMIN_ENTRY_POINT_ROLE` |
| `collectProtocolFees(address[],uint256[],address)` | `0x5004ae8b` | `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE` |
| `pause()` | `0x8456cb59` | `ADMIN_PAUSER_ROLE` |
| `unpause()` | `0x3f4ba83a` | `ADMIN_UNPAUSER_ROLE` |
| `upgradeToAndCall(address,bytes)` | `0x4f1ef286` | `ADMIN_UPGRADER_ROLE` |

## Syncer

_singleton per chain (Mainnet / Avalanche / Arbitrum; none on Base yet)._

| Function | Selector | Gating role |
|---|---|---|
| `executeBatchAccountingSync(bool)` | `0x53f43da0` | `SYNC_ROLE` |
| `executeBatchAccountingSyncFor(address[],bool)` | `0x44dcf00e` | `SYNC_ROLE` |
| `addMarketKernels(address[])` | `0x0b3b4e1a` | `SYNC_ROLE` |
| `removeMarketKernels(address[])` | `0x06c6a863` | `SYNC_ROLE` |
| `pause()` | `0x8456cb59` | `ADMIN_PAUSER_ROLE` |
| `unpause()` | `0x3f4ba83a` | `ADMIN_UNPAUSER_ROLE` |
| `upgradeToAndCall(address,bytes)` | `0x4f1ef286` | `ADMIN_UPGRADER_ROLE` |
