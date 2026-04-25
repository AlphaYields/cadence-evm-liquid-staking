# EVM stake → Cadence keeper (stake only)

End-to-end **without unstake**: user calls `LSPVault.requestStake` on **Flow EVM**; protocol account runs **`fulfill_evm_stake_bundle.cdc`** on Cadence (COA is vault `owner`).

**Prereqs:** setup complete (`LSPVault` deployed, `update_liquid_staking…` run, bridge onboarded). You need:

| Variable | Meaning |
|----------|---------|
| `RPC` | e.g. `https://testnet.evm.nodes.onflow.org` |
| `LSP_VAULT` | `LSPVault` EVM address (`0x…`) |
| `BRIDGED_STFLOW` | Bridged stFlow ERC‑20 (`ST_FLOW_ADDRESS`) |
| `EVM_USER_PK` | EOA private key that will **stake** (has FLOW on Flow EVM for gas + stake) |
| `NETWORK` / `SIGNER` | Cadence: e.g. `testnet` + `testnet-acc` (protocol / COA account) |

```bash
export RPC=https://testnet.evm.nodes.onflow.org
export NETWORK=testnet
export SIGNER=testnet-acc
export LSP_VAULT=0xYourLSPVault
export BRIDGED_STFLOW=0xYourBridgedStFlowERC20
export EVM_USER_PK=0x...   # test only; never mainnet / real funds
```

---

## 1) Read minimum stake (EVM)

```bash
cast call "$LSP_VAULT" "getConfig()(uint256,bool,bool,uint256)" --rpc-url "$RPC"
```

First tuple value is **`minStakeAmount`** (wei). Your `requestStake` **`--value`** must be **≥** that.

---

## 2) User: `requestStake()` (native FLOW)

Example: **1 FLOW** (adjust to satisfy `minStakeAmount`):

```bash
export STAKE_VALUE=$(cast to-unit 1ether wei)
cast send "$LSP_VAULT" "requestStake()" \
  --value "$STAKE_VALUE" \
  --rpc-url "$RPC" \
  --private-key "$EVM_USER_PK"
```

**First** successful stake on a fresh vault uses **`stakeRequestId` = `1`** (counter starts at `1`). If you already had stakes, read `stakeRequestCount` or events and pick the latest pending id.

---

## 3) Read request fields (for the keeper tx)

Replace `1` with your `stakeRequestId` if different.

```bash
cast call "$LSP_VAULT" "stakeRequests(uint256)(uint8,address,uint256,uint256)" 1 --rpc-url "$RPC"
```

Output order: **`status`**, **`user`**, **`amount`** (stFlow-side units, 18 decimals), **`flowWei`** (locked native FLOW for this request).

Export the last two for the Cadence bundle:

```bash
export STAKE_REQUEST_ID=1
export FLOW_WEI=<flowWei from cast output, decimal integer>
export STFLOW_AMOUNT=<amount from cast output, decimal integer>
```

`nativeFlowAtto` in Cadence must equal **`FLOW_WEI`**. `erc20TransferAmount` must equal **`STFLOW_AMOUNT`** (what Cadence mints must match what you move on EVM).

---

## 4) Cadence type id for `@stFlowToken.Vault`

```bash
export VAULT_IDENTIFIER=$(flow scripts execute cadence/scripts/deployment/stflow_vault_type_identifier.cdc -n "$NETWORK" -o inline | tr -d '"')
echo "$VAULT_IDENTIFIER"
```

---

## 5) Keeper: `fulfill_evm_stake_bundle.cdc` (one transaction)

Pass addresses **with `0x`** as strings. Large integers as **decimal strings** in JSON.

```bash
flow transactions send cadence/transactions/keeper/fulfill_evm_stake_bundle.cdc \
  --args-json "[
    {\"type\":\"String\",\"value\":\"$LSP_VAULT\"},
    {\"type\":\"String\",\"value\":\"$BRIDGED_STFLOW\"},
    {\"type\":\"UInt256\",\"value\":\"$STAKE_REQUEST_ID\"},
    {\"type\":\"UInt\",\"value\":\"$FLOW_WEI\"},
    {\"type\":\"String\",\"value\":\"$VAULT_IDENTIFIER\"},
    {\"type\":\"UInt256\",\"value\":\"$STFLOW_AMOUNT\"}
  ]" \
  -n "$NETWORK" --signer "$SIGNER" -y --compute-limit 9999
```

Signer must be the **protocol account** that holds the COA at `/storage/evm` and `LiquidStaking.Admin`.

---

## 6) Quick checks

EVM rate / config:

```bash
cast call "$LSP_VAULT" "getRate()(uint256)" --rpc-url "$RPC"
```

Cadence TVL / price:

```bash
flow scripts execute cadence/scripts/get_price.cdc -n "$NETWORK" -o inline
flow scripts execute cadence/scripts/get_tvl.cdc -n "$NETWORK" -o inline
```

---

## Optional (later / epochs): `compound_and_sync.cdc`

Not required for a first stake smoke test if EVM `_rate` and Cadence price are aligned; use after epochs to compound rewards and push rate to the vault:

```bash
flow transactions send cadence/transactions/keeper/compound_and_sync.cdc \
  "$LSP_VAULT" \
  -n "$NETWORK" --signer "$SIGNER" -y --compute-limit 9999
```

---

## Troubleshooting

- **`MinAmountNotMet`**: increase `--value` vs `getConfig().minStakeAmount`.
- **`fulfillStakeRequest failed` / bridge errors**: ensure `FLOW_WEI` / `STFLOW_AMOUNT` match `stakeRequests(id)` exactly; ensure `VAULT_IDENTIFIER` matches `Type<@stFlowToken.Vault>().identifier` on that network.
- **`nativeFlowAtto` / UInt**: use the same decimal integer string Flow expects (the wei pulled to Cadence after `withdrawPendingStakeNative`).
