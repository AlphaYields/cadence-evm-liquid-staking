import "EVM"
import "LiquidStaking"
import "FlowToken"
import "FungibleToken"

import "ScopedFTProviders"

import "FlowEVMBridge"
import "FlowEVMBridgeConfig"
import "FlowEVMBridgeUtils"

/// Single transaction: EVM stake fulfillment end-to-end.
///
/// 1. `withdrawPendingStakeNative` — native FLOW from `LSPVault` → COA (EVM).
/// 2. `coa.withdraw` — that FLOW → Cadence `@FlowToken.Vault`.
/// 3. `LiquidStaking.stake` — mint `@stFlowToken.Vault` at current Cadence rate.
/// 4. Official Flow EVM bridge — `onboardByType` if needed, then `coa.depositTokens` (stFlow → COA as ERC‑20).
/// 5. ERC‑20 `transfer` — stFlow from COA → `LSPVault` (vault contract address).
/// 6. `fulfillStakeRequest` — burn receipt, pay user stFlow from vault.
///
/// Args:
/// - `evmVaultAddress` — `LSPVault` hex.
/// - `evmStFlowContractHex` — bridged stFlow ERC‑20 on Flow EVM (same as vault `ST_FLOW_ADDRESS`).
/// - `stakeRequestId` — pending stake id on the vault.
/// - `nativeFlowAtto` — wei to pull from COA after step 1; must match locked `flowWei` for that request.
/// - `vaultIdentifier` — Cadence type id for `@stFlowToken.Vault` (e.g. from `Type<@stFlowToken.Vault>().identifier` on your network).
/// - `erc20TransferAmount` — ERC‑20 amount in **EVM smallest units** for `transfer(vault, amount)`; must match the stake request’s stFlow amount on EVM.
transaction(
    evmVaultAddress: String,
    evmStFlowContractHex: String,
    stakeRequestId: UInt256,
    nativeFlowAtto: UInt,
    vaultIdentifier: String,
    erc20TransferAmount: UInt256,
) {
    let coa: auth(EVM.Call, EVM.Withdraw, EVM.Bridge) &EVM.CadenceOwnedAccount
    let scopedProvider: @ScopedFTProviders.ScopedFTProvider

    prepare(signer: auth(CopyValue, BorrowValue, IssueStorageCapabilityController, PublishCapability, SaveValue) &Account) {
        self.coa = signer.storage.borrow<auth(EVM.Call, EVM.Withdraw, EVM.Bridge) &EVM.CadenceOwnedAccount>(from: /storage/evm)
            ?? panic("COA not found at /storage/evm — run setup_coa; need Call + Withdraw + Bridge entitlements")

        var approxFee = FlowEVMBridgeUtils.calculateBridgeFee(bytes: 400_000)
        approxFee = approxFee + FlowEVMBridgeConfig.onboardFee

        if signer.storage.type(at: FlowEVMBridgeConfig.providerCapabilityStoragePath) == nil {
            let providerCap = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &{FungibleToken.Provider}>(
                /storage/flowTokenVault
            )
            signer.storage.save(providerCap, to: FlowEVMBridgeConfig.providerCapabilityStoragePath)
        }
        let providerCapCopy = signer.storage.copy<Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Provider}>>(
                from: FlowEVMBridgeConfig.providerCapabilityStoragePath
            ) ?? panic("Invalid Flow fee provider capability at "
                .concat(FlowEVMBridgeConfig.providerCapabilityStoragePath.toString()))
        let providerFilter = ScopedFTProviders.AllowanceFilter(approxFee)
        self.scopedProvider <- ScopedFTProviders.createScopedFTProvider(
                provider: providerCapCopy,
                filters: [providerFilter],
                expiration: getCurrentBlock().timestamp + 1.0
            )
    }

    execute {
        let vaultAddr = EVM.addressFromString(evmVaultAddress)

        let pullData = EVM.encodeABIWithSignature("withdrawPendingStakeNative(uint256)", [stakeRequestId])
        let pullRes = self.coa.call(
            to: vaultAddr,
            data: pullData,
            gasLimit: 200_000,
            value: EVM.Balance(attoflow: 0)
        )
        assert(pullRes.status == EVM.Status.successful, message: "withdrawPendingStakeNative failed")

        let withdrawBalance = EVM.Balance(attoflow: nativeFlowAtto)
        let flowVault <- self.coa.withdraw(balance: withdrawBalance) as! @FlowToken.Vault
        let stFlowVault <- LiquidStaking.stake(from: <-flowVault)

        assert(
            stFlowVault.getType().identifier == vaultIdentifier,
            message: "stFlow vault type mismatch: expected ".concat(vaultIdentifier)
                .concat(" got ").concat(stFlowVault.getType().identifier)
        )

        let needsOnboard = FlowEVMBridge.typeRequiresOnboarding(stFlowVault.getType())
            ?? panic("FlowEVMBridge does not support this vault type: ".concat(vaultIdentifier))
        if needsOnboard {
            FlowEVMBridge.onboardByType(
                stFlowVault.getType(),
                feeProvider: &self.scopedProvider as auth(FungibleToken.Withdraw) &{FungibleToken.Provider}
            )
        }

        self.coa.depositTokens(
            vault: <-stFlowVault,
            feeProvider: &self.scopedProvider as auth(FungibleToken.Withdraw) &{FungibleToken.Provider}
        )

        let xferData = EVM.encodeABIWithSignature(
            "transfer(address,uint256)",
            [vaultAddr, erc20TransferAmount]
        )
        let xferRes = self.coa.call(
            to: EVM.addressFromString(evmStFlowContractHex),
            data: xferData,
            gasLimit: 200_000,
            value: EVM.Balance(attoflow: 0)
        )
        assert(xferRes.status == EVM.Status.successful, message: "ERC20.transfer to LSPVault failed")

        let fulfillData = EVM.encodeABIWithSignature("fulfillStakeRequest(uint256)", [stakeRequestId])
        let fulfillRes = self.coa.call(
            to: vaultAddr,
            data: fulfillData,
            gasLimit: 500_000,
            value: EVM.Balance(attoflow: 0)
        )
        assert(fulfillRes.status == EVM.Status.successful, message: "fulfillStakeRequest failed")

        destroy self.scopedProvider
    }
}
