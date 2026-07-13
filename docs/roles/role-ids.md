# Royco AccessManager role IDs (by system)

`roleId = uint64(uint256(keccak256(abi.encode("<tag>"))))` — `ADMIN_ROLE = 0`, `PUBLIC_ROLE = 2^64-1`. Generated from `app/metadata/role-names.json`; grouped per `src/registry/Roles.sol`.

## Built-ins (OZ AccessManager)

| Role | Numeric ID (uint64) | Hex |
|---|---|---|
| `ADMIN_ROLE` | 0 | `0x0000000000000000` |
| `PUBLIC_ROLE` (open — every address) | 18446744073709551615 | `0xffffffffffffffff` |

## Royco Dawn — markets, entry point, syncer
_src/registry/Roles.sol · `ROYCO_*`_

| Role | Numeric ID (uint64) | Hex |
|---|---|---|
| `ADMIN_PAUSER_ROLE` | 7925626764789623619 | `0x6dfd7b8d019d2b43` |
| `ADMIN_UNPAUSER_ROLE` | 10054419464311379566 | `0x8b88793b710d966e` |
| `ADMIN_UPGRADER_ROLE` | 17817129721670429102 | `0xf7432915293869ae` |
| `ST_LP_ROLE` | 9623252227852051139 | `0x858ca8ea411ba2c3` |
| `JT_LP_ROLE` | 16055754263579004741 | `0xded17f6f89970f45` |
| `BURNER_ROLE` | 18208673593576913896 | `0xfcb23428e02ffbe8` |
| `LP_ROLE_ADMIN_ROLE` | 12118832287418532003 | `0xa82ebdc1d01dc0a3` |
| `SYNC_ROLE` | 15053450870919821405 | `0xd0e899cf7cf8785d` |
| `ADMIN_KERNEL_ROLE` | 6805807443307967810 | `0x5e7315cf9c14b542` |
| `ADMIN_ACCOUNTANT_ROLE` | 1194442435508212435 | `0x10938311111e92d3` |
| `ADMIN_PROTOCOL_FEE_SETTER_ROLE` | 14297485179608767180 | `0xc66adf04fffe1acc` |
| `ADMIN_ORACLE_QUOTER_ROLE` | 5790196268886763633 | `0x505ae8d42ac9a871` |
| `ADMIN_ENTRY_POINT_ROLE` | 18089890734229314815 | `0xfb0c33c7475e5cff` |
| `ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE` | 3947436291410369121 | `0x36c81c6483001a61` |
| `DEPLOYER_ROLE` | 6507856881284443453 | `0x5a508d5a7a0a6d3d` |
| `DEPLOYER_ROLE_ADMIN_ROLE` | 11875770835546705225 | `0xa4cf36a786b48d49` |
| `GUARDIAN_ROLE` | 3153718263372025530 | `0x2bc4420d29f38eba` |
| `TRANSFER_AGENT_ROLE` (Securitize) | 6300902259487099312 | `0x57714d38ad2f49b0` |

## Concrete vaults (native roles mirrored into the AM)
_srRoyUSDC / roywstETH_

| Role | Numeric ID (uint64) | Hex |
|---|---|---|
| `VAULT_MANAGER` | 15875865955164154843 | `0xdc5267f8e746ebdb` |
| `STRATEGY_MANAGER` | 4487222393053400099 | `0x3e45d0fdfe204c23` |
| `HOOK_MANAGER` | 14177249393595990130 | `0xc4bfb5358d694072` |

## Makina strategy adapter (per concrete-vault strategy)

| Role | Numeric ID (uint64) | Hex |
|---|---|---|
| `STRATEGY_PAUSER` | 11452681425251394499 | `0x9ef01913cdd2e3c3` |
| `STRATEGY_UNPAUSER` | 5615552891458788855 | `0x4dee739a30d19df7` |
| `STRATEGY_RESCUE` | 5085675420049522850 | `0x4693f2d976fcc0a2` |
| `STRATEGY_ALLOCATOR` ⚠️ not AM-wired — strategy `allocateFunds`/`deallocateFunds` are `onlyRoycoVault`; allocation is the vault's native `ALLOCATOR` (DIAL). | 15277387785437310784 | `0xd4042f3f6ee1ef40` |

## Makina / Caliber (per vault)

| Role | Numeric ID (uint64) | Hex |
|---|---|---|
| `SRROYUSDC_RISK_MANAGER` | 6359708774850158159 | `0x5842396f7fe0de4f` |
| `SRROYUSDC_TIMELOCK_MANAGER` | 11474785291283288494 | `0x9f3ea06d28d151ae` |
| `ROYWSTETH_RISK_MANAGER` | 12159166457409087352 | `0xa8be097892b6a778` |
| `ROYWSTETH_TIMELOCK_MANAGER` | 14149459376679876623 | `0xc45cfa5606d2f80f` |
