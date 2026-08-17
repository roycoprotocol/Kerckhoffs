import {
  assert,
  describe,
  test,
  afterEach,
  clearStore,
  newMockEvent,
  createMockedFunction,
} from "matchstick-as/assembly/index";
import { Address, BigInt, ethereum } from "@graphprotocol/graph-ts";
import { TargetConfiguredAtGenesis } from "../generated/DayAccessManager/RoycoAccessManager";
import { handleTargetConfiguredAtGenesis } from "../src/dayAccessManager";

// NOTE: this file imports generated Day types, which only exist when subgraph.yaml is rendered
// for a chain that has Royco Day (mainnet / arbitrum / base). `graph test` after an Avalanche
// render will fail to compile — always run tests off a Day-bearing render (CI ends on 8453).

const MANAGER = Address.fromString("0x87aED46566cb28c8375cfcC9971090882A0fB12e");
const AM = MANAGER.toHexString();
const TARGET = Address.fromString("0x0aE0978B868804929fd4C06B3B22D9197B8cd3c6");

function targetConfiguredAtGenesis(target: Address): TargetConfiguredAtGenesis {
  const e = changetype<TargetConfiguredAtGenesis>(newMockEvent());
  e.address = MANAGER;
  e.parameters = new Array<ethereum.EventParam>();
  e.parameters.push(new ethereum.EventParam("target", ethereum.Value.fromAddress(target)));
  return e;
}

describe("Day AccessManager mappings", () => {
  afterEach(() => {
    clearStore();
  });

  test("TargetConfiguredAtGenesis marks the manager-scoped target", () => {
    createMockedFunction(MANAGER, "expiration", "expiration():(uint32)").returns([
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(604800)),
    ]);
    createMockedFunction(MANAGER, "minSetback", "minSetback():(uint32)").returns([
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(0)),
    ]);

    handleTargetConfiguredAtGenesis(targetConfiguredAtGenesis(TARGET));

    const id = AM + "-" + TARGET.toHexString();
    assert.fieldEquals("TargetContract", id, "everConfigured", "true");
    assert.fieldEquals("TargetContract", id, "manager", AM);
    assert.entityCount("TargetContract", 1);
  });
});
