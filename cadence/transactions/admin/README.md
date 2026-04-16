# Admin setup (order)

Run on the **protocol Cadence account** that will hold `LiquidStaking.Admin` and the COA (same signer as in this POC).

1. **`flow.json`** — ensure `stFlowToken` + `LiquidStaking` deployments point at this account for your network; deploy contracts (`flow deploy -n …`).
2. **`setup_flow_and_stflow_vaults.cdc`** — `/storage/flowTokenVault` (needed for `register_delegator`, users, keeper bridge fees) + stFlow vault + public caps (same as `user/setup_stflow_vault.cdc`).
3. **`register_delegator.cdc`** — one-time; `nodeID` + `initialCommitment` FLOW from `/storage/flowTokenVault`.
4. **`setup_coa.cdc`** — COA at `/storage/evm` + public **`/public/coaEVM`** for address scripts.
5. **`deploy_evm_contract.cdc`** — deploy `LSPVault` bytecode (constructor args already ABI-encoded in bytecode per Foundry output). Logged EVM address → save in `deployment/deployment.local.json`.
6. **Flow EVM bridge** — onboard Cadence `stFlowToken` so an ERC‑20 exists; save that address as `bridgedStFlowErc20Address` (must match `LSPVault` constructor `ST_FLOW_ADDRESS`).
7. **`update_liquid_staking_and_evm_vault.cdc`** — align Cadence fee/pause with `LSPVault.updateConfig` (min stake wei, pause flags, EVM fee field).

**Also available:** `set_protocol_fee.cdc`, `set_paused.cdc` for smaller updates without touching EVM config.

**Deployment record:** copy `deployment/deployment.example.json` → `deployment/deployment.local.json` (gitignored). Populate with:

- `flow scripts execute cadence/scripts/deployment/get_coa_evm_address.cdc <hex>` (args: deployer address)
- `flow scripts execute cadence/scripts/deployment/stflow_vault_type_identifier.cdc` (no args; uses current network’s `stFlowToken` import)
