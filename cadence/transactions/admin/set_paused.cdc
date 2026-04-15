import "LiquidStaking"

/// Admin pauses or unpauses the protocol.
transaction(paused: Bool) {
    let admin: &LiquidStaking.Admin

    prepare(signer: auth(BorrowValue) &Account) {
        self.admin = signer.storage
            .borrow<&LiquidStaking.Admin>(from: LiquidStaking.AdminStoragePath)
            ?? panic("Could not borrow Admin resource")
    }

    execute {
        self.admin.setPaused(paused: paused)
    }
}
