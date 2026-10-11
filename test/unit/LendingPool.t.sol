//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {LendingPool} from "../../src/core/LendingPool.sol";
import {ProtocolConfig} from "../../src/core/ProtocolConfig.sol";
import {OracleReader} from "../../src/oracles/OracleReader.sol";
import {RiskEngine} from "../../src/core/RiskEngine.sol";
import {MockAggregatorV3} from "../../src/mocks/MockAggregatorV3.sol";
import {FeeOnTransferMock} from "../../src/mocks/FeeOnTransferMock.sol";

contract MockERC20SixDecimals is MockERC20 {
    constructor() MockERC20("Mock USD Coin", "mUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract LendingPoolTest is Test {
    MockERC20 internal asset;
    LendingPool internal pool;
    ProtocolConfig internal config;
    OracleReader internal oracleReader;
    RiskEngine internal riskEngine;
    MockAggregatorV3 internal priceFeed;

    address internal alice = makeAddr("alice");
    address internal owner = makeAddr("owner");

    function setUp() public {
        asset = new MockERC20("Mock USD coin", "mUSDC");
        pool = new LendingPool(owner);
        config = new ProtocolConfig(owner);
        oracleReader = new OracleReader(owner, 1 days);
        priceFeed = new MockAggregatorV3(8, 1e8, 1, block.timestamp, 1);

        vm.startPrank(owner);
        config.configureAsset(
            address(asset),
            true,
            8000, // LTV: 80%
            8500, // Liquidation threshold: 85%
            500 // Liquidation bonus: 5%
        );

        oracleReader.setPriceFeed(address(asset), address(priceFeed));

        riskEngine = new RiskEngine(address(config), address(oracleReader), address(pool));

        pool.setProtocolConfig(address(config));
        pool.setRiskEngine(address(riskEngine));
        vm.stopPrank();
    }

    function test_SetupGivesAliceTokens() public {
        asset.mint(alice, 100 ether);
        assertEq(asset.balanceOf(alice), 100 ether);
    }

    function test_AliceCanApproveLendingPool() public {
        uint256 amount = 100 ether;
        address poolAddr = address(pool);
        vm.startPrank(alice);
        asset.mint(alice, amount);
        asset.approve(poolAddr, amount);
        vm.stopPrank();

        assertEq(asset.allowance(alice, poolAddr), amount);
        assertEq(asset.balanceOf(alice), 100 ether);
        assertEq(asset.balanceOf(poolAddr), 0);
    }

    function test_TransferFromMovesTokensToLendingPool() public {
        uint256 amount = 100 ether;
        vm.startPrank(alice);
        asset.mint(alice, amount);
        asset.approve(address(pool), amount);
        vm.stopPrank();

        vm.prank(address(pool));
        asset.transferFrom(alice, address(pool), amount);

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(pool)), amount);
        assertEq(asset.allowance(alice, address(pool)), 0);
    }

    function test_DepositMovesTokensAndUpdatesPosition() public {
        uint256 amount = 50 ether;
        vm.startPrank(alice);
        asset.mint(alice, 100 ether);
        asset.approve(address(pool), amount);
        pool.deposit(address(asset), amount);
        vm.stopPrank();

        assertEq(asset.balanceOf(alice), 50 ether);
        assertEq(asset.balanceOf(address(pool)), 50 ether);

        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(asset));

        assertEq(position.supplied, 50 ether);
        assertEq(position.borrowed, 0);
    }

    function test_DepositRevertsWhenAllowanceIsInsufficient() public {
        uint256 approvedAmount = 10 ether;
        uint256 depositAmount = 50 ether;

        vm.startPrank(alice);
        asset.mint(alice, 100 ether);
        asset.approve(address(pool), approvedAmount);
        vm.expectRevert();
        pool.deposit(address(asset), depositAmount);
        vm.stopPrank();

        assertEq(asset.balanceOf(alice), 100 ether);
        assertEq(asset.balanceOf(address(pool)), 0);

        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(asset));

        assertEq(position.supplied, 0);
        assertEq(position.borrowed, 0);
    }

    function test_DepositRevertsWhenAmountIsZero() public {
        vm.startPrank(alice);
        asset.mint(alice, 100 ether);
        asset.approve(address(pool), 20 ether);
        vm.expectRevert(LendingPool.InvalidAmount.selector);
        pool.deposit(address(asset), 0);
        vm.stopPrank();

        assertEq(asset.balanceOf(alice), 100 ether);
        assertEq(asset.balanceOf(address(pool)), 0);

        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(asset));

        assertEq(position.supplied, 0);
        assertEq(position.borrowed, 0);
    }

    function test_DepositRevertsWhenProtocolConfigIsNotConfigured() public {
        LendingPool unconfiguredPool = new LendingPool(owner);
        uint256 amount = 10 ether;

        asset.mint(alice, amount);

        vm.startPrank(alice);
        asset.approve(address(unconfiguredPool), amount);

        // The pool has no ProtocolConfig configured.
        vm.expectRevert(LendingPool.ProtocolConfigNotConfigured.selector);
        unconfiguredPool.deposit(address(asset), amount);

        vm.stopPrank();

        // A reverted deposit must not move tokens or create a position.
        assertEq(asset.balanceOf(alice), amount);
        assertEq(asset.balanceOf(address(unconfiguredPool)), 0);

        LendingPool.UserPosition memory position = unconfiguredPool.getUserPosition(alice, address(asset));

        assertEq(position.supplied, 0);
        assertEq(position.borrowed, 0);
    }

    function test_DepositRevertsWhenReceivedAmountIsLessThanRequested() public {
        FeeOnTransferMock feeToken = new FeeOnTransferMock();
        feeToken.mint(alice, 100 ether);
        vm.startPrank(alice);
        feeToken.approve(address(pool), 100 ether);
        vm.expectRevert();
        pool.deposit(address(feeToken), 100 ether);
        vm.stopPrank();

        assertEq(feeToken.balanceOf(alice), 100 ether);
        assertEq(feeToken.balanceOf(address(pool)), 0);

        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(feeToken));

        assertEq(position.supplied, 0);
    }

    function test_DepositRevertsWhenAssetIsDisabled() public {
        // Arrange: disable the asset.
        vm.startPrank(owner);
        LendingPool newPool = new LendingPool(owner);
        config.configureAsset(
            address(asset),
            false,
            8000, // LTV: 80%
            8500, // Liquidation threshold: 85%
            500 // Liquidation bonus: 5%
        );
        newPool.setProtocolConfig(address(config));
        vm.stopPrank();

        // Prepare Alice's tokens and allowance.
        uint256 amount = 50 ether;

        vm.startPrank(alice);
        asset.mint(alice, amount);
        asset.approve(address(pool), amount);

        // Assert: depositing a disabled asset should revert.
        vm.expectRevert(LendingPool.AssetNotEnabled.selector);
        pool.deposit(address(asset), amount);
        vm.stopPrank();
    }

    function test_WithdrawRevertsWhenRiskEngineIsNotConfigured() public {
        LendingPool unconfiguredPool = new LendingPool(owner);
        ProtocolConfig newConfig = new ProtocolConfig(owner);

        // Configure ProtocolConfig so Alice can deposit.
        vm.prank(owner);
        newConfig.configureAsset(address(asset), true, 8000, 8500, 500);

        vm.prank(owner);
        unconfiguredPool.setProtocolConfig(address(newConfig));

        uint256 amount = 10 ether;

        vm.startPrank(alice);
        asset.mint(alice, amount);
        asset.approve(address(unconfiguredPool), amount);
        unconfiguredPool.deposit(address(asset), amount);

        // RiskEngine has intentionally not been configured.
        vm.expectRevert(LendingPool.RiskEngineNotConfigured.selector);
        unconfiguredPool.withdraw(address(asset), amount);

        vm.stopPrank();

        // The failed withdrawal must preserve all state.
        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(unconfiguredPool)), amount);

        LendingPool.UserPosition memory position = unconfiguredPool.getUserPosition(alice, address(asset));

        assertEq(position.supplied, amount);
        assertEq(position.borrowed, 0);
    }

    function test_WithdrawReturnsTokensAndUpdatesPosition() public {
        uint256 amount = 50 ether;
        vm.startPrank(alice);
        asset.mint(alice, 100 ether);
        asset.approve(address(pool), amount);
        pool.deposit(address(asset), amount);
        pool.withdraw(address(asset), 20 ether);
        vm.stopPrank();

        assertEq(asset.balanceOf(alice), 70 ether);
        assertEq(asset.balanceOf(address(pool)), 30 ether);

        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(asset));

        assertEq(position.supplied, 30 ether);
        assertEq(position.borrowed, 0);
    }

    function test_WithdrawRevertsWhenAmountExceedsSupplied() public {
        uint256 suppliedAmount = 100 ether;
        uint256 withdrawAmount = 101 ether;

        vm.startPrank(alice);
        asset.mint(alice, 100 ether);
        asset.approve(address(pool), suppliedAmount);
        pool.deposit(address(asset), suppliedAmount);

        vm.expectRevert(LendingPool.InsufficientSupply.selector);
        pool.withdraw(address(asset), withdrawAmount);
        vm.stopPrank();

        uint256 aliceBalance = asset.balanceOf(alice);
        uint256 poolBalance = asset.balanceOf(address(pool));
        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(asset));

        assertEq(aliceBalance, 0);
        assertEq(poolBalance, suppliedAmount);
        assertEq(position.supplied, suppliedAmount);
    }

    function test_WithdrawRevertsWhenAmountIsZero() public {
        uint256 suppliedAmount = 100 ether;
        vm.startPrank(alice);
        asset.mint(alice, 100 ether);
        asset.approve(address(pool), suppliedAmount);
        pool.deposit(address(asset), suppliedAmount);
        vm.expectRevert(LendingPool.InvalidAmount.selector);
        pool.withdraw(address(asset), 0);
        vm.stopPrank();
    }

    function test_WithdrawRevertsWhenHealthFactorWouldFallBelowOne() public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowAmount = 70 ether;
        uint256 withdrawAmount = 30 ether;

        vm.startPrank(alice);
        asset.mint(alice, suppliedAmount);
        asset.approve(address(pool), suppliedAmount);
        pool.deposit(address(asset), suppliedAmount);

        pool.borrow(address(asset), borrowAmount);

        // Withdrawing 30 leaves 70 collateral against 70 debt.
        // At an 85% liquidation threshold, HF would be 0.85.
        vm.expectRevert();
        pool.withdraw(address(asset), withdrawAmount);
        vm.stopPrank();
    }

    function test_WithdrawRevertsWhenOraclePriceIsStale() public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowAmount = 40 ether;
        uint256 withdrawAmount = 10 ether;

        // Arrange: Alice supplies collateral and borrows against it.
        vm.startPrank(alice);
        asset.mint(alice, suppliedAmount);
        asset.approve(address(pool), suppliedAmount);
        pool.deposit(address(asset), suppliedAmount);
        pool.borrow(address(asset), borrowAmount);
        vm.stopPrank();

        // Make the oracle price stale after the borrow succeeds.
        vm.warp(1000000);
        priceFeed.setRoundData(1, block.timestamp - 1 days - 1, 1);

        uint256 aliceBalanceBefore = asset.balanceOf(alice);
        uint256 poolBalanceBefore = asset.balanceOf(address(pool));

        LendingPool.UserPosition memory positionBefore = pool.getUserPosition(alice, address(asset));

        // Act: withdrawal must revert because risk cannot be evaluated.
        vm.expectRevert(OracleReader.StalePrice.selector);
        vm.prank(alice);
        pool.withdraw(address(asset), withdrawAmount);

        // Assert: balances and position accounting remain unchanged.
        LendingPool.UserPosition memory positionAfter = pool.getUserPosition(alice, address(asset));

        assertEq(asset.balanceOf(alice), aliceBalanceBefore);
        assertEq(asset.balanceOf(address(pool)), poolBalanceBefore);
        assertEq(positionAfter.supplied, positionBefore.supplied);
        assertEq(positionAfter.borrowed, positionBefore.borrowed);
    }

    function test_WithdrawSucceedsWhenHealthFactorRemainsAboveOne() public {
        vm.startPrank(alice);
        asset.mint(alice, 100 ether);
        asset.approve(address(pool), 100 ether);
        pool.deposit(address(asset), 100 ether);
        pool.borrow(address(asset), 50 ether);
        pool.withdraw(address(asset), 10 ether);
        vm.stopPrank();

        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(asset));

        assertEq(asset.balanceOf(alice), 60 ether);
        assertEq(asset.balanceOf(address(pool)), 40 ether);
        assertEq(position.supplied, 90 ether);
        assertEq(position.borrowed, 50 ether);
    }

    function test_BorrowRevertsWhenRiskEngineIsNotConfigured() public {
        LendingPool unconfiguredPool = new LendingPool(owner);
        uint256 liquidity = 100 ether;
        uint256 borrowAmount = 10 ether;

        // Provide enough liquidity so the call reaches the RiskEngine dependency.
        asset.mint(address(unconfiguredPool), liquidity);

        vm.prank(alice);
        vm.expectRevert(LendingPool.RiskEngineNotConfigured.selector);
        unconfiguredPool.borrow(address(asset), borrowAmount);

        // A failed borrow must not transfer tokens or create debt.
        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(unconfiguredPool)), liquidity);

        LendingPool.UserPosition memory position = unconfiguredPool.getUserPosition(alice, address(asset));

        assertEq(position.supplied, 0);
        assertEq(position.borrowed, 0);
    }

    function test_BorrowRevertsWhenOraclePriceIsStale() public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowAmount = 40 ether;

        // Arrange: Alice supplies collateral.
        vm.startPrank(alice);
        asset.mint(alice, suppliedAmount);
        asset.approve(address(pool), suppliedAmount);
        pool.deposit(address(asset), suppliedAmount);
        vm.stopPrank();

        // Make the oracle price older than OracleReader's maximum age.
        vm.warp(1_000_000);
        priceFeed.setRoundData(1, block.timestamp - 1 days - 1, 1);

        uint256 aliceBalanceBefore = asset.balanceOf(alice);
        uint256 poolBalanceBefore = asset.balanceOf(address(pool));

        LendingPool.UserPosition memory positionBefore = pool.getUserPosition(alice, address(asset));

        // Act: borrowing must revert because the oracle price is stale.
        vm.expectRevert(OracleReader.StalePrice.selector);
        vm.prank(alice);
        pool.borrow(address(asset), borrowAmount);

        // Assert: token balances and accounting remain unchanged.
        LendingPool.UserPosition memory positionAfter = pool.getUserPosition(alice, address(asset));

        assertEq(asset.balanceOf(alice), aliceBalanceBefore);
        assertEq(asset.balanceOf(address(pool)), poolBalanceBefore);
        assertEq(positionAfter.supplied, positionBefore.supplied);
        assertEq(positionAfter.borrowed, positionBefore.borrowed);
    }

    function test_BorrowTransfersTokensAndUpdatesPosition() public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowAmount = 40 ether;
        MockERC20 token = asset;
        LendingPool lendingPool = pool;

        vm.startPrank(alice);
        asset.mint(alice, 100 ether);
        token.approve(address(lendingPool), suppliedAmount);
        lendingPool.deposit(address(token), suppliedAmount); //alice balance = 0
        lendingPool.borrow(address(token), borrowAmount); //alice balance = 40
        vm.stopPrank();

        LendingPool.UserPosition memory position = lendingPool.getUserPosition(alice, address(token));

        assertEq(token.balanceOf(alice), borrowAmount);
        assertEq(token.balanceOf(address(lendingPool)), suppliedAmount - borrowAmount);
        assertEq(position.supplied, suppliedAmount);
        assertEq(position.borrowed, borrowAmount);
    }

    function test_BorrowWithSixDecimalAssetUsesCorrectTokenScale() public {
        MockERC20SixDecimals usdc = new MockERC20SixDecimals();
        MockAggregatorV3 usdcFeed = new MockAggregatorV3(8, 1e8, 1, block.timestamp, 1);

        vm.startPrank(owner);
        config.configureAsset(address(usdc), true, 8000, 8500, 500);
        oracleReader.setPriceFeed(address(usdc), address(usdcFeed));
        vm.stopPrank();

        uint256 suppliedAmount = 100e6;
        uint256 borrowAmount = 80e6;
        usdc.mint(alice, suppliedAmount);

        vm.startPrank(alice);
        usdc.approve(address(pool), suppliedAmount);
        pool.deposit(address(usdc), suppliedAmount);
        // 100 USDC supplied, 80% LTV: borrowing 80 USDC should succeed.
        usdc.mint(address(pool), borrowAmount);
        pool.borrow(address(usdc), borrowAmount);
        vm.stopPrank();

        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(usdc));

        assertEq(position.supplied, suppliedAmount);
        assertEq(position.borrowed, borrowAmount);
        assertEq(usdc.balanceOf(alice), borrowAmount);
    }

    function test_BorrowRevertsWhenTinyPriceExceedsBorrowingCapacity() public {
        MockERC20SixDecimals usdc = new MockERC20SixDecimals();
        MockAggregatorV3 tinyPriceFeed = new MockAggregatorV3(18, 1, 1, block.timestamp, 1);

        vm.startPrank(owner);
        config.configureAsset(address(usdc), true, 8000, 8500, 500);
        oracleReader.setPriceFeed(address(usdc), address(tinyPriceFeed));
        vm.stopPrank();

        // Supply $100 of collateral at $1 per token.
        uint256 collateralAmount = 100 ether;
        asset.mint(alice, collateralAmount);
        vm.startPrank(alice);
        asset.approve(address(pool), collateralAmount);
        pool.deposit(address(asset), collateralAmount);
        vm.stopPrank();

        // At $1e-18 per USDC, this amount is worth $81.
        uint256 borrowAmount = 81e24; //81e24 basic unit = 81e18 USDC
        usdc.mint(address(pool), borrowAmount);
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        uint256 poolBalanceBefore = usdc.balanceOf(address(pool));

        vm.expectRevert(LendingPool.BorrowingCapacityExceeded.selector);
        vm.prank(alice);
        pool.borrow(address(usdc), borrowAmount);

        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(usdc));
        assertEq(position.borrowed, 0);
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore);
        assertEq(usdc.balanceOf(address(pool)), poolBalanceBefore);
    }

    function test_BorrowRevertsWhenAmountIsZero() public {
        vm.prank(alice);
        vm.expectRevert(LendingPool.InvalidAmount.selector);
        pool.borrow(address(asset), 0);
    }

    function test_BorrowRevertsWhenLiquidityIsInsufficient() public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowAmount = 101 ether;
        MockERC20 token = asset;
        LendingPool lendingPool = pool;

        vm.startPrank(alice);
        token.mint(alice, 100 ether);
        token.approve(address(lendingPool), suppliedAmount);
        lendingPool.deposit(address(token), suppliedAmount);

        LendingPool.UserPosition memory positionBefore = lendingPool.getUserPosition(alice, address(token));

        vm.expectRevert(LendingPool.InsufficientLiquidity.selector);
        lendingPool.borrow(address(token), borrowAmount);

        LendingPool.UserPosition memory positionAfter = lendingPool.getUserPosition(alice, address(token));

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(lendingPool)), suppliedAmount);
        assertEq(positionAfter.supplied, positionBefore.supplied);
        assertEq(positionAfter.borrowed, positionBefore.borrowed);
        vm.stopPrank();
    }

    function test_BorrowRevertsWhenExceedingBorrowingPower() public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowAmount = 81 ether;

        vm.startPrank(alice);
        asset.mint(alice, suppliedAmount);
        asset.approve(address(pool), suppliedAmount);
        pool.deposit(address(asset), suppliedAmount);
        vm.stopPrank();

        vm.expectRevert(LendingPool.BorrowingCapacityExceeded.selector);
        vm.prank(alice);
        pool.borrow(address(asset), borrowAmount);

        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(asset));

        assertEq(asset.balanceOf(alice), 0);
        assertEq(asset.balanceOf(address(pool)), suppliedAmount);
        assertEq(position.supplied, suppliedAmount);
        assertEq(position.borrowed, 0);
    }

    function test_BorrowWithTinyDebtValueUsesMinimumPositiveUsdUnit() public {
        MockERC20SixDecimals usdc = new MockERC20SixDecimals();
        // A raw answer of 1 with 18 feed decimals represents $1e-18.
        MockAggregatorV3 tinyPriceFeed = new MockAggregatorV3(18, 1, 1, block.timestamp, 1);

        vm.startPrank(owner);
        config.configureAsset(address(usdc), true, 8000, 8500, 500);
        oracleReader.setPriceFeed(address(usdc), address(tinyPriceFeed));
        vm.stopPrank();
        uint256 collateralAmount = 100e18;
        usdc.mint(alice, collateralAmount);

        vm.startPrank(alice);
        usdc.approve(address(pool), collateralAmount);
        pool.deposit(address(usdc), collateralAmount);
        vm.stopPrank();

        // One USDC base unit is worth less than the smallest USD unit
        // used by the RiskEngine calculation.
        uint256 borrowAmount = 1; //1 base unit = 1e-24 USD
        usdc.mint(address(pool), borrowAmount);
        assertEq(riskEngine.getAssetUsdValue(address(usdc), borrowAmount), 0);

        vm.prank(alice);
        pool.borrow(address(usdc), borrowAmount);

        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(usdc));

        assertEq(position.borrowed, borrowAmount);
        assertEq(usdc.balanceOf(alice), borrowAmount);
        assertEq(riskEngine.getTotalDebtValue(alice), 1);
    }

    function test_BorrowSucceedsAtExactBorrowingPower() public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowAmount = 80 ether;

        vm.startPrank(alice);

        asset.mint(alice, suppliedAmount);
        asset.approve(address(pool), suppliedAmount);
        pool.deposit(address(asset), suppliedAmount);

        // LTV is 80%, so borrowing exactly 80 tokens
        // against 100 supplied tokens should be allowed.
        pool.borrow(address(asset), borrowAmount);

        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(asset));

        assertEq(position.supplied, suppliedAmount);
        assertEq(position.borrowed, borrowAmount);
        assertEq(asset.balanceOf(alice), 80 ether);
        assertEq(asset.balanceOf(address(pool)), 20 ether);

        vm.stopPrank();
    }

    function test_BorrowRevertsWhenCumulativeBorrowingExceedsBorrowingPower() public {
        uint256 suppliedAmount = 100 ether;
        uint256 firstBorrowAmount = 50 ether;
        uint256 secondBorrowAmount = 31 ether;

        vm.startPrank(alice);
        asset.mint(alice, suppliedAmount);
        asset.approve(address(pool), suppliedAmount);
        pool.deposit(address(asset), suppliedAmount);

        pool.borrow(address(asset), firstBorrowAmount);
        vm.stopPrank();

        LendingPool.UserPosition memory positionBefore = pool.getUserPosition(alice, address(asset));

        assertEq(positionBefore.borrowed, firstBorrowAmount);
        assertEq(asset.balanceOf(alice), firstBorrowAmount);

        vm.expectRevert(LendingPool.BorrowingCapacityExceeded.selector);
        vm.prank(alice);
        pool.borrow(address(asset), secondBorrowAmount);

        LendingPool.UserPosition memory positionAfter = pool.getUserPosition(alice, address(asset));

        assertEq(asset.balanceOf(alice), firstBorrowAmount);
        assertEq(asset.balanceOf(address(pool)), suppliedAmount - firstBorrowAmount);
        assertEq(positionAfter.supplied, suppliedAmount);
        assertEq(positionAfter.borrowed, firstBorrowAmount);
    }

    function test_RepayTransfersTokensAndUpdatesPosition() public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowAmount = 40 ether;
        uint256 repayAmount = 25 ether;
        MockERC20 token = asset;
        LendingPool lendingPool = pool;

        vm.startPrank(alice);
        token.mint(alice, 100 ether);
        token.approve(address(lendingPool), suppliedAmount);
        lendingPool.deposit(address(token), suppliedAmount); //alice balance = 0
        lendingPool.borrow(address(token), borrowAmount); //alice balance = 40

        token.approve(address(lendingPool), repayAmount);
        lendingPool.repay(address(token), repayAmount); //alice balance = 15

        LendingPool.UserPosition memory position = lendingPool.getUserPosition(alice, address(token));

        assertEq(token.balanceOf(alice), 15 ether);
        assertEq(token.balanceOf(address(lendingPool)), 85 ether);
        assertEq(position.supplied, suppliedAmount);
        assertEq(position.borrowed, 15 ether);

        vm.stopPrank();
    }

    function test_RepaySucceedsWhenAssetIsDisabled() public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowAmount = 40 ether;
        uint256 repayAmount = 25 ether;

        vm.startPrank(alice);
        asset.mint(alice, suppliedAmount);
        asset.approve(address(pool), suppliedAmount);
        pool.deposit(address(asset), suppliedAmount);
        pool.borrow(address(asset), borrowAmount);
        vm.stopPrank();

        // Disable the asset after the debt has been created.
        vm.prank(owner);
        config.configureAsset(address(asset), false, 8000, 8500, 500);

        vm.startPrank(alice);
        asset.approve(address(pool), repayAmount);
        pool.repay(address(asset), repayAmount);
        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(asset));
        assertEq(position.supplied, suppliedAmount);
        assertEq(position.borrowed, borrowAmount - repayAmount);
        assertEq(asset.balanceOf(address(pool)), 85 ether);
        assertEq(asset.balanceOf(alice), 15 ether);
        vm.stopPrank();
    }

    function test_RepayRevertsWhenAmountIsZero() public {
        vm.prank(alice);
        vm.expectRevert(LendingPool.InvalidAmount.selector);
        pool.repay(address(asset), 0);
    }

    function test_RepayRevertsWhenAmountExceedsDebt() public {
        uint256 suppliedAmount = 100 ether;
        uint256 borrowAmount = 40 ether;
        uint256 repayAmount = 41 ether;

        vm.startPrank(alice);
        asset.mint(alice, 100 ether);
        asset.approve(address(pool), suppliedAmount);
        pool.deposit(address(asset), suppliedAmount); //alice = 0
        pool.borrow(address(asset), borrowAmount); // alice = 40
        vm.expectRevert(LendingPool.RepayAmountExceedsDebt.selector);
        pool.repay(address(asset), repayAmount); //alice = 40

        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(asset));

        assertEq(asset.balanceOf(alice), 40 ether);
        assertEq(asset.balanceOf(address(pool)), suppliedAmount - borrowAmount);
        assertEq(position.supplied, suppliedAmount);
        assertEq(position.borrowed, borrowAmount);

        vm.stopPrank();
    }

    function test_RepayRevertsWhenReceivedAmountIsLessThanRequested() public {
        FeeOnTransferMock feeToken = new FeeOnTransferMock();
        vm.startPrank(owner);
        config.configureAsset(
            address(feeToken),
            true,
            8000, // LTV: 80%
            8500, // Liquidation threshold: 85%
            500 // Liquidation bonus: 5%
        );
        oracleReader.setPriceFeed(address(feeToken), address(priceFeed));
        vm.stopPrank();

        feeToken.mint(address(pool), 100 ether);
        feeToken.mint(alice, 100 ether);
        vm.startPrank(alice);
        asset.mint(alice, 100 ether);
        asset.approve(address(pool), 100 ether);
        pool.deposit(address(asset), 100 ether);
        pool.borrow(address(feeToken), 50 ether);
        // Act:
        feeToken.approve(address(pool), 50 ether);
        // Expect revert when Alice repays using the fee-on-transfer asset.
        vm.expectRevert(LendingPool.InvalidAmount.selector);
        pool.repay(address(feeToken), 50 ether);
        vm.stopPrank();

        LendingPool.UserPosition memory position = pool.getUserPosition(alice, address(feeToken));
        // Assert:
        // Alice's debt remains unchanged.
        assertEq(position.borrowed, 50 ether);
        // The pool's balance of the fee-on-transfer asset remains unchanged.
        assertEq(feeToken.balanceOf(address(pool)), 50 ether);
        assertEq(feeToken.balanceOf(alice), 145 ether);
    }

    function test_SetRiskEngineRevertsWhenCallerIsNotOwner() public {
        vm.expectRevert();
        vm.prank(alice);
        pool.setRiskEngine(address(asset));
    }

    function test_SetRiskEngineRevertsWhenAddressIsZero() public {
        vm.expectRevert(LendingPool.InvalidRiskEngineAddress.selector);
        vm.prank(owner);
        pool.setRiskEngine(address(0));
    }

    function test_SetRiskEngineConfiguresAddress() public {
        LendingPool unconfiguredPool = new LendingPool(owner);
        RiskEngine newriskEngine = new RiskEngine(address(config), address(oracleReader), address(unconfiguredPool));
        vm.startPrank(owner);
        unconfiguredPool.setProtocolConfig(address(config));
        unconfiguredPool.setRiskEngine(address(newriskEngine));
        assertEq(unconfiguredPool.riskEngine(), address(newriskEngine));
        vm.stopPrank();
    }

    function test_SetRiskEngineRevertsWhenAlreadyConfigured() public {
        vm.startPrank(owner);
        vm.expectRevert(LendingPool.RiskEngineAlreadySet.selector);
        pool.setRiskEngine(address(0xBEFF));
        vm.stopPrank();
    }

    function test_SetRiskEngineRevertsWhenRiskEngineUsesDifferentLendingPool() public {
        // Deploy a fresh pool that has no RiskEngine configured.
        LendingPool unconfiguredPool = new LendingPool(owner);
        // Deploy another pool to create a dependency mismatch.
        LendingPool anotherPool = new LendingPool(owner);
        // This RiskEngine points to anotherPool, not unconfiguredPool.
        RiskEngine mismatchedRiskEngine = new RiskEngine(address(config), address(oracleReader), address(anotherPool));

        vm.startPrank(owner);
        unconfiguredPool.setProtocolConfig(address(config));
        vm.expectRevert(LendingPool.InvalidRiskEngineAddress.selector);
        unconfiguredPool.setRiskEngine(address(mismatchedRiskEngine));
        vm.stopPrank();
    }

    function test_SetRiskEngineRevertsWhenProtocolConfigDoesNotMatch() public {
        LendingPool unconfiguredPool = new LendingPool(owner);
        ProtocolConfig anotherConfig = new ProtocolConfig(owner);
        RiskEngine mismatchedRiskEngine =
            new RiskEngine(address(anotherConfig), address(oracleReader), address(unconfiguredPool));

        vm.prank(owner);
        unconfiguredPool.setProtocolConfig(address(config));

        vm.expectRevert(LendingPool.InvalidRiskEngineAddress.selector);
        vm.prank(owner);
        unconfiguredPool.setRiskEngine(address(mismatchedRiskEngine));
    }

    function test_SetRiskEngineRevertsWhenProtocolConfigIsNotConfigured() public {
        LendingPool unconfiguredPool = new LendingPool(owner);

        RiskEngine engine = new RiskEngine(address(config), address(oracleReader), address(unconfiguredPool));

        vm.expectRevert(LendingPool.ProtocolConfigNotConfigured.selector);
        vm.prank(owner);
        unconfiguredPool.setRiskEngine(address(engine));
    }

    function test_SetProtocolConfigConfiguresAddress() public {
        LendingPool unconfiguredPool = new LendingPool(owner);
        ProtocolConfig newConfig = new ProtocolConfig(owner);

        vm.prank(owner);
        unconfiguredPool.setProtocolConfig(address(newConfig));

        assertEq(address(unconfiguredPool.config()), address(newConfig));
    }

    function test_SetProtocolConfigRevertsWhenAddressIsZero() public {
        LendingPool unconfiguredPool = new LendingPool(owner);

        vm.prank(owner);
        vm.expectRevert(LendingPool.InvalidProtocolConfigAddress.selector);
        unconfiguredPool.setProtocolConfig(address(0));
    }

    function test_SetProtocolConfigRevertsWhenAddressHasNoCode() public {
        LendingPool unconfiguredPool = new LendingPool(owner);

        vm.prank(owner);
        vm.expectRevert(LendingPool.InvalidProtocolConfigAddress.selector);
        unconfiguredPool.setProtocolConfig(address(0x1234));
    }

    function test_SetProtocolConfigRevertsWhenAlreadyConfigured() public {
        vm.prank(owner);
        vm.expectRevert(LendingPool.ProtocolConfigAlreadySet.selector);
        pool.setProtocolConfig(address(config));
    }
}
