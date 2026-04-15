import "FungibleToken"
import "stFlowToken"

/// Sets up the stFlow token vault in the user's account.
transaction {
    prepare(signer: auth(SaveValue, Capabilities) &Account) {
        if signer.storage.borrow<&stFlowToken.Vault>(from: stFlowToken.tokenVaultPath) != nil {
            return
        }

        signer.storage.save(
            <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()),
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
