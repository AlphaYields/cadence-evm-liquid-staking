import "FungibleToken"
import "FlowToken"
import "FlowIDTableStaking"
import "stFlowToken"

/// Minimal liquid staking protocol for FLOW.
/// Users stake FLOW and receive stFlow. Rewards auto-compound each epoch,
/// increasing the FLOW-per-stFlow price. Unstaking follows the standard
/// epoch cooldown (~1 week).
access(all) contract LiquidStaking {

    // ──── State ────

    /// Total FLOW the protocol controls (staked + committed + compounded rewards − unstaked).
    /// Drives the stFlow price: price = totalFlowStaked / stFlowToken.totalSupply.
    access(all) var totalFlowStaked: UFix64

    /// Protocol fee taken from each epoch's rewards (e.g. 0.1 = 10%).
    access(all) var protocolFeePercent: UFix64

    /// Monotonic counter for unstake request IDs.
    access(all) var unstakeRequestCount: UInt64

    /// Emergency pause flag.
    access(all) var isPaused: Bool

    // ──── Paths ────

    access(all) let AdminStoragePath: StoragePath
    access(all) let DelegatorStoragePath: StoragePath
    access(all) let WithdrawPoolStoragePath: StoragePath

    // ──── Unstake tracking ────

    /// Requests waiting for the epoch boundary to process.
    access(self) let pendingUnstakes: {UInt64: UnstakeRequest}

    /// Requests whose FLOW has been withdrawn from the delegator and is ready to claim.
    access(self) let readyUnstakes: {UInt64: UnstakeRequest}

    // ──── Events ────

    access(all) event Staked(flowAmount: UFix64, stFlowAmount: UFix64)
    access(all) event UnstakeRequested(id: UInt64, stFlowAmount: UFix64, flowAmount: UFix64)
    access(all) event UnstakeClaimed(id: UInt64, flowAmount: UFix64)
    /// Keeper pulled FLOW from the withdraw pool for an EVM fulfillment path (not Cadence cashout).
    access(all) event UnstakeFlowRoutedToEvm(id: UInt64, flowAmount: UFix64)
    access(all) event RewardsCompounded(rewardAmount: UFix64, feeAmount: UFix64)
    access(all) event ProtocolFeeUpdated(oldFee: UFix64, newFee: UFix64)
    access(all) event Paused()
    access(all) event Unpaused()

    // ──── Structs ────

    access(all) struct UnstakeRequest {
        access(all) let requester: Address
        access(all) let flowAmount: UFix64
        access(all) let stFlowAmount: UFix64

        init(requester: Address, flowAmount: UFix64, stFlowAmount: UFix64) {
            self.requester = requester
            self.flowAmount = flowAmount
            self.stFlowAmount = stFlowAmount
        }
    }

    // ──── Price helpers ────

    /// How much FLOW one stFlow is worth.
    access(all) view fun flowPerStFlow(): UFix64 {
        if stFlowToken.totalSupply == 0.0 { return 1.0 }
        return self.totalFlowStaked / stFlowToken.totalSupply
    }

    /// How much stFlow you get per FLOW.
    access(all) view fun stFlowPerFlow(): UFix64 {
        if self.totalFlowStaked == 0.0 { return 1.0 }
        return stFlowToken.totalSupply / self.totalFlowStaked
    }

    // ──── User functions ────

    /// Stake FLOW → receive stFlow at the current exchange rate.
    access(all) fun stake(from: @FlowToken.Vault): @stFlowToken.Vault {
        pre { !self.isPaused: "Protocol is paused" }

        let flowAmount = from.balance
        assert(flowAmount > 0.0, message: "Must stake > 0 FLOW")

        let stFlowAmount = flowAmount * self.stFlowPerFlow()

        let delegator = self.account.storage
            .borrow<auth(FlowIDTableStaking.DelegatorOwner) &FlowIDTableStaking.NodeDelegator>(
                from: self.DelegatorStoragePath
            ) ?? panic("No delegator configured")

        delegator.delegateNewTokens(from: <-from)

        self.totalFlowStaked = self.totalFlowStaked + flowAmount

        emit Staked(flowAmount: flowAmount, stFlowAmount: stFlowAmount)

        return <- stFlowToken.mintTokens(amount: stFlowAmount)
    }

    /// Burn stFlow → create an unstake request. Returns a request ID
    /// the caller can use to claim FLOW after the epoch processes.
    access(all) fun unstake(from: @stFlowToken.Vault, requester: Address): UInt64 {
        pre { !self.isPaused: "Protocol is paused" }

        let stFlowAmount = from.balance
        assert(stFlowAmount > 0.0, message: "Must unstake > 0 stFlow")

        let flowAmount = stFlowAmount * self.flowPerStFlow()

        stFlowToken.burnTokens(from: <-from)

        let delegator = self.account.storage
            .borrow<auth(FlowIDTableStaking.DelegatorOwner) &FlowIDTableStaking.NodeDelegator>(
                from: self.DelegatorStoragePath
            ) ?? panic("No delegator configured")

        delegator.requestUnstaking(amount: flowAmount)

        self.totalFlowStaked = self.totalFlowStaked - flowAmount

        let id = self.unstakeRequestCount
        self.pendingUnstakes[id] = UnstakeRequest(
            requester: requester,
            flowAmount: flowAmount,
            stFlowAmount: stFlowAmount
        )
        self.unstakeRequestCount = id + 1

        emit UnstakeRequested(id: id, stFlowAmount: stFlowAmount, flowAmount: flowAmount)
        return id
    }

    /// Claim FLOW from a fulfilled unstake request. Caller must be the original requester.
    access(all) fun cashout(requestId: UInt64, receiver: &{FungibleToken.Receiver}) {
        let request = self.readyUnstakes.remove(key: requestId)
            ?? panic("Request not found or not yet ready")

        let pool = self.account.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                from: self.WithdrawPoolStoragePath
            ) ?? panic("Withdraw pool not found")

        receiver.deposit(from: <- pool.withdraw(amount: request.flowAmount))

        emit UnstakeClaimed(id: requestId, flowAmount: request.flowAmount)
    }

    // ──── Read helpers ────

    access(all) view fun getPendingUnstake(id: UInt64): UnstakeRequest? {
        return self.pendingUnstakes[id]
    }

    access(all) view fun getReadyUnstake(id: UInt64): UnstakeRequest? {
        return self.readyUnstakes[id]
    }

    access(all) fun getDelegatorInfo(): FlowIDTableStaking.DelegatorInfo {
        let delegator = self.account.storage
            .borrow<&FlowIDTableStaking.NodeDelegator>(from: self.DelegatorStoragePath)
            ?? panic("No delegator configured")
        return FlowIDTableStaking.DelegatorInfo(
            nodeID: delegator.nodeID,
            delegatorID: delegator.id
        )
    }

    // ──── Admin ────

    access(all) resource Admin {

        /// One-time setup: register as a delegator to a node operator.
        access(all) fun registerDelegator(nodeID: String, from: @FlowToken.Vault) {
            let delegator <- FlowIDTableStaking.registerNewDelegator(
                nodeID: nodeID,
                tokensCommitted: <-from
            )
            LiquidStaking.account.storage.save(
                <-delegator,
                to: LiquidStaking.DelegatorStoragePath
            )
        }

        /// Called by keeper once per epoch.
        /// 1. Withdraw rewards  2. Take protocol fee  3. Restake remainder
        access(all) fun compoundRewards() {
            let delegator = LiquidStaking.account.storage
                .borrow<auth(FlowIDTableStaking.DelegatorOwner) &FlowIDTableStaking.NodeDelegator>(
                    from: LiquidStaking.DelegatorStoragePath
                ) ?? panic("No delegator configured")

            let info = FlowIDTableStaking.DelegatorInfo(
                nodeID: delegator.nodeID,
                delegatorID: delegator.id
            )
            let rewardAmount = info.tokensRewarded
            if rewardAmount <= 0.0 { return }

            let feeAmount = rewardAmount * LiquidStaking.protocolFeePercent
            let restakeAmount = rewardAmount - feeAmount

            if feeAmount > 0.0 {
                let feeVault <- delegator.withdrawRewardedTokens(amount: feeAmount)
                let treasury = LiquidStaking.account.storage
                    .borrow<&{FungibleToken.Receiver}>(from: /storage/flowTokenVault)
                    ?? panic("Treasury vault not found")
                treasury.deposit(from: <-feeVault)
            }

            if restakeAmount > 0.0 {
                delegator.delegateRewardedTokens(amount: restakeAmount)
                LiquidStaking.totalFlowStaked = LiquidStaking.totalFlowStaked + restakeAmount
            }

            emit RewardsCompounded(rewardAmount: rewardAmount, feeAmount: feeAmount)
        }

        /// Called by keeper after epoch boundary.
        /// Withdraws newly-unstaked tokens from the delegator into the withdraw pool
        /// and moves pending requests to ready.
        access(all) fun processUnstakes() {
            let delegator = LiquidStaking.account.storage
                .borrow<auth(FlowIDTableStaking.DelegatorOwner) &FlowIDTableStaking.NodeDelegator>(
                    from: LiquidStaking.DelegatorStoragePath
                ) ?? panic("No delegator configured")

            let info = FlowIDTableStaking.DelegatorInfo(
                nodeID: delegator.nodeID,
                delegatorID: delegator.id
            )
            let unstakedAmount = info.tokensUnstaked
            if unstakedAmount <= 0.0 { return }

            let withdrawn <- delegator.withdrawUnstakedTokens(amount: unstakedAmount)

            let pool = LiquidStaking.account.storage
                .borrow<&{FungibleToken.Receiver}>(from: LiquidStaking.WithdrawPoolStoragePath)
                ?? panic("Withdraw pool not found")
            pool.deposit(from: <-withdrawn)

            for id in LiquidStaking.pendingUnstakes.keys {
                if let request = LiquidStaking.pendingUnstakes.remove(key: id) {
                    LiquidStaking.readyUnstakes[id] = request
                }
            }
        }

        /// Withdraw FLOW for a **ready** unstake into the keeper transaction so it can be
        /// bridged/deposited to the COA and paid out on Flow EVM (`LSPVault.fulfillUnstakeRequest`).
        /// Removes the entry from `readyUnstakes` (same net effect on Cadence as `cashout` for that ID).
        access(all) fun finalizeUnstakeForEvm(requestId: UInt64): @FlowToken.Vault {
            let request = LiquidStaking.readyUnstakes.remove(key: requestId)
                ?? panic("Unstake request not ready or unknown id")

            let pool = LiquidStaking.account.storage
                .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                    from: LiquidStaking.WithdrawPoolStoragePath
                ) ?? panic("Withdraw pool not found")

            assert(pool.balance >= request.flowAmount, message: "Withdraw pool underflow")

            emit UnstakeFlowRoutedToEvm(id: requestId, flowAmount: request.flowAmount)
            return <- pool.withdraw(amount: request.flowAmount) as! @FlowToken.Vault
        }

        access(all) fun setProtocolFee(newFee: UFix64) {
            pre { newFee <= 1.0: "Fee cannot exceed 100%" }
            let oldFee = LiquidStaking.protocolFeePercent
            LiquidStaking.protocolFeePercent = newFee
            emit ProtocolFeeUpdated(oldFee: oldFee, newFee: newFee)
        }

        access(all) fun setPaused(paused: Bool) {
            LiquidStaking.isPaused = paused
            if paused { emit Paused() } else { emit Unpaused() }
        }
    }

    // ──── Init ────

    init() {
        self.totalFlowStaked = 0.0
        self.protocolFeePercent = 0.1
        self.unstakeRequestCount = 0
        self.isPaused = false
        self.pendingUnstakes = {}
        self.readyUnstakes = {}

        self.AdminStoragePath = /storage/liquidStakingAdmin
        self.DelegatorStoragePath = /storage/liquidStakingDelegator
        self.WithdrawPoolStoragePath = /storage/liquidStakingWithdrawPool

        self.account.storage.save(<- create Admin(), to: self.AdminStoragePath)

        let pool <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
        self.account.storage.save(<-pool, to: self.WithdrawPoolStoragePath)
    }
}
