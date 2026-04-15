import "EVM"
import "LiquidStaking"

/// ABI-encode uint256 as 32 big-endian bytes.
access(all) fun encodeUint256Word(_ value: UInt256): [UInt8] {
    var out: [UInt8] = []
    var remaining = value
    var i = 0
    while i < 32 {
        out = [UInt8(remaining % 256)].concat(out)
        remaining = remaining / 256
        i = i + 1
    }
    return out
}

/// ABI-encode bool as a 32-byte word (0 or 1).
access(all) fun encodeBoolWord(_ value: Bool): [UInt8] {
    if value {
        return encodeUint256Word(UInt256(1))
    }
    return encodeUint256Word(UInt256(0))
}

/// Updates LiquidStaking (Cadence) and LSPVault (EVM) config in one atomic transaction.
///
/// Cadence (`LiquidStaking`):
/// - `cadenceProtocolFee` — fraction of rewards kept by the protocol (0.0–1.0), e.g. `0.1` = 10%
/// - `cadencePaused` — when `true`, stake and unstake on Cadence are blocked
///
/// EVM (`LSPVault.updateConfig`):
/// - `minStakeWei` — minimum native FLOW for `requestStake` (wei, 18 decimals)
/// - `evmStakingPaused` / `evmUnstakingPaused` — EVM-side pause flags
/// - `evmProtocolFee1e18` — fee field on the vault (1e18 = 100%); align with Cadence for UX
///
/// Selector: `updateConfig((uint256,bool,bool,uint256))` = `0xded28040`
///
/// `evmVaultAddress` — EVM address string (with or without `0x`).
transaction(
    evmVaultAddress: String,
    cadenceProtocolFee: UFix64,
    cadencePaused: Bool,
    minStakeWei: UInt256,
    evmStakingPaused: Bool,
    evmUnstakingPaused: Bool,
    evmProtocolFee1e18: UInt256
) {
    let admin: &LiquidStaking.Admin
    let coa: auth(EVM.Call) &EVM.CadenceOwnedAccount

    prepare(signer: auth(BorrowValue) &Account) {
        self.admin = signer.storage
            .borrow<&LiquidStaking.Admin>(from: LiquidStaking.AdminStoragePath)
            ?? panic("Could not borrow Admin resource")

        self.coa = signer.storage
            .borrow<auth(EVM.Call) &EVM.CadenceOwnedAccount>(from: /storage/evm)
            ?? panic("COA not found — run setup_coa first")
    }

    execute {
        assert(cadenceProtocolFee <= 1.0, message: "Cadence protocol fee cannot exceed 100%")

        self.admin.setProtocolFee(newFee: cadenceProtocolFee)
        self.admin.setPaused(paused: cadencePaused)

        // updateConfig((uint256,bool,bool,uint256))
        var data: [UInt8] = [0xde, 0xd2, 0x80, 0x40]
        data = data.concat(encodeUint256Word(minStakeWei))
        data = data.concat(encodeBoolWord(evmStakingPaused))
        data = data.concat(encodeBoolWord(evmUnstakingPaused))
        data = data.concat(encodeUint256Word(evmProtocolFee1e18))

        let vaultAddr = EVM.addressFromString(evmVaultAddress)

        let result = self.coa.call(
            to: vaultAddr,
            data: data,
            gasLimit: 500_000,
            value: EVM.Balance(attoflow: 0)
        )
        assert(result.status == EVM.Status.successful, message: "LSPVault.updateConfig failed")
    }
}
