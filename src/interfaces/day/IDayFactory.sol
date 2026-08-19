// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/**
 * @title IDayFactory
 * @notice Thin ABI mirror of royco-day's `RoycoFactory` market-deployment surface.
 *
 * Mirrors `royco-day/src/interfaces/factory/{IRoycoFactory,IRoycoProtocolTemplate}.sol`. Struct
 * field names MUST stay byte-identical to royco-day's `IRoycoProtocolTemplate.DeploymentResult` —
 * graph-cli codegen derives the `event.params.result.<field>` accessors from the ABI tuple
 * component names.
 */
interface IDayFactory {
    struct DeploymentResult {
        address seniorTranche;
        address juniorTranche;
        address liquidityProviderTranche;
        address kernel;
        address accountant;
        address ydm;
        address lptYdm;
        bytes extras;
    }

    event MarketDeploymentCompleted(address indexed template, address indexed deployer, DeploymentResult result);

    function getMarket(address _tranche)
        external
        view
        returns (address seniorTranche, address juniorTranche, address liquidityProviderTranche, address kernel, address accountant);
}
