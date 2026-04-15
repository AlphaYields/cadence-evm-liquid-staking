import "FungibleToken"
import "stFlowToken"
import "LiquidStaking"

/// User unstakes stFlow. Returns a request ID (logged) that they use to cashout later.
transaction(amount: UFix64) {

    let stFlowVault: @stFlowToken.Vault
    let requester: Address

    prepare(signer: auth(BorrowValue) &Account) {
        let vault = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &stFlowToken.Vault>(from: stFlowToken.tokenVaultPath)
            ?? panic("Could not borrow stFlow vault")
        self.stFlowVault <- vault.withdraw(amount: amount) as! @stFlowToken.Vault
        self.requester = signer.address
    }

    execute {
        let requestId = LiquidStaking.unstake(from: <-self.stFlowVault, requester: self.requester)
        log("Unstake request created with ID: ".concat(requestId.toString()))
    }
}
