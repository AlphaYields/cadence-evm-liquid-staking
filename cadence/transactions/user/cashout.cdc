import "FungibleToken"
import "FlowToken"
import "LiquidStaking"

/// User claims FLOW from a fulfilled unstake request.
transaction(requestId: UInt64) {

    let receiver: &{FungibleToken.Receiver}

    prepare(signer: auth(BorrowValue) &Account) {
        self.receiver = signer.storage
            .borrow<&{FungibleToken.Receiver}>(from: /storage/flowTokenVault)
            ?? panic("Could not borrow FLOW receiver")
    }

    execute {
        LiquidStaking.cashout(requestId: requestId, receiver: self.receiver)
    }
}
