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
import {LendingPoolHandler} from "./handlers/LendingPoolHandler.sol";

/// @notice Stateful invariant tests over random call sequences.
///         These tests verify properties that must hold across any sequence
///         of deposit / withdraw / borrow / repay.
contract LendingPoolInvariantTest is Test {
    LendingPool internal pool;
    ProtocolConfig internal config;
    RiskEngine internal riskEngine;
    OracleReader internal oracleReader;
    MockERC20 internal asset;
    MockAggregatorV3 internal feed;
    LendingPoolHandler internal handler;

    address internal owner = makeAddr("owner");
    address[] internal actors;

    /// Pool balance at end of setUp. Invariant I1 is defined relative to this.
    uint256 internal poolSeedBalance;

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

        // Seed the pool so borrows have liquidity to draw from.
        asset.mint(address(pool), 1_000_000 ether);
        poolSeedBalance = asset.balanceOf(address(pool));

        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));

        for (uint256 i = 0; i < actors.length; i++) {
            asset.mint(actors[i], 10_000 ether);
            vm.prank(actors[i]);
            asset.approve(address(pool), type(uint256).max);
        }

        handler = new LendingPoolHandler(pool, asset, actors);

        // Restrict the fuzzer to the four handler actions.
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = LendingPoolHandler.deposit.selector;
        selectors[1] = LendingPoolHandler.withdraw.selector;
        selectors[2] = LendingPoolHandler.borrow.selector;
        selectors[3] = LendingPoolHandler.repay.selector;

        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // I1 — Token conservation
    // pool_balance + Σ borrowed == Σ supplied + poolSeedBalance
    function invariant_TokenConservation() public view {
        uint256 poolBalance = asset.balanceOf(address(pool));
        uint256 totalSupplied;
        uint256 totalBorrowed;

        for (uint256 i = 0; i < actors.length; i++) {
            ILendingPool.UserPosition memory pos = pool.getUserPosition(actors[i], address(asset));
            totalSupplied += pos.supplied;
            totalBorrowed += pos.borrowed;
        }

        assertEq(poolBalance + totalBorrowed, totalSupplied + poolSeedBalance, "I1: token conservation broken");
    }

    // I2 — Health-factor safety
    // Any actor with outstanding debt must have HF >= 1e18.
    function invariant_HealthFactorSafety() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            ILendingPool.UserPosition memory pos = pool.getUserPosition(actors[i], address(asset));
            if (pos.borrowed > 0) {
                uint256 hf = riskEngine.getHealthFactor(actors[i]);
                assertGe(hf, 1e18, "I2: debt holder below HF threshold");
            }
        }
    }
}
