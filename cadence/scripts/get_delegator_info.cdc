import "LiquidStaking"

/// Returns the delegator info (all token buckets) for the protocol's delegator.
access(all) fun main(): LiquidStaking.UnstakeRequest? {
    return LiquidStaking.getReadyUnstake(id: 0)
}
