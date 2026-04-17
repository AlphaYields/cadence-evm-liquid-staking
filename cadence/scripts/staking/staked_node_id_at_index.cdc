import "FlowIDTableStaking"

/// Deterministic pick: **`index`** `0` = first staked node, `1` = second, etc.
/// Use output as **`NODE_ID`** for `register_delegator.cdc` and related scripts.
access(all) fun main(index: Int): String {
    let ids = FlowIDTableStaking.getStakedNodeIDs()
    assert(index >= 0, message: "index must be >= 0")
    assert(index < ids.length, message: "index out of range for getStakedNodeIDs()")
    return ids[index]!
}
