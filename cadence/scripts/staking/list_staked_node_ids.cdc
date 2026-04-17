import "FlowIDTableStaking"

/// All node IDs currently in the **participant** (staked) set for this epoch.
/// Pick one (see `staked_node_id_at_index.cdc`) to pass as `nodeID` to `register_delegator.cdc`.
access(all) fun main(): [String] {
    return FlowIDTableStaking.getStakedNodeIDs()
}
