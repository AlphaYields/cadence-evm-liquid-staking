import "FlowIDTableStaking"

/// Minimum FLOW committed when calling `register_delegator.cdc` (network rule).
access(all) fun main(): UFix64 {
    return FlowIDTableStaking.getDelegatorMinimumStakeRequirement()
}
