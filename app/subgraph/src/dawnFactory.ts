import { Address } from "@graphprotocol/graph-ts";
import { MarketDeployed } from "../generated/AccessManager/AccessManager";
import { Market, MarketComponent } from "../generated/schema";

// The Dawn RoycoFactory is BOTH the AccessManager and the market deployer, so this handler hangs
// off the existing AccessManager data source (same address). Every market ever deployed through a
// registered factory auto-populates from this event — no manual registry entries.
// Topic0 verified against the live sNUSD deployment (see src/interfaces/dawn/IDawnFactory.sol).

function saveComponent(marketId: string, componentType: string, address: Address): void {
  const c = new MarketComponent(marketId + "-" + componentType);
  c.market = marketId;
  c.address = address;
  c.componentType = componentType;
  c.save();
}

export function handleMarketDeployed(event: MarketDeployed): void {
  const m = event.params.roycoMarket;
  const p = event.params.params;
  const id = m.kernel.toHexString();

  const market = new Market(id);
  market.kind = "dawn";
  market.factory = event.address;
  market.seniorTranche = m.seniorTranche;
  market.juniorTranche = m.juniorTranche;
  market.kernel = m.kernel;
  market.accountant = m.accountant;
  market.liquidityProviderTranche = Address.zero();
  market.ydm = Address.zero();
  market.lptYdm = Address.zero();
  market.extras = Address.zero();
  market.seniorTrancheName = p.seniorTrancheName;
  market.seniorTrancheSymbol = p.seniorTrancheSymbol;
  market.juniorTrancheName = p.juniorTrancheName;
  market.juniorTrancheSymbol = p.juniorTrancheSymbol;
  market.blockNumber = event.block.number;
  market.timestamp = event.block.timestamp;
  market.txHash = event.transaction.hash;
  market.save();

  saveComponent(id, "kernel", m.kernel);
  saveComponent(id, "accountant", m.accountant);
  saveComponent(id, "seniorTranche", m.seniorTranche);
  saveComponent(id, "juniorTranche", m.juniorTranche);
}
