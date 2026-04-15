import "FungibleToken"
import "FlowToken"
import "stFlowToken"
import "LiquidStaking"

/// User stakes FLOW and receives stFlow.
transaction(amount: UFix64) {

    let flowVault: @FlowToken.Vault
    let stFlowReceiver: &{FungibleToken.Receiver}

    prepare(signer: auth(BorrowValue) &Account) {
        let vault = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Could not borrow FLOW vault")
        self.flowVault <- vault.withdraw(amount: amount) as! @FlowToken.Vault

        self.stFlowReceiver = signer.storage
            .borrow<&{FungibleToken.Receiver}>(from: stFlowToken.tokenVaultPath)
            ?? panic("stFlow vault not set up — run setup_stflow_vault first")
    }

    execute {
        let stFlowVault <- LiquidStaking.stake(from: <-self.flowVault)
        self.stFlowReceiver.deposit(from: <-stFlowVault)
    }
}
