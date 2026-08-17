import { Address, Bytes } from "@graphprotocol/graph-ts";
import { MarketDeploymentCompleted } from "../generated/DayFactory/DayFactory";
import { ERC20 } from "../generated/DayFactory/ERC20";
import { Market, MarketComponent } from "../generated/schema";

// Royco Day markets are deployed permissionlessly through the Day RoycoFactory; this single event
// carries the full contract set of a new market. Market id = kernel address (unique per
// deployment). Components are keyed "{kernel}-{type}" — never by component address, because the
// YDM singletons are shared across markets and MarketComponent is immutable.

function saveComponent(marketId: string, componentType: string, address: Address): void {
  if (address == Address.zero()) {
    return; // e.g. lptYdm is zero for markets without a liquidity-provider tranche
  }
  const c = new MarketComponent(marketId + "-" + componentType);
  c.market = marketId;
  c.address = address;
  c.componentType = componentType;
  c.save();
}

export function handleMarketDeploymentCompleted(event: MarketDeploymentCompleted): void {
  const r = event.params.result;
  const id = r.kernel.toHexString();

  const market = new Market(id);
  market.kind = "day";
  market.factory = event.address;
  market.template = event.params.template;
  market.deployer = event.params.deployer;
  market.seniorTranche = r.seniorTranche;
  market.juniorTranche = r.juniorTranche;
  market.liquidityProviderTranche = r.liquidityProviderTranche;
  market.kernel = r.kernel;
  market.accountant = r.accountant;
  market.ydm = r.ydm;
  market.lptYdm = r.lptYdm;
  market.extras = r.extras;
  // Day markets are named by their senior tranche; the deployment event carries no names (unlike
  // Dawn's), so read them from the token at deployment time. Try-calls: a reverting token leaves
  // the fields null and the UI falls back to the kernel address.
  if (r.seniorTranche != Address.zero()) {
    const st = ERC20.bind(r.seniorTranche);
    const name = st.try_name();
    if (!name.reverted) {
      market.seniorTrancheName = name.value;
    }
    const symbol = st.try_symbol();
    if (!symbol.reverted) {
      market.seniorTrancheSymbol = symbol.value;
    }
  }
  market.blockNumber = event.block.number;
  market.timestamp = event.block.timestamp;
  market.txHash = event.transaction.hash;
  market.save();

  saveComponent(id, "kernel", r.kernel);
  saveComponent(id, "accountant", r.accountant);
  saveComponent(id, "seniorTranche", r.seniorTranche);
  saveComponent(id, "juniorTranche", r.juniorTranche);
  saveComponent(id, "liquidityProviderTranche", r.liquidityProviderTranche);
  saveComponent(id, "ydm", r.ydm);
  saveComponent(id, "lptYdm", r.lptYdm);
}
