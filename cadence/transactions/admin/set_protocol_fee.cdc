import "LiquidStaking"

/// Admin updates the protocol fee percentage.
transaction(newFee: UFix64) {
    let admin: &LiquidStaking.Admin

    prepare(signer: auth(BorrowValue) &Account) {
        self.admin = signer.storage
            .borrow<&LiquidStaking.Admin>(from: LiquidStaking.AdminStoragePath)
            ?? panic("Could not borrow Admin resource")
    }

    execute {
        self.admin.setProtocolFee(newFee: newFee)
    }
}
