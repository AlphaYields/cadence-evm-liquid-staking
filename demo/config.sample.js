// Default demo config (safe to commit). Copy to `config.local.js` (gitignored) and override.
window.DEMO_CONFIG = Object.assign(window.DEMO_CONFIG || {}, {
  flowAccessRest: "https://rest-testnet.onflow.org",
  evmRpc: "https://testnet.evm.nodes.onflow.org",
  evmChainId: 545,
  /** Cadence account where `LiquidStaking` + `stFlowToken` live (with `0x`). */
  cadenceDeployer: "0x2ebe72605dfc9fd0",
  /** Core contract — testnet default from `flow.json`. */
  flowIDTableStaking: "0x9eca2b38b18b5dfe",
  lspVault: "0xCDb6839Bb928436C412E8F1DFb02D6CeAF432B92",
  bridgedStFlow: "0x4e1ef470e39d6481199cc4577ecd75b38e217702",
  /** From `flow scripts execute cadence/scripts/deployment/stflow_vault_type_identifier.cdc` */
  vaultIdentifier: "A.2ebe72605dfc9fd0.stFlowToken.Vault",
  /** Optional: EVM address to show bridged stFlow `balanceOf`. */
  evmBalanceOfAddress: "0xF961DB7172ea9069F1E62eF92F410aC48bCc6088",
  flowSigner: "testnet-acc",
  networkFlag: "testnet",
  /** Path relative to repo root for generated keeper command. */
  keeperCdcPath: "cadence/transactions/keeper/fulfill_evm_stake_bundle.cdc",
});
