import "LiquidStaking"
import "stFlowToken"

/// Returns [totalFlowStaked, stFlowTotalSupply, protocolFee].
access(all) fun main(): [UFix64; 3] {
    return [
        LiquidStaking.totalFlowStaked,
        stFlowToken.totalSupply,
        LiquidStaking.protocolFeePercent
    ]
}
