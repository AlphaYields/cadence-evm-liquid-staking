// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { LSPVault } from "../src/LSPVault.sol";
import { FlowReceipt } from "../src/FlowReceipt.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { ILSPVault } from "../src/interfaces/ILSPVault.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract LSPVaultTest is Test {
    LSPVault public lspVault;
    FlowReceipt public flowReceipt;
    MockERC20 public stFlow;
    address public coa = address(0x1);
    address public staker = address(0x2);

    function setUp() public {
        stFlow = new MockERC20();

        vm.prank(coa);
        lspVault = new LSPVault(address(stFlow));
        flowReceipt = FlowReceipt(lspVault.FLOW_RECEIPT());

        vm.deal(coa, 10_000 ether);
        vm.deal(staker, 10_000 ether);

        vm.prank(coa);
        lspVault.updateConfig(ILSPVault.Config({
            minStakeAmount: 0.01 ether,
            isStakingPaused: false,
            isUnstakingPaused: false,
            protocolFee: 0
        }));

        vm.prank(coa);
        lspVault.syncRate(1 ether);
    }

    function testRequestStakeRevertsIfStakingIsPaused() public {
        vm.prank(coa);
        lspVault.updateConfig(ILSPVault.Config({
            minStakeAmount: 0.01 ether,
            isStakingPaused: true,
            isUnstakingPaused: false,
            protocolFee: 0
        }));
        vm.prank(staker);
        vm.expectRevert(ILSPVault.StakingPaused.selector);
        lspVault.requestStake{value: 0.1 ether}();
    }

    function testRequestStakeRevertsIfAmountIsLessThanMinStakeAmount() public {
        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(ILSPVault.MinAmountNotMet.selector, 0.01 ether, 0.009 ether));
        lspVault.requestStake{value: 0.009 ether}();
    }

    function testRequestUnstakeRevertsIfUnstakingIsPaused() public {
        vm.prank(coa);
        lspVault.updateConfig(ILSPVault.Config({
            minStakeAmount: 0.01 ether,
            isStakingPaused: false,
            isUnstakingPaused: true,
            protocolFee: 0
        }));
        vm.prank(staker);
        vm.expectRevert(ILSPVault.UnstakingPaused.selector);
        lspVault.requestUnstake(100 ether);
    }

    function testFulfillStakeRequestRevertsIfRequestIsNotPending() public {
        vm.prank(coa);
        vm.expectRevert(ILSPVault.InvalidRequest.selector);
        lspVault.fulfillStakeRequest(1);
    }

    function testFulfillUnstakeRequestRevertsIfRequestIsNotPending() public {
        vm.prank(coa);
        vm.expectRevert(ILSPVault.InvalidRequest.selector);
        lspVault.fulfillUnstakeRequest(1, 100 ether);
    }

    function testRequestStake() public {
        vm.prank(staker);
        lspVault.requestStake{value: 1000 ether}();
        assertEq(flowReceipt.balanceOf(staker), 1000e18);
        assertEq(address(lspVault).balance, 1000 ether);
    }

    function testRequestUnstake() public {
        stFlow.mint(staker, 100 ether);
        vm.startPrank(staker);
        stFlow.approve(address(lspVault), 100 ether);
        lspVault.requestUnstake(100 ether);
        vm.stopPrank();

        assertEq(stFlow.balanceOf(address(lspVault)), 100 ether);
        assertEq(stFlow.balanceOf(staker), 0);
    }

    function testFulfillStakeRequest() public {
        vm.prank(staker);
        lspVault.requestStake{value: 100 ether}();

        // COA bridges stFlow into the vault, then fulfills
        stFlow.mint(address(lspVault), 100 ether);
        vm.prank(coa);
        lspVault.fulfillStakeRequest(1);

        assertEq(stFlow.balanceOf(staker), 100 ether);
        assertEq(flowReceipt.balanceOf(staker), 0);
    }

    function testFulfillUnstakeRequest() public {
        stFlow.mint(staker, 100 ether);
        vm.startPrank(staker);
        stFlow.approve(address(lspVault), 100 ether);
        lspVault.requestUnstake(100 ether);
        vm.stopPrank();

        // COA deposits FLOW into vault, then fulfills
        vm.deal(address(lspVault), 100 ether);
        uint256 balBefore = staker.balance;
        vm.prank(coa);
        lspVault.fulfillUnstakeRequest(1, 100 ether);

        assertEq(staker.balance, balBefore + 100 ether);
    }

    function testUpdateConfig() public {
        vm.prank(coa);
        lspVault.updateConfig(ILSPVault.Config({
            minStakeAmount: 0.01 ether,
            isStakingPaused: true,
            isUnstakingPaused: true,
            protocolFee: 0
        }));
        assertEq(lspVault.getConfig().isStakingPaused, true);
        assertEq(lspVault.getConfig().isUnstakingPaused, true);
        assertEq(lspVault.getConfig().protocolFee, 0);
        assertEq(lspVault.getConfig().minStakeAmount, 0.01 ether);
    }

    function testSyncRate() public {
        vm.prank(coa);
        lspVault.syncRate(2 ether);
        assertEq(lspVault.getRate(), 2 ether);
    }

    function testUpdateConfigRevertsIfNotOwner() public {
        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, staker));
        lspVault.updateConfig(ILSPVault.Config({
            minStakeAmount: 0.01 ether,
            isStakingPaused: true,
            isUnstakingPaused: true,
            protocolFee: 0
        }));
    }

    function testSyncRateRevertsIfNotOwner() public {
        vm.prank(staker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, staker));
        lspVault.syncRate(2 ether);
    }

    function testFulfillUnstakeRevertsIfLowBalance() public {
        stFlow.mint(staker, 100 ether);
        vm.startPrank(staker);
        stFlow.approve(address(lspVault), 100 ether);
        lspVault.requestUnstake(100 ether);
        vm.stopPrank();

        // COA deposits FLOW into vault, then fulfills
        vm.deal(address(lspVault), 99 ether);
        vm.prank(coa);
        vm.expectRevert(abi.encodeWithSelector(ILSPVault.NativeTransferFailed.selector));
        lspVault.fulfillUnstakeRequest(1, 100 ether);
    }

    function testWithdrawPendingStakeNative_movesWeiToOwner() public {
        vm.prank(staker);
        lspVault.requestStake{value: 50 ether}();

        uint256 coaBefore = coa.balance;
        uint256 vaultBefore = address(lspVault).balance;

        vm.prank(coa);
        uint256 withdrawn = lspVault.withdrawPendingStakeNative(1);

        assertEq(withdrawn, 50 ether);
        assertEq(coa.balance, coaBefore + 50 ether);
        assertEq(address(lspVault).balance, vaultBefore - 50 ether);

        (ILSPVault.RequestStatus status,, uint256 amount, uint256 flowWei) = lspVault.stakeRequests(1);
        assertEq(uint256(status), uint256(ILSPVault.RequestStatus.PENDING));
        assertEq(flowWei, 0);
        assertEq(amount, 50 ether);
    }

    function testWithdrawPendingUnstakeStFlow_movesTokensToOwner() public {
        stFlow.mint(staker, 40 ether);
        vm.startPrank(staker);
        stFlow.approve(address(lspVault), type(uint256).max);
        lspVault.requestUnstake(40 ether);
        vm.stopPrank();

        vm.prank(coa);
        uint256 pulled = lspVault.withdrawPendingUnstakeStFlow(1);

        assertEq(pulled, 40 ether);
        assertEq(stFlow.balanceOf(coa), 40 ether);
        assertEq(stFlow.balanceOf(address(lspVault)), 0);
    }
}