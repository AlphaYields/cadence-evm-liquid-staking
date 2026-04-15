// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title FlowReceipt
 * @notice A contract that allows the owner to mint and burn stFlow Receipts
 * @dev Intended to be deployed by the Staking Vault, to emit stFlow Receipts to users when they stake Flow.
 *      The receipt tokens will be burned by the Flow COA after the keeper bot processes the stake on Cadence.
*/
contract FlowReceipt is Ownable, ERC20 {
    constructor() Ownable(msg.sender) ERC20("stFlow Receipt", "stFR") {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}