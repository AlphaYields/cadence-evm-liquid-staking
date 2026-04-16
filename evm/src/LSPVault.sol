// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FlowReceipt } from "./FlowReceipt.sol";
import { ILSPVault } from "./interfaces/ILSPVault.sol";

/**
 * @title LSPVault
 * @notice A contract that allows users to deposit/stake/unstake/withdraw Flow on the Cadence LSP.
 * @dev Intended to be deployed by the Flow COA, to allow keeper to interact through COA.
*/
contract LSPVault is Ownable, ILSPVault {
    using SafeERC20 for IERC20;

    /// Scale factor for token maths.
    uint256 public constant PRECISION = 1e18;

    /// Address of the Flow receipt token.
    FlowReceipt public immutable FLOW_RECEIPT;

    /// Address of the staked Flow token.
    address public immutable ST_FLOW_ADDRESS;

    /// Stake requests.
    mapping(uint256 => StakeRequest) public stakeRequests;

    /// Unstake requests.
    mapping(uint256 => UnstakeRequest) public unstakeRequests;

    /// Stake request IDs.
    uint256 public stakeRequestCount = 1;

    /// Unstake request IDs.
    uint256 public unstakeRequestCount = 1;

    /// LSP configuration.
    Config private _config;

    /// stFlow to Flow rate, starting with 1 to 1.
    uint256 private _rate = 1e18;

    /// Deploy receipt to gain minter/burner rights.
    constructor(address _stFlowAddress) Ownable(msg.sender) {
        ST_FLOW_ADDRESS = _stFlowAddress;
        FLOW_RECEIPT = new FlowReceipt();
    }

    /// Accept FLOW sent by keeper (COA) for unstake fulfillment.
    receive() external payable {}

      /////////////////////////////////////////////////////////////////
     //                       user functions                        //
    /////////////////////////////////////////////////////////////////

    /**
     * Requests a stake of Flow to the LSP on cadence. Mints receipts tokens to the user.
     * @custom:throws StakingPaused if the staking is paused.
     * @custom:throws MinAmountNotMet if the amount is less than the minimum stake amount.
     */
    function requestStake() external payable returns (uint256) {
        if (_config.isStakingPaused) revert StakingPaused();
        if (msg.value < _config.minStakeAmount) revert MinAmountNotMet(_config.minStakeAmount, msg.value);

        uint256 stFlowAmount = msg.value * PRECISION / _rate;

        uint256 requestId = stakeRequestCount;

        stakeRequests[requestId] = StakeRequest({
            status: RequestStatus.PENDING,
            user: msg.sender,
            amount: stFlowAmount,
            flowWei: msg.value
        });

        FLOW_RECEIPT.mint(msg.sender, stFlowAmount);

        emit StakeRequested(stakeRequestCount, msg.sender, stFlowAmount);

        unchecked { stakeRequestCount++; }

        return requestId;
    }

    /**
     * Requests an unstake of stFlow. Locks stFlow in the vault for the keeper to bridge
     * to Cadence and process through the LSP.
     * @param _amount amount of stFlow to unstake.
     * @custom:throws UnstakingPaused if the unstaking is paused.
     */
    function requestUnstake(uint256 _amount) external returns (uint256) {
        if (_config.isUnstakingPaused) revert UnstakingPaused();

        IERC20(ST_FLOW_ADDRESS).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 requestId = unstakeRequestCount;

        unstakeRequests[requestId] = UnstakeRequest({
            status: RequestStatus.PENDING,
            user: msg.sender,
            amount: _amount
        });

        emit UnstakeRequested(unstakeRequestCount, msg.sender, _amount);

        unchecked { unstakeRequestCount++; }

        return requestId;
    }

      /////////////////////////////////////////////////////////////////
     //                       COA functions                         //
    /////////////////////////////////////////////////////////////////

    /// Restricted to COA, which updates the LSP config to represent it correctly on EVM side.
    function updateConfig(Config calldata _newConfig) external onlyOwner {
        Config memory oldConfig = _config;
        _config = _newConfig;
        emit ConfigUpdated(oldConfig, _config);
    }

    /// Restricted to COA function, which syncs stFlow/Flow rate on EVM side.
    function syncRate(uint256 _newRate) external onlyOwner {
        uint256 oldRate = _rate;
        _rate = _newRate;
        emit RateUpdated(oldRate, _rate);
    }

    /** 
     * Restricted to COA. Burns user's receipt and sends them stFlow (already bridged to vault by keeper).
     * @param _id id of the stake request.
     */
    function fulfillStakeRequest(uint256 _id) external onlyOwner {
        StakeRequest storage req = stakeRequests[_id];
        if (req.status != RequestStatus.PENDING) revert InvalidRequest();

        req.status = RequestStatus.FULFILLED;

        FLOW_RECEIPT.burn(req.user, req.amount);
        IERC20(ST_FLOW_ADDRESS).safeTransfer(req.user, req.amount);

        emit StakeFulfilled(_id, req.user, req.amount);
    }

    /** 
     * Restricted to COA. Marks unstake as fulfilled and sends FLOW back to user.
     * Keeper passes the actual FLOW amount returned by the Cadence LSP.
     * @param _id id of the unstake request.
     * @param _flowAmount actual FLOW returned by Cadence LSP (avoids EVM/Cadence precision mismatch).
     */
    function fulfillUnstakeRequest(uint256 _id, uint256 _flowAmount) external onlyOwner {
        UnstakeRequest storage req = unstakeRequests[_id];

        if (req.status != RequestStatus.PENDING) {
            revert InvalidRequest();
        }

        req.status = RequestStatus.FULFILLED;

        (bool success,) = req.user.call{value: _flowAmount}("");

        if (!success) {
            revert NativeTransferFailed();
        }
        
        emit UnstakeFulfilled(_id, req.user, _flowAmount);
    }

    /// @inheritdoc ILSPVault
    function withdrawPendingStakeNative(uint256 _id) external onlyOwner returns (uint256 amount) {
        StakeRequest storage req = stakeRequests[_id];
        if (req.status != RequestStatus.PENDING) revert InvalidRequest();

        amount = req.flowWei;
        if (amount == 0) revert InvalidRequest();

        req.flowWei = 0;

        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
    }

    /// @inheritdoc ILSPVault
    function withdrawPendingUnstakeStFlow(uint256 _id) external onlyOwner returns (uint256 amount) {
        UnstakeRequest storage req = unstakeRequests[_id];
        if (req.status != RequestStatus.PENDING) revert InvalidRequest();

        amount = req.amount;
        IERC20(ST_FLOW_ADDRESS).safeTransfer(msg.sender, amount);
    }

      /////////////////////////////////////////////////////////////////
     //                       view functions                        //
    /////////////////////////////////////////////////////////////////

    function getConfig() external view returns (Config memory) {
        return _config;
    }

    function getRate() external view returns (uint256) {
        return _rate;
    }
}