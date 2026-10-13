// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {LendingPool} from "../../src/core/LendingPool.sol";
import {ProtocolConfig} from "../../src/core/ProtocolConfig.sol";
import {RiskEngine} from "../../src/core/RiskEngine.sol";
import {OracleReader} from "../../src/oracles/OracleReader.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockAggregatorV3} from "../../src/mocks/MockAggregatorV3.sol";

contract RiskEngineFuzzTest is Test {
    LendingPool internal pool;
    ProtocolConfig internal config;
    RiskEngine internal riskEngine;
    OracleReader internal oracleReader;
    MockERC20 internal asset;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    function setUp() public {
        asset = new MockERC20("Mock USD", "mUSD");
        pool = new LendingPool(owner);
        config = new ProtocolConfig(owner);
        oracleReader = new OracleReader(owner, 1 days);

        vm.startPrank(owner);
        config.configureAsset(address(asset), true, 8000, 8500, 500);
        oracleReader.setPriceFeed(address(asset), address(new MockAggregatorV3(8, 1e8, 1, block.timestamp, 1)));
        riskEngine = new RiskEngine(address(config), address(oracleReader), address(pool));
        pool.setProtocolConfig(address(config));
        pool.setRiskEngine(address(riskEngine));
        vm.stopPrank();
    }

    /// getAssetUsdValue is the mathematical floor of
    /// (amount * price) / tokenScale. We verify the floor bound directly
    /// instead of re-computing the same expression.
    function testFuzz_GetAssetUsdValueRoundsDown(uint256 amount) public view {
        amount = bound(amount, 0, 1e30);
        uint256 price = 1e18; // $1.00
        uint256 tokenScale = 1e18; // 18-decimals

        uint256 value = riskEngine.getAssetUsdValue(address(asset), amount);

        assertLe(value * tokenScale, amount * price, "value exceeds true product");
        assertGt((value + 1) * tokenScale, amount * price, "value below floor");
    }

    /// any positive debt at a positive price yields a non-zero
    /// USD debt value, because debt rounding is ceil.
    function testFuzz_GetTotalDebtValueNeverRoundsPositiveDebtToZero(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, 1, 1e24);

        asset.mint(address(pool), borrowAmount);
        asset.mint(alice, 10_000_000 ether);
        vm.startPrank(alice);
        asset.approve(address(pool), 10_000_000 ether);
        pool.deposit(address(asset), 10_000_000 ether);
        pool.borrow(address(asset), borrowAmount);
        vm.stopPrank();

        assertGt(riskEngine.getTotalDebtValue(alice), 0, "positive debt rounded to zero");
    }

    /// USD -> token -> USD round-trip never inflates the amount.
    function testFuzz_RoundTripUsdToTokenNeverInflates(uint256 amount) public view {
        amount = bound(amount, 0, 1e30);

        uint256 valueUsd = riskEngine.getAssetUsdValue(address(asset), amount);
        uint256 recovered = riskEngine.getAssetAmountForUsdValue(address(asset), valueUsd);

        assertLe(recovered, amount);
    }
}
