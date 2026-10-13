// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";

import {ProtocolConfig} from "../../src/core/ProtocolConfig.sol";
import {OracleReader} from "../../src/oracles/OracleReader.sol";
import {RiskEngine} from "../../src/core/RiskEngine.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockAggregatorV3} from "../../src/mocks/MockAggregatorV3.sol";
import {ILendingPool} from "../../src/interfaces/ILendingPool.sol";
import {MockLendingPool} from "../../src/mocks/MockLendingPool.sol";

contract MockERC20SixDecimals is MockERC20 {
    constructor() MockERC20("Mock USD Coin", "mUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract MockERC20SeventyEightDecimals is MockERC20 {
    constructor() MockERC20("Invalid Decimal Token", "BAD") {}

    function decimals() public pure override returns (uint8) {
        return 78;
    }
}

contract RiskEngineTest is Test {
    ProtocolConfig internal config;
    OracleReader internal oracleReader;
    RiskEngine internal riskEngine;
    MockLendingPool internal lendingPool;

    MockERC20 internal ethToken;
    MockERC20SixDecimals internal usdcToken;
    MockERC20 internal tokenWithoutFeed;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    MockAggregatorV3 internal ethFeed;
    MockAggregatorV3 internal usdcFeed;

    function test_ConstructorRevertsWhenProtocolConfigHasNoCode() public {
        vm.expectRevert(RiskEngine.InvalidAddress.selector);
        new RiskEngine(address(0x1001), address(oracleReader), address(lendingPool));
    }

    function test_ConstructorRevertsWhenOracleReaderHasNoCode() public {
        vm.expectRevert(RiskEngine.InvalidAddress.selector);
        new RiskEngine(address(config), address(0x1002), address(lendingPool));
    }

    function test_ConstructorRevertsWhenLendingPoolHasNoCode() public {
        vm.expectRevert(RiskEngine.InvalidAddress.selector);
        new RiskEngine(address(config), address(oracleReader), address(0x1003));
    }

    function test_ConstructorRevertsWhenDependencyIsZeroAddress() public {
        vm.expectRevert(RiskEngine.InvalidAddress.selector);
        new RiskEngine(address(0), address(oracleReader), address(lendingPool));
    }

    function setUp() public {
        config = new ProtocolConfig(owner);
        oracleReader = new OracleReader(owner, 1 days);
        lendingPool = new MockLendingPool();

        ethToken = new MockERC20("Mock Ether", "mETH");
        usdcToken = new MockERC20SixDecimals();
        tokenWithoutFeed = new MockERC20("Unconfigured Token", "NOFEED");

        vm.startPrank(owner);
        config.configureAsset(address(ethToken), true, 8000, 8500, 500);
        config.configureAsset(address(usdcToken), true, 8000, 8500, 500);
        config.configureAsset(address(tokenWithoutFeed), true, 8000, 8500, 500);

        ethFeed = new MockAggregatorV3(8, 2000e8, 1, block.timestamp, 1);
        usdcFeed = new MockAggregatorV3(8, 1e8, 1, block.timestamp, 1);

        oracleReader.setPriceFeed(address(ethToken), address(ethFeed));
        oracleReader.setPriceFeed(address(usdcToken), address(usdcFeed));

        riskEngine = new RiskEngine(address(config), address(oracleReader), address(lendingPool));
        vm.stopPrank();

        ethToken.mint(alice, 10 ether);
        usdcToken.mint(alice, 10_000e6);

        vm.startPrank(alice);
        ethToken.approve(address(lendingPool), type(uint256).max);
        usdcToken.approve(address(lendingPool), type(uint256).max);
        vm.stopPrank();
    }

    function _setPosition(address user, address asset, uint256 supplied, uint256 borrowed) internal {
        lendingPool.setPosition(user, asset, supplied, borrowed);
    }

    function _setBorrowed(address user, address asset, uint256 amount) internal {
        ILendingPool.UserPosition memory position = lendingPool.getUserPosition(user, asset);

        lendingPool.setPosition(user, asset, position.supplied, position.borrowed + amount);
    }

    function test_GetAssetUsdValueFor18DecimalToken() public view {
        uint256 value = riskEngine.getAssetUsdValue(address(ethToken), 1 ether);

        assertEq(value, 2000e18);
    }

    function test_GetAssetUsdValueFor6DecimalToken() public view {
        uint256 value = riskEngine.getAssetUsdValue(address(usdcToken), 1000e6);

        assertEq(value, 1000e18);
    }

    function test_RevertWhenAssetIsDisabled() public {
        vm.prank(owner);
        config.configureAsset(address(ethToken), false, 8000, 8500, 500);

        vm.expectRevert(RiskEngine.AssetNotEnabled.selector);
        riskEngine.getAssetUsdValue(address(ethToken), 1 ether);
    }

    function test_RevertWhenPriceFeedIsNotConfigured() public {
        vm.expectRevert(OracleReader.PriceFeedNotConfigured.selector);
        riskEngine.getAssetUsdValue(address(tokenWithoutFeed), 1 ether);
    }

    function test_GetAssetUsdValueReturnsZeroForZeroAmount() public view {
        uint256 value = riskEngine.getAssetUsdValue(address(ethToken), 0);

        assertEq(value, 0);
    }

    function test_RevertWhenTokenDecimalsExceedLimit() public {
        MockERC20SeventyEightDecimals invalidToken = new MockERC20SeventyEightDecimals();

        vm.prank(owner);
        config.configureAsset(address(invalidToken), true, 8000, 8500, 500);

        vm.expectRevert(RiskEngine.InvalidTokenDecimals.selector);
        riskEngine.getAssetUsdValue(address(invalidToken), 1);
    }

    function test_GetAssetUsdValueRoundsDown() public {
        MockAggregatorV3 preciseFeed = new MockAggregatorV3(18, 1e18 + 1, 1, block.timestamp, 1);

        vm.prank(owner);
        oracleReader.setPriceFeed(address(usdcToken), address(preciseFeed));

        uint256 value = riskEngine.getAssetUsdValue(address(usdcToken), 1);

        assertEq(value, 1e12);
    }

    function test_GetAssetUsdValueCanRoundPositiveAmountToZero() public {
        MockAggregatorV3 tinyPriceFeed = new MockAggregatorV3(18, 1, 1, block.timestamp, 1);
        vm.prank(owner);
        oracleReader.setPriceFeed(address(usdcToken), address(tinyPriceFeed));
        uint256 value = riskEngine.getAssetUsdValue(address(usdcToken), 1);
        assertEq(value, 0);
    }

    function test_TotalDebtValueRoundsPositiveDebtUpToMinimumUnit() public {
        MockAggregatorV3 tinyPriceFeed = new MockAggregatorV3(18, 1, 1, block.timestamp, 1);

        vm.prank(owner);
        oracleReader.setPriceFeed(address(usdcToken), address(tinyPriceFeed));

        address user = makeAddr("roundingUser");

        lendingPool.setPosition(user, address(usdcToken), 0, 1);
        uint256 debtValue = riskEngine.getTotalDebtValue(user);
        assertEq(debtValue, 1);
    }

    function test_GetTotalCollateralValueAcrossMultipleAssets() public {
        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        lendingPool.deposit(address(usdcToken), 1000e6);
        vm.stopPrank();

        uint256 value = riskEngine.getTotalCollateralValue(alice);

        assertEq(value, 3000e18);
    }

    function test_GetTotalCollateralValueReturnsZeroWhenNoSupply() public view {
        uint256 value = riskEngine.getTotalCollateralValue(alice);

        assertEq(value, 0);
    }

    function test_GetTotalCollateralValueExcludesAssetWithZeroLtv() public {
        MockERC20 nonCollateralToken = new MockERC20("Non Collateral Token", "NCT");

        vm.prank(owner);
        config.configureAsset(address(nonCollateralToken), true, 0, 8500, 500);

        MockAggregatorV3 tokenFeed = new MockAggregatorV3(8, 10e8, 1, block.timestamp, 1);

        vm.prank(owner);
        oracleReader.setPriceFeed(address(nonCollateralToken), address(tokenFeed));

        nonCollateralToken.mint(alice, 100 ether);

        vm.startPrank(alice);
        nonCollateralToken.approve(address(lendingPool), type(uint256).max);
        lendingPool.deposit(address(nonCollateralToken), 100 ether);
        vm.stopPrank();

        uint256 value = riskEngine.getTotalCollateralValue(alice);

        assertEq(value, 0);
    }

    function test_GetTotalCollateralValueExcludesDisabledAsset() public {
        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        lendingPool.deposit(address(usdcToken), 1_000e6);
        vm.stopPrank();

        vm.prank(owner);
        config.configureAsset(address(ethToken), false, 8_000, 8_500, 500);

        uint256 totalValue = riskEngine.getTotalCollateralValue(alice);

        // Disabled ETH is excluded.
        // USDC contributes $1,000.
        assertEq(totalValue, 1_000e18);

        ILendingPool.UserPosition memory ethPosition = lendingPool.getUserPosition(alice, address(ethToken));
        assertEq(ethPosition.supplied, 1 ether);
    }

    function test_GetTotalDebtValueAcrossMultipleAssets() public {
        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        lendingPool.deposit(address(usdcToken), 1000e6);

        _setBorrowed(alice, address(ethToken), 0.5 ether);
        _setBorrowed(alice, address(usdcToken), 100e6);
        vm.stopPrank();

        uint256 value = riskEngine.getTotalDebtValue(alice);

        // 0.5 ETH * $2,000 + 100 USDC * $1 = $1,100.
        assertEq(value, 1100e18);
    }

    function test_GetTotalDebtValueReturnsZeroWhenNoDebt() public view {
        uint256 value = riskEngine.getTotalDebtValue(alice);

        assertEq(value, 0);
    }

    function test_GetTotalDebtValueIncludesDisabledAssetDebt() public {
        vm.startPrank(alice);
        lendingPool.deposit(address(usdcToken), 1000e6);
        _setBorrowed(alice, address(usdcToken), 100e6);
        vm.stopPrank();

        vm.prank(owner);
        config.configureAsset(address(usdcToken), false, 8000, 8500, 500);

        uint256 value = riskEngine.getTotalDebtValue(alice);

        assertEq(value, 100e18);
    }

    function test_GetTotalDebtValueRevertsWhenDisabledDebtAssetHasNoPriceFeed() public {
        tokenWithoutFeed.mint(alice, 100 ether);

        vm.startPrank(alice);
        tokenWithoutFeed.approve(address(lendingPool), type(uint256).max);
        lendingPool.deposit(address(tokenWithoutFeed), 100 ether);
        _setBorrowed(alice, address(tokenWithoutFeed), 10 ether);
        vm.stopPrank();

        vm.prank(owner);
        config.configureAsset(address(tokenWithoutFeed), false, 8000, 8500, 500);

        vm.expectRevert(OracleReader.PriceFeedNotConfigured.selector);
        riskEngine.getTotalDebtValue(alice);
    }

    function test_GetMaxBorrowableValueAcrossMultipleAssets() public {
        vm.startPrank(alice);

        lendingPool.deposit(address(ethToken), 1 ether);
        lendingPool.deposit(address(usdcToken), 1_000e6);

        vm.stopPrank();

        uint256 maxBorrowableValue = riskEngine.getMaxBorrowableValue(alice);

        // 1 ETH = $2,000; 80% LTV = $1,600.
        // 1,000 USDC = $1,000; 80% LTV = $800.
        assertEq(maxBorrowableValue, 2_400e18);
    }

    function test_GetMaxBorrowableValueUsesAssetSpecificLtv() public {
        // Change USDC LTV to 50%; ETH remains at 80%.
        vm.prank(owner);
        config.configureAsset(address(usdcToken), true, 5_000, 8_500, 500);

        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        lendingPool.deposit(address(usdcToken), 1_000e6);
        vm.stopPrank();

        uint256 maxBorrowableValue = riskEngine.getMaxBorrowableValue(alice);

        // ETH: $2,000 * 80% = $1,600.
        // USDC: $1,000 * 50% = $500.
        // Total borrowing power = $2,100.
        assertEq(maxBorrowableValue, 2_100e18);
    }

    function test_GetMaxBorrowableValueReturnsZeroWhenNoCollateral() public view {
        uint256 maxBorrowableValue = riskEngine.getMaxBorrowableValue(alice);
        assertEq(maxBorrowableValue, 0);
    }

    function test_GetMaxBorrowableValueExcludesAssetWithZeroLtv() public {
        vm.prank(owner);
        config.configureAsset(address(ethToken), true, 0, 8_500, 500);

        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        lendingPool.deposit(address(usdcToken), 1_000e6);
        vm.stopPrank();

        uint256 maxBorrowableValue = riskEngine.getMaxBorrowableValue(alice);

        // ETH contributes $0 because its LTV is 0%.
        // USDC contributes $800 because its LTV is 80%.
        assertEq(maxBorrowableValue, 800e18);
    }

    function test_GetMaxBorrowableValueExcludesDisabledAsset() public {
        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        lendingPool.deposit(address(usdcToken), 1_000e6);
        vm.stopPrank();

        vm.prank(owner);
        config.configureAsset(address(ethToken), false, 8_000, 8_500, 500);

        uint256 maxBorrowableValue = riskEngine.getMaxBorrowableValue(alice);

        // Disabled ETH contributes nothing.
        // USDC contributes $1,000 * 80% = $800.
        assertEq(maxBorrowableValue, 800e18);
    }

    function test_GetMaxBorrowableValueRoundsDown() public {
        // Set ETH LTV to 50%.
        vm.prank(owner);
        config.configureAsset(address(ethToken), true, 5_000, 8_500, 500);

        // Deposit the smallest non-zero amount of ETH.
        vm.prank(alice);
        lendingPool.deposit(address(ethToken), 1);

        uint256 maxBorrowableValue = riskEngine.getMaxBorrowableValue(alice);

        // USD value is floor(1 * 2000e18 / 1e18) = 2000.
        // 50% LTV is floor(2000 * 5000 / 10000) = 1000.
        assertEq(maxBorrowableValue, 1_000);
    }

    function test_GetMaxBorrowableValueIsIndependentOfExistingDebt() public {
        vm.startPrank(alice);

        lendingPool.deposit(address(ethToken), 1 ether);
        lendingPool.deposit(address(usdcToken), 1_000e6);

        _setBorrowed(alice, address(ethToken), 0.5 ether);

        vm.stopPrank();

        uint256 debtValue = riskEngine.getTotalDebtValue(alice);
        uint256 maxBorrowableValue = riskEngine.getMaxBorrowableValue(alice);

        assertEq(debtValue, 1_000e18);
        assertEq(maxBorrowableValue, 2_400e18);
    }

    function test_GetLiquidationAdjustedCollateralValueAcrossMultipleAssets() public {
        // Arrange: give USDC a different liquidation threshold.
        vm.prank(owner);
        config.configureAsset(
            address(usdcToken),
            true,
            5_000, // LTV: 50%
            9_000, // Liquidation threshold: 90%
            500 // Liquidation bonus: 5%
        );

        // Alice supplies 1 ETH ($2,000) and 1,000 USDC ($1,000).
        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        lendingPool.deposit(address(usdcToken), 1_000e6);
        vm.stopPrank();

        // Act
        uint256 adjustedValue = riskEngine.getLiquidationAdjustedCollateralValue(alice);

        // Assert:
        // ETH:  $2,000 * 85% = $1,700
        // USDC: $1,000 * 90% =   $900
        // Total adjusted collateral value = $2,600
        assertEq(adjustedValue, 2_600e18);
    }

    function test_GetLiquidationAdjustedCollateralValueReturnsZeroWhenNoSupply() public view {
        uint256 adjustedValue = riskEngine.getLiquidationAdjustedCollateralValue(alice);
        assertEq(adjustedValue, 0);
    }

    function test_GetLiquidationAdjustedCollateralValueExcludesDisabledAsset() public {
        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        lendingPool.deposit(address(usdcToken), 1_000e6);
        vm.stopPrank();

        vm.prank(owner);
        config.configureAsset(
            address(ethToken),
            false, // disabled
            8_000,
            8_500,
            500
        );

        uint256 adjustedValue = riskEngine.getLiquidationAdjustedCollateralValue(alice);

        // ETH is excluded. USDC: $1,000 * 85% = $850.
        assertEq(adjustedValue, 850e18);
    }

    function test_GetLiquidationAdjustedCollateralValueIncludesAssetWithZeroLtv() public {
        vm.prank(owner);
        config.configureAsset(address(usdcToken), true, 0, 8_500, 500);

        vm.startPrank(alice);
        lendingPool.deposit(address(usdcToken), 1_000e6);
        vm.stopPrank();

        uint256 adjustedCollateralValue = riskEngine.getLiquidationAdjustedCollateralValue(alice);

        assertEq(adjustedCollateralValue, 850e18);
    }

    function test_GetHealthFactorReturnsMaxWhenNoDebt() public view {
        uint256 healthFactor = riskEngine.getHealthFactor(alice);
        assertEq(healthFactor, type(uint256).max);
    }

    function test_GetHealthFactorWithCollateralAndDebt() public {
        // Arrange: Alice supplies 1 ETH and 1,000 USDC.
        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        lendingPool.deposit(address(usdcToken), 1_000e6);

        // Borrow 1 ETH. LendingPool currently has no RiskEngine checks.
        _setBorrowed(alice, address(ethToken), 1 ether);
        vm.stopPrank();

        // Act
        uint256 healthFactor = riskEngine.getHealthFactor(alice);

        // Assert
        // Adjusted collateral:
        // ETH:  $2,000 * 85% = $1,700
        // USDC: $1,000 * 85% =   $850
        // Total:                 $2,550
        //
        // Debt: 1 ETH = $2,000
        // HF = $2,550 / $2,000 = 1.275
        assertEq(healthFactor, 1_275e15);
    }

    function test_GetHealthFactorReturnsZeroWhenDebtExistsWithoutCollateral() public {
        // Arrange: provide liquidity from another account.
        address bob = makeAddr("bob");
        vm.startPrank(bob);
        ethToken.mint(bob, 1 ether);
        ethToken.approve(address(lendingPool), 1 ether);
        lendingPool.deposit(address(ethToken), 1 ether);
        vm.stopPrank();

        // Alice borrows without supplying collateral.
        vm.prank(alice);
        _setBorrowed(alice, address(ethToken), 1 ether);

        // Act
        uint256 healthFactor = riskEngine.getHealthFactor(alice);

        // Assert
        assertEq(healthFactor, 0);
    }

    function test_GetHealthFactorUsesAssetSpecificLiquidationThresholds() public {
        // Configure USDC with a 90% liquidation threshold.
        vm.prank(owner);
        config.configureAsset(address(usdcToken), true, 5_000, 9_000, 500);

        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        lendingPool.deposit(address(usdcToken), 1_000e6);
        _setBorrowed(alice, address(ethToken), 1 ether);
        vm.stopPrank();

        uint256 healthFactor = riskEngine.getHealthFactor(alice);

        // ETH adjusted collateral: $2,000 * 85% = $1,700
        // USDC adjusted collateral: $1,000 * 90% = $900
        // Debt: $2,000
        // HF = $2,600 / $2,000 = 1.3
        assertEq(healthFactor, 1_300e15);
    }

    function test_HealthFactorExcludesDisabledCollateralButIncludesDebt() public {
        // Arrange: Alice deposits 1 ETH and borrows 0.5 ETH.
        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        _setBorrowed(alice, address(ethToken), 0.5 ether);
        vm.stopPrank();

        // Disable ETH after the position has been created.
        vm.prank(owner);
        config.configureAsset(address(ethToken), false, 8000, 8500, 500);

        // Assert: existing debt must remain valued.
        assertEq(riskEngine.getTotalDebtValue(alice), 1000e18);

        // Disabled collateral must not contribute to liquidation safety.
        assertEq(riskEngine.getHealthFactor(alice), 0);

        // Disabling the asset must not erase Alice's position.
        ILendingPool.UserPosition memory position = lendingPool.getUserPosition(alice, address(ethToken));

        assertEq(position.supplied, 1 ether);
        assertEq(position.borrowed, 0.5 ether);
    }

    function test_GetHealthFactorEqualsOneAtThresholdBoundary() public {
        // Arrange
        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        _setBorrowed(alice, address(ethToken), 0.85 ether);
        vm.stopPrank();

        // 1 ETH = $2,000
        // Adjusted collateral = $2,000 * 85% = $1,700
        // Debt = 0.85 ETH = $1,700

        // Assert: $1,700 / $1,700 = 1.0
        assertEq(riskEngine.getHealthFactor(alice), 1e18);
    }

    function test_GetHealthFactorIsBelowOneWhenDebtExceedsAdjustedCollateral() public {
        // Arrange
        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        _setBorrowed(alice, address(ethToken), 0.9 ether);
        vm.stopPrank();

        // Adjusted collateral = $2,000 * 85% = $1,700
        // Debt = 0.9 ETH = $1,800

        // Assert: $1,700 / $1,800 < 1.0
        assertEq(riskEngine.getHealthFactor(alice), 944444444444444444);

        assertLt(riskEngine.getHealthFactor(alice), 1e18);
    }

    function test_HealthFactorUpdatesWhenCollateralPriceFalls() public {
        // Arrange: provide USDC liquidity from the test contract.
        usdcToken.mint(address(this), 1000e6);
        usdcToken.approve(address(lendingPool), 1000e6);
        lendingPool.deposit(address(usdcToken), 1000e6);

        // Alice deposits 1 ETH and borrows 1,000 USDC.
        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        _setBorrowed(alice, address(usdcToken), 1000e6);
        vm.stopPrank();

        // Initial ETH price: $2,000.
        assertEq(riskEngine.getHealthFactor(alice), 1.7e18);

        // Simulate the ETH price falling to $1,000.
        ethFeed.setAnswer(1000e8);

        // Adjusted collateral: $1,000 * 85% = $850.
        // Debt remains $1,000.
        assertEq(riskEngine.getTotalDebtValue(alice), 1000e18);
        assertEq(riskEngine.getHealthFactor(alice), 0.85e18);
    }

    function test_GetHealthFactorRevertsWhenOraclePriceIsStale() public {
        // Arrange: Alice supplies ETH and borrows USDC.
        usdcToken.mint(address(this), 1000e6);
        usdcToken.approve(address(lendingPool), 1000e6);
        lendingPool.deposit(address(usdcToken), 1000e6);

        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        _setBorrowed(alice, address(usdcToken), 1000e6);
        vm.stopPrank();

        // Make the ETH price stale.
        vm.warp(block.timestamp + 2 days);

        // Assert: RiskEngine must propagate OracleReader's error.
        vm.expectRevert(OracleReader.StalePrice.selector);
        riskEngine.getHealthFactor(alice);
    }

    function test_GetHealthFactorRevertsWhenDebtAssetHasNoPriceFeed() public {
        // Arrange: Alice supplies ETH as collateral.
        vm.startPrank(alice);
        lendingPool.deposit(address(ethToken), 1 ether);
        vm.stopPrank();

        // Provide liquidity for the unconfigured debt asset.
        tokenWithoutFeed.mint(address(this), 10 ether);
        tokenWithoutFeed.approve(address(lendingPool), 10 ether);
        lendingPool.deposit(address(tokenWithoutFeed), 10 ether);

        // Alice borrows an asset without a configured price feed.
        vm.prank(alice);
        _setBorrowed(alice, address(tokenWithoutFeed), 1 ether);

        // Assert: RiskEngine must not calculate HF without debt pricing.
        vm.expectRevert(OracleReader.PriceFeedNotConfigured.selector);
        riskEngine.getHealthFactor(alice);
    }

    function test_GetAssetAmountForUsdValueReturnsZeroForZeroUsdValue() public view {
        assertEq(riskEngine.getAssetAmountForUsdValue(address(ethToken), 0), 0);
    }

    function test_GetAssetAmountForUsdValueFor18DecimalToken() public {
        MockERC20 eth = new MockERC20("Mock ETH", "meth"); //18 decimal token
        MockAggregatorV3 feed = new MockAggregatorV3(18, 1e18, 1, block.timestamp, 1);
        vm.startPrank(owner);
        config.configureAsset(address(eth), true, 8000, 8500, 500);
        oracleReader.setPriceFeed(address(eth), address(feed));
        vm.stopPrank();
        // $250 at $1/token → 250e18.
        uint256 amount = riskEngine.getAssetAmountForUsdValue(address(eth), 250e18);
        assertEq(amount, 250e18);
    }

    function test_GetAssetAmountForUsdValueFor6DecimalToken() public {
        MockAggregatorV3 feed = new MockAggregatorV3(8, 1e8, 1, block.timestamp, 1);
        vm.startPrank(owner);
        config.configureAsset(address(usdcToken), true, 8000, 8500, 500);
        oracleReader.setPriceFeed(address(usdcToken), address(feed));
        vm.stopPrank();
        uint256 amount = riskEngine.getAssetAmountForUsdValue(address(usdcToken), 250e18);
        assertEq(amount, 250e6); //250 USDC
    }

    function test_GetAssetAmountForUsdValueRoundsDown() public {
        // Price = $3.00. $10 / $3 = 3.333... tokens → floor to 3.333...e18.
        MockAggregatorV3 feed = new MockAggregatorV3(8, 3e8, 1, block.timestamp, 1);
        vm.prank(owner);
        oracleReader.setPriceFeed(address(ethToken), address(feed));
        uint256 amount = riskEngine.getAssetAmountForUsdValue(address(ethToken), 10e18);
        assertEq(amount, uint256(10 ether) / 3);
    }

    function test_GetAssetAmountForUsdValueRevertsWhenAssetIsDisabled() public {
        MockERC20 disabled = new MockERC20("Disabled", "DIS");
        vm.prank(owner);
        config.configureAsset(address(disabled), false, 8000, 8500, 500);
        vm.expectRevert(RiskEngine.AssetNotEnabled.selector);
        riskEngine.getAssetAmountForUsdValue(address(disabled), 100e18);
    }

    function test_GetAssetAmountForUsdValueRevertsWhenPriceFeedNotConfigured() public {
        vm.expectRevert(OracleReader.PriceFeedNotConfigured.selector);
        riskEngine.getAssetAmountForUsdValue(address(tokenWithoutFeed), 100e18);
    }

    function test_GetHealthFactorRevertsWhenCollateralAssetHasNoPriceFeed() public {
        // give alice a position that has real debt
        vm.startPrank(alice);
        _setBorrowed(alice, address(ethToken), 50 ether);

        tokenWithoutFeed.mint(alice, 50 ether);
        tokenWithoutFeed.approve(address(lendingPool), 50 ether);
        lendingPool.deposit(address(tokenWithoutFeed), 50 ether);

        // getHealthFactor reads tokenWithoutFeed's price → revert.
        vm.expectRevert(OracleReader.PriceFeedNotConfigured.selector);
        riskEngine.getHealthFactor(alice);
        vm.stopPrank();
    }
}
