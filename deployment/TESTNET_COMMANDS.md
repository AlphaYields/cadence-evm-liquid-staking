# Testnet: copy-paste CLI sequence

From the **repo root**. Uses `flow.json` account **`testnet-acc`** and `jq` to read its address. Change `NETWORK` / `SIGNER` if needed.

```bash
cd /path/to/flow-native-staking

export NETWORK=testnet
export SIGNER=testnet-acc
export DEPLOYER=$(jq -r '.accounts["testnet-acc"].address' flow.json)
```

## 1. Staking inputs from chain (no hand-picked node id)

Optional: list all staked node ids:

```bash
flow scripts execute cadence/scripts/staking/list_staked_node_ids.cdc -n "$NETWORK" -o inline
```

Pick index `0` (use `1`, `2`, … if `0` fails delegation):

```bash
export NODE_ID=$(flow scripts execute cadence/scripts/staking/staked_node_id_at_index.cdc 0 -n "$NETWORK" -o inline | tr -d '"')
echo "NODE_ID=$NODE_ID"
```

Delegator id your **next** `register_delegator` will receive (re-run this immediately before that tx if the chain is busy):

```bash
export DELEGATOR_ID=$(flow scripts execute cadence/scripts/staking/next_delegator_id_for_node.cdc "$NODE_ID" -n "$NETWORK" -o inline)
echo "DELEGATOR_ID=$DELEGATOR_ID"
```

Minimum FLOW for `register_delegator`:

```bash
export COMMIT=$(flow scripts execute cadence/scripts/staking/delegator_minimum_stake.cdc -n "$NETWORK" -o inline)
echo "COMMIT=$COMMIT"
```

Fund `DEPLOYER` so `/storage/flowTokenVault` can cover `COMMIT` plus fees.

## 2. Cadence deploy + admin setup

```bash
flow deploy -n "$NETWORK" --signer "$SIGNER" -y
```

```bash
flow transactions send cadence/transactions/admin/setup_flow_and_stflow_vaults.cdc \
  -n "$NETWORK" --signer "$SIGNER" -y
```

```bash
flow transactions send cadence/transactions/admin/register_delegator.cdc \
  "$NODE_ID" "$COMMIT" \
  -n "$NETWORK" --signer "$SIGNER" -y
```

```bash
flow transactions send cadence/transactions/admin/setup_coa.cdc \
  -n "$NETWORK" --signer "$SIGNER" -y
```

```bash
flow scripts execute cadence/scripts/deployment/get_coa_evm_address.cdc "$DEPLOYER" -n "$NETWORK" -o inline
```

Delegator snapshot (after successful register; uses same `NODE_ID` / `DELEGATOR_ID` as above):

```bash
flow scripts execute cadence/scripts/get_delegator_info.cdc \
  "$NODE_ID" "$DELEGATOR_ID" \
  -n "$NETWORK" -o inline
```

## 3. Bridge onboard (Cadence tx) + read ERC‑20 address

Requires FLOW in `/storage/flowTokenVault` for bridge onboarding fees.

```bash
flow transactions send cadence/transactions/admin/onboard_stflow_token_type_for_evm_bridge.cdc \
  -n "$NETWORK" --signer "$SIGNER" -y
```

```bash
export BRIDGED_STFLOW=$(flow scripts execute cadence/scripts/deployment/get_bridged_stflow_evm_address.cdc -n "$NETWORK" -o inline | tr -d '"')
echo "BRIDGED_STFLOW=$BRIDGED_STFLOW"
```

If this prints empty / wrong, re-run the script after the onboard tx seals; `nil` prints as empty for `-o inline` in some CLI versions—use default text output if needed.

Vault type id (optional, for keeper / bridge forms):

```bash
flow scripts execute cadence/scripts/deployment/stflow_vault_type_identifier.cdc -n "$NETWORK" -o inline
```

## 4. Deploy `LSPVault` on Flow EVM (constructor = `BRIDGED_STFLOW`)

```bash
cd evm
forge build
INIT=$(forge inspect LSPVault bytecode | sed 's/^0x//')
ARGS=$(cast abi-encode "f(address)" "$BRIDGED_STFLOW" | sed 's/^0x//')
BYTECODE="${INIT}${ARGS}"
cd ..

flow transactions send cadence/transactions/admin/deploy_evm_contract.cdc \
  "$BYTECODE" \
  -n "$NETWORK" --signer "$SIGNER" -y --compute-limit 9999
```

Set `LSP_VAULT` from the log line **`Contract deployed at:`** (copy the `0x…` hex):

```bash
export LSP_VAULT='0xPASTE_FROM_TX_LOG'
```

## 5. Align Cadence + EVM config

Edit the JSON values if you want different fee / min stake / pauses.

```bash
flow transactions send cadence/transactions/admin/update_liquid_staking_and_evm_vault.cdc \
  --args-json "[{\"type\":\"String\",\"value\":\"$LSP_VAULT\"},{\"type\":\"UFix64\",\"value\":\"0.1\"},{\"type\":\"Bool\",\"value\":false},{\"type\":\"UInt256\",\"value\":\"1000000000000000000\"},{\"type\":\"Bool\",\"value\":false},{\"type\":\"Bool\",\"value\":false},{\"type\":\"UInt256\",\"value\":\"100000000000000000\"}]" \
  -n "$NETWORK" --signer "$SIGNER" -y --compute-limit 9999
```

## 6. Sanity

```bash
flow scripts execute cadence/scripts/get_price.cdc -n "$NETWORK" -o inline
flow scripts execute cadence/scripts/get_tvl.cdc -n "$NETWORK" -o inline
```

## Contract upgrades only

```bash
flow project deploy --update -n "$NETWORK" --signer "$SIGNER" -y
```

## Notes

- Add `-f /path/to/flow.json` to any command if `flow.json` is not in the current directory.
- If `register_delegator` fails with staking auction closed, wait for the next staking window and retry (see [epoch schedule](https://developers.flow.com/networks/staking/schedule)).
- Save addresses into `deployment/deployment.local.json` (gitignored); start from `deployment/deployment.example.json`.

## After setup: EVM stake + keeper (stake only)

See **[`EVM_STAKE_FLOW.md`](EVM_STAKE_FLOW.md)** — user `cast send … requestStake()` on Flow EVM, then protocol `flow transactions send … fulfill_evm_stake_bundle.cdc` (no unstake path).
