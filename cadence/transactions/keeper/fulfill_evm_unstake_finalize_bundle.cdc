import "EVM"
import "LiquidStaking"

/// **Unstake tx 3 / 3** — run only after **`process_unstakes.cdc`** has moved this request to **ready** on Cadence.
///
/// 1. `finalizeUnstakeForEvm` — pull FLOW for `cadenceUnstakeRequestId` from the withdraw pool and remove that ready record.
/// 2. `coa.deposit` — FLOW to the COA’s EVM balance.
/// 3. Native transfer to `LSPVault` (`receive()`).
/// 4. `fulfillUnstakeRequest(evmUnstakeRequestId, evmFlowAmountWei)`.
///
/// Order: **`fulfill_evm_unstake_start_bundle.cdc`** → wait epoch → **`process_unstakes.cdc`** → this file.
transaction(
    evmVaultAddress: String,
    evmUnstakeRequestId: UInt256,
    cadenceUnstakeRequestId: UInt64,
    evmFlowAmountWei: UInt256,
    nativeFlowAttoToVault: UInt,
) {
    let admin: &LiquidStaking.Admin
    let coaCall: auth(EVM.Call) &EVM.CadenceOwnedAccount
    let coaAny: &EVM.CadenceOwnedAccount

    prepare(signer: auth(BorrowValue) &Account) {
        self.admin = signer.storage.borrow<&LiquidStaking.Admin>(from: LiquidStaking.AdminStoragePath)
            ?? panic("Could not borrow LiquidStaking.Admin")

        self.coaCall = signer.storage.borrow<auth(EVM.Call) &EVM.CadenceOwnedAccount>(from: /storage/evm)
            ?? panic("COA not found — run setup_coa first")

        self.coaAny = signer.storage.borrow<&EVM.CadenceOwnedAccount>(from: /storage/evm)
            ?? panic("COA not found — run setup_coa first")
    }

    execute {
        let flowVault <- self.admin.finalizeUnstakeForEvm(requestId: cadenceUnstakeRequestId)
        self.coaAny.deposit(from: <-flowVault)

        let vaultAddr = EVM.addressFromString(evmVaultAddress)

        let sendRes = self.coaCall.call(
            to: vaultAddr,
            data: [],
            gasLimit: 100_000,
            value: EVM.Balance(attoflow: nativeFlowAttoToVault)
        )
        assert(sendRes.status == EVM.Status.successful, message: "Native FLOW transfer to LSPVault failed")

        let data = EVM.encodeABIWithSignature(
            "fulfillUnstakeRequest(uint256,uint256)",
            [evmUnstakeRequestId, evmFlowAmountWei]
        )
        let res = self.coaCall.call(
            to: vaultAddr,
            data: data,
            gasLimit: 500_000,
            value: EVM.Balance(attoflow: 0)
        )
        assert(res.status == EVM.Status.successful, message: "fulfillUnstakeRequest failed")
    }
}
