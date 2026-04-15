// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILSPVault {
    // Structs
    enum RequestStatus {
        NONE,
        PENDING,
        FULFILLED
    }

    struct StakeRequest {
        RequestStatus status;
        address user;
        uint256 amount;
    }

    struct UnstakeRequest {
        RequestStatus status;
        address user;
        uint256 amount;
    }

    struct Config {
        uint256 minStakeAmount;
        bool isStakingPaused;
        bool isUnstakingPaused;
        uint256 protocolFee;
    }
    
    // Errors
    error MinAmountNotMet(uint256 minAmount, uint256 amount);
    error StakingPaused();
    error UnstakingPaused();
    error InvalidRequest();
    error NativeTransferFailed();

    // Events
    event StakeRequested(uint256 indexed id, address indexed user, uint256 amount);
    event UnstakeRequested(uint256 indexed id, address indexed user, uint256 amount);
    event StakeFulfilled(uint256 indexed id, address indexed user, uint256 amount);
    event UnstakeFulfilled(uint256 indexed id, address indexed user, uint256 amount);
    event RateUpdated(uint256 oldRate, uint256 newRate);
    event ConfigUpdated(Config oldConfig, Config newConfig);

    // Functions
    function requestStake() external payable returns (uint256);
    function requestUnstake(uint256 _amount) external returns (uint256);
    function fulfillStakeRequest(uint256 _id) external;
    function fulfillUnstakeRequest(uint256 _id, uint256 _flowAmount) external;
    function updateConfig(Config calldata _config) external;
    function syncRate(uint256 _newRate) external;
    function getConfig() external view returns (Config memory);
    function getRate() external view returns (uint256);
}