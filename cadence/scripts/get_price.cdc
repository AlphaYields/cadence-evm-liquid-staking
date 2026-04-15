import "LiquidStaking"

/// Returns [flowPerStFlow, stFlowPerFlow].
access(all) fun main(): [UFix64; 2] {
    return [
        LiquidStaking.flowPerStFlow(),
        LiquidStaking.stFlowPerFlow()
    ]
}
