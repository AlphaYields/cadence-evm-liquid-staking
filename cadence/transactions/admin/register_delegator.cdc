import "FungibleToken"
import "FlowToken"
import "LiquidStaking"

/// Admin registers the protocol as a delegator to a node operator.
/// Must be called once before staking begins.
transaction(nodeID: String, initialCommitment: UFix64) {
    let admin: &LiquidStaking.Admin
    let flowVault: @FlowToken.Vault

    prepare(signer: auth(BorrowValue) &Account) {
        self.admin = signer.storage
            .borrow<&LiquidStaking.Admin>(from: LiquidStaking.AdminStoragePath)
            ?? panic("Could not borrow Admin resource")

        let vault = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Could not borrow FLOW vault")
        self.flowVault <- vault.withdraw(amount: initialCommitment) as! @FlowToken.Vault
    }

    execute {
        self.admin.registerDelegator(nodeID: nodeID, from: <-self.flowVault)
    }
}
