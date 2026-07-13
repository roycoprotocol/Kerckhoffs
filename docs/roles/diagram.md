# Ownership / control structure

Single-page view of every contract Royco controls or depends on, plus who can call what.

## Actors → AM roles

```mermaid
flowchart LR
    FNDN[FNDN multisig<br/>root · rarely transacts]
    WAY[WAY multisig]
    WAYPAUSE[WAY_PAUSE multisig<br/>1-of-4]
    FNDNVETO[FNDN_VETO multisig<br/>1-of-4]
    DIAL[DIAL multisig]
    LPS[LPs<br/>per-address]
    SEC[Securitize]
    MAKINA[Makina governance<br/>off-chain to Royco]

    subgraph AM[RoycoFactory · OpenZeppelin AccessManager]
        ADMIN[ADMIN_ROLE · 72h]
        GUARDIAN[GUARDIAN_ROLE]
        UNPAUSER[ADMIN_UNPAUSER_ROLE]
        EPCLAIM[ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE]
        DEPLOYER[DEPLOYER_ROLE]

        PAUSER[ADMIN_PAUSER_ROLE]
        UPGRADER[ADMIN_UPGRADER_ROLE · 72h]
        LPADMIN[LP_ROLE_ADMIN_ROLE]
        SYNC[SYNC_ROLE]
        ORACLE[ADMIN_ORACLE_QUOTER_ROLE · WAY 72h / FNDN Immediate]
        DEPLOYERADMIN[DEPLOYER_ROLE_ADMIN_ROLE · 72h]
        KERNEL[ADMIN_KERNEL_ROLE · 72h]
        ACCT[ADMIN_ACCOUNTANT_ROLE · 72h]
        FEES[ADMIN_PROTOCOL_FEE_SETTER_ROLE · 72h]
        EP[ADMIN_ENTRY_POINT_ROLE · 24h]
        VM[VAULT_MANAGER · 72h]
        SM[STRATEGY_MANAGER · 72h]
        HM[HOOK_MANAGER · 72h]
        RM["&lt;VAULT&gt;_RISK_MANAGER · 72h"]
        TLM["&lt;VAULT&gt;_TIMELOCK_MANAGER · 72h"]

        SPAUSER[STRATEGY_PAUSER]
        SUNPAUSER[STRATEGY_UNPAUSER]
        SRESCUE[STRATEGY_RESCUE · 72h]
        SALLOC[STRATEGY_ALLOCATOR]

        STLP[ST_LP_ROLE]
        JTLP[JT_LP_ROLE]
        BURNER[BURNER_ROLE]

        TA[TRANSFER_AGENT_ROLE]
    end

    FNDN -->|holds| ADMIN
    FNDN -->|holds| GUARDIAN
    FNDN -->|holds| UNPAUSER
    FNDN -->|holds| EPCLAIM
    FNDN -->|holds| DEPLOYER
    FNDN -->|holds| SUNPAUSER
    FNDN -->|holds| SRESCUE
    FNDN -->|holds Immediate| ORACLE

    FNDNVETO -->|co-holds| GUARDIAN

    WAYPAUSE -->|holds| PAUSER
    WAYPAUSE -->|holds| SPAUSER

    WAY -->|holds| UPGRADER
    WAY -->|holds| LPADMIN
    WAY -->|holds| SYNC
    WAY -->|holds 72h| ORACLE
    WAY -->|holds| DEPLOYERADMIN
    WAY -->|holds| KERNEL
    WAY -->|holds| ACCT
    WAY -->|holds| FEES
    WAY -->|holds| EP
    WAY -->|holds| VM
    WAY -->|holds| SM
    WAY -->|holds| HM
    WAY -->|holds| RM
    WAY -->|holds| TLM

    DIAL -->|holds| SALLOC
    LPS -->|granted by LPADMIN| STLP
    LPS -->|granted by LPADMIN| JTLP
    SEC -->|holds| TA
```

## AM roles → contracts they gate

```mermaid
flowchart LR
    subgraph AM[Royco AM roles]
        PAUSER[ADMIN_PAUSER_ROLE]
        UNPAUSER[ADMIN_UNPAUSER_ROLE]
        UPGRADER[ADMIN_UPGRADER_ROLE]
        KERNELR[ADMIN_KERNEL_ROLE]
        ACCTR[ADMIN_ACCOUNTANT_ROLE]
        FEER[ADMIN_PROTOCOL_FEE_SETTER_ROLE]
        ORACLER[ADMIN_ORACLE_QUOTER_ROLE]
        SYNCR[SYNC_ROLE]
        STLP[ST_LP_ROLE]
        JTLP[JT_LP_ROLE]
        BURNER[BURNER_ROLE]
        TA[TRANSFER_AGENT_ROLE]
        EPR[ADMIN_ENTRY_POINT_ROLE]
        EPCLAIM[ADMIN_ENTRY_POINT_ROLE_CLAIM_FEE]
        VM[VAULT_MANAGER]
        SM[STRATEGY_MANAGER]
        HM[HOOK_MANAGER]
        SPAUSER[STRATEGY_PAUSER]
        SUNPAUSER[STRATEGY_UNPAUSER]
        SRESCUE[STRATEGY_RESCUE]
        SALLOC[STRATEGY_ALLOCATOR]
        RM[VAULT_RISK_MANAGER]
        TLM[VAULT_TIMELOCK_MANAGER]
    end

    subgraph DAWN[Dawn surface · per market on each chain]
        K[Kernel]
        A[Accountant]
        ST[Senior Tranche]
        JT[Junior Tranche]
        SY[Syncer · per chain]
        EP[EntryPoint · CREATE3]
    end

    subgraph VAULTS[Concrete vaults · Mainnet only]
        V[Concrete vault]
        STR[Makina strategy adapter]
        CAL[Caliber]
        MCH[Machine]
    end

    PAUSER --> K & A & ST & JT & SY & EP
    UNPAUSER --> K & A & ST & JT & SY & EP
    UPGRADER --> K & A & ST & JT & SY & EP

    KERNELR --> K
    ACCTR --> A
    FEER --> A
    ORACLER --> K
    SYNCR --> K & SY
    STLP --> ST
    JTLP --> JT
    BURNER --> ST & JT
    TA --> K & ST & JT

    EPR --> EP
    EPCLAIM --> EP

    VM --> V
    SM --> V
    HM --> V

    SPAUSER --> STR
    SUNPAUSER --> STR
    SRESCUE --> STR
    SALLOC --> STR

    RM --> CAL & MCH
    TLM --> CAL
```

## Cross-organization dependencies

```mermaid
flowchart TB
    subgraph MAKINA_GOV[Makina governance · out-of-band]
        MGOV[Makina AM]
    end

    subgraph CALMACH[Per-vault Caliber + Machine]
        RMS["Machine.riskManager slot"]
        RMTS["Machine.riskManagerTimelock slot"]
        IRG["Caliber.instrRootGuardians set"]
    end

    subgraph CONCRETE[Concrete protocol]
        CFAC[ConcreteFactory · Ownable]
        WL[Vault whitelist hook · Ownable]
    end

    subgraph SECURITIZE[Securitize compliance]
        TASRC[Transfer agent service]
    end

    subgraph ROYCO[Royco AM]
        AM[RoycoFactory]
        FNDN_R[FNDN]
        WAY_R[WAY]
    end

    MGOV -->|setRiskManager AM| RMS
    MGOV -->|setRiskManagerTimelock AM| RMTS
    MGOV -->|addInstrRootGuardian FNDN| IRG

    RMS -->|onlyRiskManager calls routed via| AM
    RMTS -->|onlyRiskManagerTimelock calls routed via| AM
    AM -->|gates with VAULT_RISK_MANAGER| WAY_R
    IRG -->|cancelAllowedInstrRootUpdate| FNDN_R

    CFAC -.->|out of scope| AM
    WL -.->|out of scope| AM
    TASRC -.->|TRANSFER_AGENT_ROLE granted| AM
```

## Key

- **Solid arrows** = on-chain authority paths (who can call what).
- **Dashed arrows** = out-of-scope dependencies (Royco depends on but doesn't control).
- Delays are noted on roles in the actor diagram; default is Immediate.
- Per-vault roles (`<VAULT>_RISK_MANAGER`, `<VAULT>_TIMELOCK_MANAGER`) collapse to a single node here for readability — there's actually one of each per concrete vault (`SRROYUSDC_*`, `ROYWSTETH_*`).
