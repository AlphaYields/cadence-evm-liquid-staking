# Admin setup (order)

Run on the **protocol Cadence account** that will hold `LiquidStaking.Admin` and the COA (same signer as in this POC).

## Fresh testnet deploy (ignore an old address)

You cannot reliably “delete everything” on **the same** account and redeploy: `stFlowToken` / `LiquidStaking` `init()` reuse fixed storage paths, and a registered **delegator** is tied to Flow staking. **Use a new funded testnet account** and point `flow.json` at it; leave the old `0x…` unused.

1. **New keys** — `flow keys generate` (save the private key to a file, e.g. `protocol-testnet.pkey`; `*.pkey` is gitignored).
2. **Create the account on testnet** — e.g. [Create account](https://developers.flow.com/tools/flow-cli/create-accounts) / [Faucet](https://testnet-faucet.onflow.org/) with your new public key; note the new address.
3. **Point `flow.json` at it** — under `accounts`, set `testnet-acc` (or rename the entry and update `deployments.testnet` to match) to the **new** `address` and `key.location` for your key file. Keep `deployments.testnet.<that-account-name>: ["stFlowToken", "LiquidStaking"]`.
4. **Deploy** — from repo root: `flow deploy -n testnet` (use `flow project deploy --update -n testnet` only when you intend to **upgrade** contracts already on that account).
5. **Run the setup txs below** on that same account in order.

The old deployment is simply abandoned; no need to remove contracts on the old address for your new demo.

1. **`flow.json`** — ensure `stFlowToken` + `LiquidStaking` deployments point at this account for your network; deploy contracts (`flow deploy -n …`).
2. **`setup_flow_and_stflow_vaults.cdc`** — `/storage/flowTokenVault` (needed for `register_delegator`, users, keeper bridge fees) + stFlow vault + public caps (same as `user/setup_stflow_vault.cdc`).
3. **`register_delegator.cdc`** — one-time; `nodeID` + `initialCommitment` FLOW from `/storage/flowTokenVault`.
4. **`setup_coa.cdc`** — COA at `/storage/evm` + public **`/public/coaEVM`** for address scripts.
5. **Flow EVM bridge (Cadence tx)** — run **`onboard_stflow_token_type_for_evm_bridge.cdc`** (calls `FlowEVMBridge.onboardByType` for `Type<@stFlowToken.Vault>`, same mechanism as the keeper stake bundle). Then read the ERC‑20 with **`cadence/scripts/deployment/get_bridged_stflow_evm_address.cdc`**. You need this **before** deploying `LSPVault` (constructor `ST_FLOW_ADDRESS`).
6. **`deploy_evm_contract.cdc`** — deploy `LSPVault` with bytecode that already includes the bridged stFlow address in the constructor args. Logged EVM address → save in `deployment/deployment.local.json`.
7. **`update_liquid_staking_and_evm_vault.cdc`** — align Cadence fee/pause with `LSPVault.updateConfig` (min stake wei, pause flags, EVM fee field).

**Also available:** `set_protocol_fee.cdc`, `set_paused.cdc` for smaller updates without touching EVM config.

**Deployment record:** copy `deployment/deployment.example.json` → `deployment/deployment.local.json` (gitignored). Populate with:

- `flow scripts execute cadence/scripts/deployment/get_coa_evm_address.cdc <hex>` (args: deployer address)
- `flow scripts execute cadence/scripts/deployment/stflow_vault_type_identifier.cdc` (no args; uses current network’s `stFlowToken` import)
- `flow scripts execute cadence/scripts/deployment/get_bridged_stflow_evm_address.cdc` (after `onboard_stflow_token_type_for_evm_bridge.cdc`)

**Full CLI sequence (testnet):** [`deployment/TESTNET_COMMANDS.md`](../../../deployment/TESTNET_COMMANDS.md)
