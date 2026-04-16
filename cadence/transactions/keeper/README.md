# Keeper Cadence transactions

| File | Purpose |
|------|---------|
| `compound_and_sync.cdc` | Compound rewards + COA `syncRate` on `LSPVault`. |
| `process_unstakes.cdc` | After epoch: delegator `tokensUnstaked` → withdraw pool; all pending unstakes → ready (system / keeper, like compound). |
| `fulfill_evm_stake_bundle.cdc` | **Single tx** — full EVM stake fulfillment (vault pull → Cadence stake → bridge → ERC‑20 transfer → `fulfillStakeRequest`). |
| `fulfill_evm_unstake_start_bundle.cdc` | **Unstake tx 1/3** — vault pull → bridge to Cadence → `LiquidStaking.unstake`. |
| `fulfill_evm_unstake_finalize_bundle.cdc` | **Unstake tx 3/3** — after `process_unstakes.cdc`: pool → COA → fund vault → `fulfillUnstakeRequest`. |

Official Flow EVM bridge contracts are **`flow.json`** dependencies (testnet `dfc20aee650fcbdf`); upstream txs live in [onflow/flow-evm-bridge](https://github.com/onflow/flow-evm-bridge).
