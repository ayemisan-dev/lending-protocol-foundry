//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {MockLendingPool} from "../../src/mocks/MockLendingPool.sol";

contract MockLendingPoolTest is Test {
    MockLendingPool internal pool;
    address internal alice = makeAddr("alice");
    address internal asset = makeAddr("asset");

    function setUp() public {
        pool = new MockLendingPool();
    }

    function test_DepositUpdatesSupplied() public {
        uint256 amount = 10 ether;

        vm.prank(alice);
        pool.deposit(asset, amount);

        MockLendingPool.UserPosition memory position = pool.getUserPosition(alice, asset);

        assertEq(position.supplied, amount);
        assertEq(position.borrowed, 0);
    }

    function test_DepositTracksPositionsPerAsset() public {
        address eth = makeAddr("eth");
        address usdc = makeAddr("usdc");

        uint256 ethAmount = 10 ether;
        uint256 usdcAmount = 5_000e6;

        //user deposit
        vm.startPrank(alice);
        pool.deposit(eth, ethAmount);
        pool.deposit(usdc, usdcAmount);
        vm.stopPrank();

        //get user positions
        MockLendingPool.UserPosition memory ethPosition = pool.getUserPosition(alice, eth);
        MockLendingPool.UserPosition memory usdcPosition = pool.getUserPosition(alice, usdc);

        assertEq(ethPosition.supplied, ethAmount);
        assertEq(ethPosition.borrowed, 0);
        assertEq(usdcPosition.supplied, usdcAmount);
        assertEq(usdcPosition.borrowed, 0);
    }

    function test_DepositAccumulatesSupplied() public {
        uint256 firstAmount = 10 ether;
        uint256 secondAmount = 5 ether;

        vm.startPrank(alice);

        pool.deposit(asset, firstAmount);
        pool.deposit(asset, secondAmount);

        vm.stopPrank();

        MockLendingPool.UserPosition memory position = pool.getUserPosition(alice, asset);

        assertEq(position.supplied, firstAmount + secondAmount);
        assertEq(position.borrowed, 0);
    }

    function test_WithdrawReducesSupplied() public {
        uint256 depositAmount = 10 ether;
        uint256 withdrawAmount = 4 ether;

        vm.startPrank(alice);
        pool.deposit(asset, depositAmount);
        pool.withdraw(asset, withdrawAmount);
        vm.stopPrank();

        MockLendingPool.UserPosition memory position = pool.getUserPosition(alice, asset);

        // Withdrawal should reduce the supplied balance
        assertEq(position.supplied, depositAmount - withdrawAmount);
        assertEq(position.borrowed, 0);
    }

    function test_WithdrawRevertsWhenAmountExceedsSupplied() public {
        uint256 depositAmount = 10 ether;
        uint256 withdrawAmount = 15 ether;

        vm.startPrank(alice);
        pool.deposit(asset, depositAmount);
        vm.expectRevert(MockLendingPool.InsufficientSupply.selector);
        pool.withdraw(asset, withdrawAmount);
        vm.stopPrank();

        MockLendingPool.UserPosition memory position = pool.getUserPosition(alice, asset);

        // Failed withdrawal must not modify the supplied balance
        assertEq(position.supplied, depositAmount);
        assertEq(position.borrowed, 0);
    }

    function test_WithdrawRevertsWhenAmountIsZero() public {
        vm.startPrank(alice);

        pool.deposit(asset, 10 ether);

        vm.expectRevert(MockLendingPool.InvalidAmount.selector);
        pool.withdraw(asset, 0);

        vm.stopPrank();

        MockLendingPool.UserPosition memory position = pool.getUserPosition(alice, asset);

        // A zero-amount withdrawal must not modify the position
        assertEq(position.supplied, 10 ether);
        assertEq(position.borrowed, 0);
    }
}
