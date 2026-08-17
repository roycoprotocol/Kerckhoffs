import {
  assert,
  describe,
  test,
  afterEach,
  beforeEach,
  clearStore,
  createMockedFunction,
  newMockEvent,
} from "matchstick-as/assembly/index";
import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import { MarketDeploymentCompleted } from "../generated/DayFactory/DayFactory";
import { handleMarketDeploymentCompleted } from "../src/dayFactory";

// NOTE: imports generated Day types — see the note in dayAccessManager.test.ts.

const TEMPLATE = Address.fromString("0xa3207CA8d318784D70E2F6DA14907c67DCf94599");
const DEPLOYER = Address.fromString("0x84d37A25e46029CE161111420E07cEb78880119e");
const SENIOR = Address.fromString("0x1000000000000000000000000000000000000001");
const JUNIOR = Address.fromString("0x1000000000000000000000000000000000000002");
const LPT = Address.fromString("0x1000000000000000000000000000000000000003");
const KERNEL = Address.fromString("0x1000000000000000000000000000000000000004");
const ACCOUNTANT = Address.fromString("0x1000000000000000000000000000000000000005");
const YDM = Address.fromString("0x1000000000000000000000000000000000000006");

function marketDeploymentCompleted(lptYdm: Address): MarketDeploymentCompleted {
  const e = changetype<MarketDeploymentCompleted>(newMockEvent());
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("template", ethereum.Value.fromAddress(TEMPLATE)));
  e.parameters.push(new ethereum.EventParam("deployer", ethereum.Value.fromAddress(DEPLOYER)));

  // DeploymentResult tuple — field order must match IDayFactory.DeploymentResult.
  const tuple = new ethereum.Tuple();
  tuple.push(ethereum.Value.fromAddress(SENIOR));
  tuple.push(ethereum.Value.fromAddress(JUNIOR));
  tuple.push(ethereum.Value.fromAddress(LPT));
  tuple.push(ethereum.Value.fromAddress(KERNEL));
  tuple.push(ethereum.Value.fromAddress(ACCOUNTANT));
  tuple.push(ethereum.Value.fromAddress(YDM));
  tuple.push(ethereum.Value.fromAddress(lptYdm));
  tuple.push(ethereum.Value.fromBytes(Bytes.fromHexString("0x")));
  e.parameters.push(new ethereum.EventParam("result", ethereum.Value.fromTuple(tuple)));
  return e;
}

describe("Day factory mappings", () => {
  beforeEach(() => {
    // The handler try-calls name()/symbol() on the senior tranche to name the market.
    createMockedFunction(SENIOR, "name", "name():(string)").returns([
      ethereum.Value.fromString("Royco Day Senior"),
    ]);
    createMockedFunction(SENIOR, "symbol", "symbol():(string)").returns([ethereum.Value.fromString("rdSR")]);
  });
  afterEach(() => {
    clearStore();
  });

  test("MarketDeploymentCompleted saves Market keyed by kernel + one component per address", () => {
    handleMarketDeploymentCompleted(marketDeploymentCompleted(YDM));

    const id = KERNEL.toHexString();
    assert.fieldEquals("Market", id, "seniorTranche", SENIOR.toHexString());
    assert.fieldEquals("Market", id, "accountant", ACCOUNTANT.toHexString());
    assert.fieldEquals("Market", id, "deployer", DEPLOYER.toHexString());
    assert.fieldEquals("Market", id, "seniorTrancheName", "Royco Day Senior");
    assert.fieldEquals("Market", id, "seniorTrancheSymbol", "rdSR");
    assert.entityCount("Market", 1);

    // 7 component slots, all non-zero here.
    assert.entityCount("MarketComponent", 7);
    assert.fieldEquals("MarketComponent", id + "-kernel", "address", KERNEL.toHexString());
    assert.fieldEquals("MarketComponent", id + "-lptYdm", "address", YDM.toHexString());
  });

  test("zero-address components are skipped", () => {
    handleMarketDeploymentCompleted(marketDeploymentCompleted(Address.zero()));
    // lptYdm is zero -> only 6 component rows.
    assert.entityCount("MarketComponent", 6);
    assert.notInStore("MarketComponent", KERNEL.toHexString() + "-lptYdm");
  });
});
