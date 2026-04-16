import "FungibleToken"
import "FlowToken"
import "stFlowToken"

/// One-time (idempotent) storage setup for the **protocol admin** account (or any account that will
/// `register_delegator`, pay bridge fees from FLOW, receive stFlow from keeper paths).
///
/// Creates:
/// - `/storage/flowTokenVault` — required by `register_delegator.cdc`, `user/stake.cdc`, `user/cashout.cdc`, keeper bridge fee paths.
/// - `stFlowToken.tokenVaultPath` + published receiver/balance caps — same as `user/setup_stflow_vault.cdc`.
transaction {
    prepare(signer: auth(SaveValue, Capabilities) &Account) {
        if signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault) == nil {
            signer.storage.save(
                <-FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>()),
                to: /storage/flowTokenVault
            )
        }

        if signer.storage.borrow<&stFlowToken.Vault>(from: stFlowToken.tokenVaultPath) == nil {
            signer.storage.save(
                <-stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()),
                to: stFlowToken.tokenVaultPath
            )

            signer.capabilities.publish(
                signer.capabilities.storage.issue<&{FungibleToken.Receiver}>(stFlowToken.tokenVaultPath),
                at: stFlowToken.tokenReceiverPath
            )

            signer.capabilities.publish(
                signer.capabilities.storage.issue<&{FungibleToken.Balance}>(stFlowToken.tokenVaultPath),
                at: stFlowToken.tokenBalancePath
            )
        }
    }
}
