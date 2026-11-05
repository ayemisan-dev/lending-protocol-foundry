// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {LendingPool} from "../../src/core/LendingPool.sol";
import {ProtocolConfig} from "../../src/core/ProtocolConfig.sol";
import {RiskEngine} from "../../src/core/RiskEngine.sol";
import {OracleReader} from "../../src/oracles/OracleReader.sol";
import {ILendingPool} from "../../src/interfaces/ILendingPool.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockAggregatorV3} from "../../src/mocks/MockAggregatorV3.sol";

contract LendingPoolFuzzTest is Test {
    LendingPool internal pool;
    ProtocolConfig internal config;
    RiskEngine internal riskEngine;
    OracleReader internal oracleReader;
    MockERC20 internal asset;
    MockAggregatorV3 internal feed;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    function setUp() public {
        asset = new MockERC20("Mock USD", "mUSD");
        pool = new LendingPool(owner);
        config = new ProtocolConfig(owner);
        oracleReader = new OracleReader(owner, 1 days);
        feed = new MockAggregatorV3(8, 1e8, 1, block.timestamp, 1);

        vm.startPrank(owner);
        config.configureAsset(address(asset), true, 8000, 8500, 500);
        oracleReader.setPriceFeed(address(asset), address(feed));
        riskEngine = new RiskEngine(address(config), address(oracleReader), address(pool));
        pool.setProtocolConfig(address(config));
        pool.setRiskEngine(address(riskEngine));
        vm.stopPrank();
    }

    // deposit moves exactly amount and records it exactly.
    function testFuzz_DepositUpdatesAccountingExactly(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 ether);
        asset.mint(alice, amount);
        vm.startPrank(alice);
        asset.approve(address(pool), amount);
        uint256 poolBefore = asset.balanceOf(address(pool));
        pool.deposit(address(asset), amount);
        vm.stopPrank();

        ILendingPool.UserPosition memory pos = pool.getUserPosition(alice, address(asset));
        assertEq(pos.supplied, amount);
        assertEq(asset.balanceOf(address(pool)), poolBefore + amount);
    }

    // borrow is all-or-nothing.
    function testFuzz_BorrowIsAllOrNothing(uint256 collateralAmount, uint256 borrowAmount) public {
        collateralAmount = bound(collateralAmount, 1, 1_000_000 ether);
        borrowAmount = bound(borrowAmount, 1, 1_000_000 ether);

        asset.mint(address(pool), 10_000_000 ether);
        asset.mint(alice, collateralAmount);

        vm.startPrank(alice);
        asset.approve(address(pool), collateralAmount);
        pool.deposit(address(asset), collateralAmount);

        uint256 aliceBalBefore = asset.balanceOf(alice);
        uint256 poolBalBefore = asset.balanceOf(address(pool));

        try pool.borrow(address(asset), borrowAmount) {
            ILendingPool.UserPosition memory pos = pool.getUserPosition(alice, address(asset));
            assertEq(pos.borrowed, borrowAmount);
            assertEq(asset.balanceOf(alice), aliceBalBefore + borrowAmount);
            assertEq(asset.balanceOf(address(pool)), poolBalBefore - borrowAmount);
        } catch {
            ILendingPool.UserPosition memory pos = pool.getUserPosition(alice, address(asset));
            assertEq(pos.borrowed, 0);
            assertEq(asset.balanceOf(alice), aliceBalBefore);
            assertEq(asset.balanceOf(address(pool)), poolBalBefore);
        }
        vm.stopPrank();
    }

    // withdraw is all-or-nothing and never breaks HF >= 1.
    function testFuzz_WithdrawIsAllOrNothing(uint256 suppliedAmount, uint256 borrowAmount, uint256 withdrawAmount)
        public
    {
        suppliedAmount = bound(suppliedAmount, 1 ether, 1_000_000 ether);
        // Bound the borrow to LTV so the borrow step itself always succeeds.
        borrowAmount = bound(borrowAmount, 0, (suppliedAmount * 8000) / 10_000);
        withdrawAmount = bound(withdrawAmount, 1, suppliedAmount);

        asset.mint(address(pool), 10_000_000 ether);
        asset.mint(alice, suppliedAmount);

        vm.startPrank(alice);
        asset.approve(address(pool), suppliedAmount);
        pool.deposit(address(asset), suppliedAmount);

        if (borrowAmount > 0) {
            pool.borrow(address(asset), borrowAmount);
        }

        uint256 aliceBalBefore = asset.balanceOf(alice);
        uint256 poolBalBefore = asset.balanceOf(address(pool));

        try pool.withdraw(address(asset), withdrawAmount) {
            ILendingPool.UserPosition memory pos = pool.getUserPosition(alice, address(asset));
            assertEq(pos.supplied, suppliedAmount - withdrawAmount);
            assertEq(asset.balanceOf(alice), aliceBalBefore + withdrawAmount);
            assertEq(asset.balanceOf(address(pool)), poolBalBefore - withdrawAmount);

            // Post-condition: no successful withdraw may leave HF below 1.
            if (pos.borrowed > 0) {
                assertGe(riskEngine.getHealthFactor(alice), 1e18);
            }
        } catch {
            ILendingPool.UserPosition memory pos = pool.getUserPosition(alice, address(asset));
            assertEq(pos.supplied, suppliedAmount);
            assertEq(asset.balanceOf(alice), aliceBalBefore);
            assertEq(asset.balanceOf(address(pool)), poolBalBefore);
        }
        vm.stopPrank();
    }

    // liquidation arithmetic is exact and bounded.
    function testFuzz_LiquidatePreservesAccounting(uint256 debtToCover) public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowedAmount = 80 ether;

        asset.mint(address(pool), borrowedAmount);
        asset.mint(alice, suppliedAmount);

        vm.startPrank(alice);
        asset.approve(address(pool), suppliedAmount);
        pool.deposit(address(asset), suppliedAmount);
        pool.borrow(address(asset), borrowedAmount);
        vm.stopPrank();

        // Tighten parameters so alice becomes liquidatable (HF < 1).
        vm.prank(owner);
        config.configureAsset(address(asset), true, 7000, 7500, 500);

        debtToCover = bound(debtToCover, 1, borrowedAmount);

        address liquidator = makeAddr("liquidator");
        asset.mint(liquidator, debtToCover);

        vm.startPrank(liquidator);
        asset.approve(address(pool), debtToCover);
        pool.liquidate(alice, address(asset), address(asset), debtToCover);
        vm.stopPrank();

        // seized amount is exactly debtToCover * 1.05 with floor rounding.
        uint256 expectedSeize = (debtToCover * 10_500) / 10_000;

        ILendingPool.UserPosition memory pos = pool.getUserPosition(alice, address(asset));
        assertEq(pos.borrowed, borrowedAmount - debtToCover);
        assertEq(pos.supplied, suppliedAmount - expectedSeize);
        assertEq(asset.balanceOf(liquidator), expectedSeize);
    }

    // liquidation arithmetic is exact and bounded for any bonusBps
    // in [0, 5000] and any debtToCover that collateral can cover.
    function testFuzz_LiquidateBonusBoundary(uint256 debtToCover, uint256 bonusBps) public {
        bonusBps = bound(bonusBps, 0, 5000); // up to 50%
        uint256 suppliedAmount = 1000 ether;
        uint256 borrowedAmount = 800 ether;

        asset.mint(address(pool), borrowedAmount);
        asset.mint(alice, suppliedAmount);

        vm.startPrank(alice);
        asset.approve(address(pool), suppliedAmount);
        pool.deposit(address(asset), suppliedAmount);
        pool.borrow(address(asset), borrowedAmount);
        vm.stopPrank();

        // Tighten config so HF = 1000 * 0.75 / 800 = 0.9375 < 1 → liquidatable.
        // Also vary the bonus across the fuzz input.
        vm.prank(owner);
        config.configureAsset(address(asset), true, 7000, 7500, bonusBps);

        // Cap debtToCover so the seized collateral never exceeds suppliedAmount.
        uint256 maxDebt = (suppliedAmount * 10_000) / (10_000 + bonusBps);
        uint256 upper = borrowedAmount < maxDebt ? borrowedAmount : maxDebt;
        debtToCover = bound(debtToCover, 1, upper);

        address liquidator = makeAddr("liquidator");
        asset.mint(liquidator, debtToCover);

        vm.startPrank(liquidator);
        asset.approve(address(pool), debtToCover);
        pool.liquidate(alice, address(asset), address(asset), debtToCover);
        vm.stopPrank();

        // price = $1, 18-decimal, so debt USD value == debtToCover.
        // All three rounding steps are floor, so expectedSeize is exact.
        uint256 expectedSeize = (debtToCover * (10_000 + bonusBps)) / 10_000;

        ILendingPool.UserPosition memory pos = pool.getUserPosition(alice, address(asset));
        assertEq(pos.borrowed, borrowedAmount - debtToCover);
        assertEq(pos.supplied, suppliedAmount - expectedSeize);
        assertEq(asset.balanceOf(liquidator), expectedSeize);
    }
}
