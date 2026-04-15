import "LiquidStaking"

/// Keeper calls after epoch boundary to withdraw unstaked tokens from the
/// delegator and move pending unstake requests to ready-to-claim.
transaction {
    let admin: &LiquidStaking.Admin

    prepare(signer: auth(BorrowValue) &Account) {
        self.admin = signer.storage
            .borrow<&LiquidStaking.Admin>(from: LiquidStaking.AdminStoragePath)
            ?? panic("Could not borrow Admin resource")
    }

    execute {
        self.admin.processUnstakes()
    }
}
