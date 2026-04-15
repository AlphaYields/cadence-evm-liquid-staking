import "EVM"
import "LiquidStaking"

/// Keeper calls after each epoch:
/// 1. Compound rewards on Cadence (restake, take fee)
/// 2. Push updated stFlow/FLOW rate to the EVM vault via COA
transaction(evmVaultAddress: String) {
    let admin: &LiquidStaking.Admin
    let coa: auth(EVM.Call) &EVM.CadenceOwnedAccount

    prepare(signer: auth(BorrowValue) &Account) {
        self.admin = signer.storage
            .borrow<&LiquidStaking.Admin>(from: LiquidStaking.AdminStoragePath)
            ?? panic("Could not borrow Admin resource")

        self.coa = signer.storage
            .borrow<auth(EVM.Call) &EVM.CadenceOwnedAccount>(from: /storage/evm)
            ?? panic("COA not found")
    }

    execute {
        self.admin.compoundRewards()

        let newRate = LiquidStaking.flowPerStFlow()

        // syncRate(uint256) selector = 0x8d930108
        // Encode rate as uint256 (UFix64 → 18-decimal EVM scale)
        // UFix64 has 8 decimal places, EVM uses 18, so multiply by 1e10
        let rateScaled = UInt256(newRate * 100_000_000.0) * 10_000_000_000

        // ABI encode: selector (4 bytes) + uint256 (32 bytes)
        var data: [UInt8] = [0x8d, 0x93, 0x01, 0x08]

        // Pad uint256 to 32 bytes big-endian
        var rateBytes: [UInt8] = []
        var remaining = rateScaled
        var i = 0
        while i < 32 {
            rateBytes = [UInt8(remaining % 256)].concat(rateBytes)
            remaining = remaining / 256
            i = i + 1
        }
        data = data.concat(rateBytes)

        let vaultAddr = EVM.addressFromString(evmVaultAddress)

        let result = self.coa.call(
            to: vaultAddr,
            data: data,
            gasLimit: 100_000,
            value: EVM.Balance(attoflow: 0)
        )
        assert(result.status == EVM.Status.successful, message: "syncRate call failed")
    }
}
