import "FlowIDTableStaking"

/// The **delegator ID your next `register_delegator` call will receive** for this `nodeID`
/// (staking table increments counter, then assigns that id — see `NewDelegatorCreated` in core contracts).
///
/// Run **before** `register_delegator.cdc` for that node; after registration, re-run if you need the id you just got
/// (it will have advanced by one).
access(all) fun main(nodeID: String): UInt32 {
    let info = FlowIDTableStaking.NodeInfo(nodeID: nodeID)
    return info.delegatorIDCounter + UInt32(1)
}
