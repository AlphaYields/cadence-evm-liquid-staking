import "FlowEVMBridge"
import "FlowEVMBridgeConfig"
import "FlowEVMBridgeUtils"
import "FungibleToken"
import "ScopedFTProviders"
import "stFlowToken"

/// One-time (idempotent): registers **`@stFlowToken.Vault`** with the **official Flow EVM bridge** via
/// `FlowEVMBridge.onboardByType` (same mechanism as `keeper/fulfill_evm_stake_bundle.cdc` step 4).
///
/// Pays onboarding + estimated bridge fees from **`/storage/flowTokenVault`** (scoped allowance).
/// Requires **`setup_flow_and_stflow_vaults.cdc`** so that vault exists.
///
/// After this succeeds, read the ERC‑20 address with **`cadence/scripts/deployment/get_bridged_stflow_evm_address.cdc`**.
transaction {
    let scopedProvider: @ScopedFTProviders.ScopedFTProvider

    prepare(signer: auth(CopyValue, BorrowValue, IssueStorageCapabilityController, PublishCapability, SaveValue) &Account) {
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
        let t = Type<@stFlowToken.Vault>()
        let needsOnboard = FlowEVMBridge.typeRequiresOnboarding(t)
            ?? panic("FlowEVMBridge does not support this vault type: ".concat(t.identifier))
        if needsOnboard {
            FlowEVMBridge.onboardByType(
                t,
                feeProvider: &self.scopedProvider as auth(FungibleToken.Withdraw) &{FungibleToken.Provider}
            )
            log("onboardByType completed for ".concat(t.identifier))
        } else {
            log("onboardByType skipped — type already onboarded")
        }
        destroy self.scopedProvider
    }
}
