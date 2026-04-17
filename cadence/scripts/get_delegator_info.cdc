import "FlowIDTableStaking"

/// On-chain delegator buckets for `(nodeID, delegatorID)` — same pattern as Flow’s
/// [get_delegator_info.cdc](https://github.com/onflow/flow-core-contracts/blob/master/transactions/idTableStaking/delegation/get_delegator_info.cdc).
///
/// **`nodeID`**: the operator node you used in `register_delegator.cdc`.
/// **`delegatorID`**: the numeric ID assigned to your delegator for that node (tx events / explorer / Flow Port).
access(all) fun main(nodeID: String, delegatorID: UInt32): FlowIDTableStaking.DelegatorInfo {
    return FlowIDTableStaking.DelegatorInfo(nodeID: nodeID, delegatorID: delegatorID)
}
