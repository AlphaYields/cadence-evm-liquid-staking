import "FlowEVMBridge"
import "stFlowToken"

/// EVM **ERC‑20** address associated with **`@stFlowToken.Vault`** after bridge onboarding
/// (see `admin/onboard_stflow_token_type_for_evm_bridge.cdc` or keeper `onboardByType` path).
///
/// Returns **`nil`** if onboarding is still required (`typeRequiresOnboarding` is true) or no association exists yet.
access(all) fun main(): String? {
    let t = Type<@stFlowToken.Vault>()
    if FlowEVMBridge.typeRequiresOnboarding(t) ?? true {
        return nil
    }
    return FlowEVMBridge.getAssociatedEVMAddress(with: t)?.toString()
}
