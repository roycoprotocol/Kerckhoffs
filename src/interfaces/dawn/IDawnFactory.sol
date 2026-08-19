// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IDawnFactory
 * @notice Thin ABI mirror of royco-dawn `RoycoFactory`'s market-deployment event surface.
 *
 * Mirrors `lib/royco-dawn/src/interfaces/IRoycoFactory.sol` (structs flattened to address).
 * The Dawn RoycoFactory is BOTH the AccessManager and the market deployer, so this event is
 * emitted from the same address the subgraph's AccessManager data source already watches.
 *
 * Topic0 verified against the live sNUSD deployment
 * (mainnet tx 0x03e9a7f506f88927d681a6bd6f70bd1e245ea883814feafc4db71ec182c51f33):
 * 0x4e3cae2d311f5627585594b3772e7b2c20ae37bb293a7937cb5c883bd7744921
 */
interface IDawnFactory {
    struct RoycoMarket {
        address seniorTranche;
        address juniorTranche;
        address kernel;
        address accountant;
    }

    struct RolesTargetConfiguration {
        address target;
        bytes4[] selectors;
        uint64[] roles;
    }

    struct MarketDeploymentParams {
        string seniorTrancheName;
        string seniorTrancheSymbol;
        string juniorTrancheName;
        string juniorTrancheSymbol;
        address seniorTrancheImplementation;
        address juniorTrancheImplementation;
        address kernelImplementation;
        address accountantImplementation;
        bytes seniorTrancheInitializationData;
        bytes juniorTrancheInitializationData;
        bytes kernelInitializationData;
        bytes accountantInitializationData;
        bytes32 seniorTrancheProxyDeploymentSalt;
        bytes32 juniorTrancheProxyDeploymentSalt;
        bytes32 kernelProxyDeploymentSalt;
        bytes32 accountantProxyDeploymentSalt;
        RolesTargetConfiguration[] roles;
    }

    event MarketDeployed(RoycoMarket roycoMarket, MarketDeploymentParams params);
}
