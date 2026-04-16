import "EVM"
import "LiquidStaking"
import "FungibleToken"
import "FungibleTokenMetadataViews"
import "ViewResolver"
import "MetadataViews"
import "FlowToken"
import "stFlowToken"

import "ScopedFTProviders"

import "FlowEVMBridge"
import "FlowEVMBridgeConfig"
import "FlowEVMBridgeUtils"

/// **Unstake tx 1 / 3** — everything before epoch processing: pull locked stFlow from `LSPVault` to the COA,
/// bridge EVM → Cadence via Flow EVM Bridge, then `LiquidStaking.unstake` on Cadence.
///
/// After the epoch: **`process_unstakes.cdc`**, then **`fulfill_evm_unstake_finalize_bundle.cdc`** (tx 3 / 3).
///
/// Args:
/// - `evmVaultAddress` — `LSPVault` hex.
/// - `unstakeRequestId` — EVM pending unstake id.
/// - `vaultIdentifier` — Cadence type id for `@stFlowToken.Vault` (same as stake bundle).
/// - `bridgeAmount` — UInt256 amount for `coa.withdrawTokens` (EVM ERC‑20 smallest units).
/// - `unstakeAmount` — UFix64 amount withdrawn from the Cadence stFlow vault for `LiquidStaking.unstake` (must match bridged balance in Cadence units).
transaction(
    evmVaultAddress: String,
    unstakeRequestId: UInt256,
    vaultIdentifier: String,
    bridgeAmount: UInt256,
    unstakeAmount: UFix64,
) {
    let coa: auth(EVM.Call, EVM.Bridge) &EVM.CadenceOwnedAccount
    let vaultType: Type
    let receiver: &{FungibleToken.Vault}
    let scopedProvider: @ScopedFTProviders.ScopedFTProvider
    let stFlowSource: auth(FungibleToken.Withdraw) &stFlowToken.Vault
    let requester: Address

    prepare(signer: auth(BorrowValue, CopyValue, IssueStorageCapabilityController, PublishCapability, SaveValue, UnpublishCapability) &Account) {
        self.requester = signer.address

        self.coa = signer.storage.borrow<auth(EVM.Call, EVM.Bridge) &EVM.CadenceOwnedAccount>(from: /storage/evm)
            ?? panic("COA not found at /storage/evm — run setup_coa; need Call + Bridge")

        self.stFlowSource = signer.storage.borrow<auth(FungibleToken.Withdraw) &stFlowToken.Vault>(from: stFlowToken.tokenVaultPath)
            ?? panic("Could not borrow stFlow vault at stFlowToken.tokenVaultPath")

        self.vaultType = CompositeType(vaultIdentifier)
            ?? panic("Could not construct Vault type from identifier: ".concat(vaultIdentifier))
        let tokenContractAddress = FlowEVMBridgeUtils.getContractAddress(fromType: self.vaultType)
            ?? panic("Could not get contract address from identifier: ".concat(vaultIdentifier))
        let tokenContractName = FlowEVMBridgeUtils.getContractName(fromType: self.vaultType)
            ?? panic("Could not get contract name from identifier: ".concat(vaultIdentifier))

        let viewResolver = getAccount(tokenContractAddress).contracts.borrow<&{ViewResolver}>(name: tokenContractName)
            ?? panic("Could not borrow ViewResolver for "
                .concat(tokenContractName).concat(" @ ").concat(tokenContractAddress.toString()))
        let vaultData = viewResolver.resolveContractView(
                resourceType: self.vaultType,
                viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
            ) as! FungibleTokenMetadataViews.FTVaultData?
            ?? panic("Could not resolve FTVaultData for ".concat(self.vaultType.identifier))

        if signer.storage.borrow<&{FungibleToken.Vault}>(from: vaultData.storagePath) == nil {
            signer.storage.save(<-vaultData.createEmptyVault(), to: vaultData.storagePath)
            signer.capabilities.unpublish(vaultData.receiverPath)
            signer.capabilities.unpublish(vaultData.metadataPath)
            let receiverCap = signer.capabilities.storage.issue<&{FungibleToken.Vault}>(vaultData.storagePath)
            let metadataCap = signer.capabilities.storage.issue<&{FungibleToken.Vault}>(vaultData.storagePath)
            signer.capabilities.publish(receiverCap, at: vaultData.receiverPath)
            signer.capabilities.publish(metadataCap, at: vaultData.metadataPath)
        }
        self.receiver = signer.storage.borrow<&{FungibleToken.Vault}>(from: vaultData.storagePath)
            ?? panic("Could not borrow receiver vault at ".concat(vaultData.storagePath.toString()))

        var approxFee = FlowEVMBridgeUtils.calculateBridgeFee(bytes: 400_000)
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

        let pullData = EVM.encodeABIWithSignature("withdrawPendingUnstakeStFlow(uint256)", [unstakeRequestId])
        let pullRes = self.coa.call(
            to: vaultAddr,
            data: pullData,
            gasLimit: 300_000,
            value: EVM.Balance(attoflow: 0)
        )
        assert(pullRes.status == EVM.Status.successful, message: "withdrawPendingUnstakeStFlow failed")

        let bridged: @{FungibleToken.Vault} <- self.coa.withdrawTokens(
            type: self.vaultType,
            amount: bridgeAmount,
            feeProvider: &self.scopedProvider as auth(FungibleToken.Withdraw) &{FungibleToken.Provider}
        )
        assert(
            bridged.getType() == self.vaultType,
            message: "Bridged vault type mismatch"
        )
        self.receiver.deposit(from: <-bridged)
        destroy self.scopedProvider

        let stFlowVault <- self.stFlowSource.withdraw(amount: unstakeAmount) as! @stFlowToken.Vault
        let cadenceRequestId = LiquidStaking.unstake(from: <-stFlowVault, requester: self.requester)
        log("Cadence unstake request id: ".concat(cadenceRequestId.toString()))
    }
}
