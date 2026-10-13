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
import {MaliciousERC20} from "./mocks/MaliciousERC20.sol";
import {AttackerLiquidator} from "./mocks/AttackerLiquidator.sol";

/// @notice CEI verification: malicious ERC20 attempts to re-enter liquidate
///         from within the collateral transfer callback. Because LendingPool
///         updates state before external calls, the reentrant call is either
///         rejected by business checks or is equivalent to a sequential call.
contract ReentrancyAttackTest is Test {
    LendingPool internal pool;
    ProtocolConfig internal config;
    RiskEngine internal riskEngine;
    OracleReader internal oracleReader;
    MockERC20 internal debtAsset;
    MaliciousERC20 internal collAsset;
    MockAggregatorV3 internal debtFeed;
    MockAggregatorV3 internal collFeed;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    function setUp() public {
        debtAsset = new MockERC20("Debt", "DBT");
        collAsset = new MaliciousERC20();
        pool = new LendingPool(owner);
        config = new ProtocolConfig(owner);
        oracleReader = new OracleReader(owner, 1 days);
        debtFeed = new MockAggregatorV3(8, 1e8, 1, block.timestamp, 1);
        collFeed = new MockAggregatorV3(8, 1e8, 1, block.timestamp, 1);

        vm.startPrank(owner);
        config.configureAsset(address(debtAsset), true, 8000, 8500, 500);
        config.configureAsset(address(collAsset), true, 8000, 8500, 500);
        oracleReader.setPriceFeed(address(debtAsset), address(debtFeed));
        oracleReader.setPriceFeed(address(collAsset), address(collFeed));
        riskEngine = new RiskEngine(address(config), address(oracleReader), address(pool));
        pool.setProtocolConfig(address(config));
        pool.setRiskEngine(address(riskEngine));
        vm.stopPrank();
    }

    function test_LiquidateResistsReentrancyThroughMaliciousCollateral() public {
        // Alice supplies 50 collAsset, borrows 40 debtAsset.
        // HF at 85% LT: 50 * 0.85 / 40 = 1.0625 → healthy.
        vm.startPrank(alice);
        collAsset.mint(alice, 50 ether);
        collAsset.approve(address(pool), 50 ether);
        pool.deposit(address(collAsset), 50 ether);
        vm.stopPrank();

        debtAsset.mint(address(pool), 40 ether);
        vm.prank(alice);
        pool.borrow(address(debtAsset), 40 ether);

        // Tighten LT to 75% → HF = 50 * 0.75 / 40 = 0.9375 → liquidatable.
        vm.prank(owner);
        config.configureAsset(address(collAsset), true, 7000, 7500, 500);

        // Liquidator
        AttackerLiquidator attacker = new AttackerLiquidator(pool);
        uint256 debtToCover = 40 ether;
        attacker.configure(alice, address(debtAsset), address(collAsset), debtToCover);
        debtAsset.mint(address(attacker), debtToCover);
        // Enable the malicious callback, targeting the attacker.
        collAsset.setCallback(address(attacker), true);

        // Launch the attack.
        attacker.attack();

        // --- Assertions ---

        // 1. The callback DID fire (proves we exercised the reentrancy path).
        assertTrue(attacker.reentryAttempted(), "callback did not fire");

        // 2. Reentrancy was rejected.
        assertFalse(attacker.reentrySucceeded(), "reentrancy unexpectedly succeeded");
        assertEq(
            attacker.reentryRevertSelector(),
            LendingPool.PositionNotLiquidatable.selector,
            "unexpected reentry revert reason"
        );

        // 3. Exactly one liquidation took effect:
        //    40 debt * 1.05 bonus = 42 collateral seized from 50.
        ILendingPool.UserPosition memory collPos = pool.getUserPosition(alice, address(collAsset));
        ILendingPool.UserPosition memory debtPos = pool.getUserPosition(alice, address(debtAsset));
        assertEq(collPos.supplied, 8 ether, "collateral not reduced by exactly one seizure"); // 50 - 42 = 8 ether
        assertEq(debtPos.borrowed, 0, "debt not fully cleared");

        // 4. Attacker received exactly one bonus payout, not two.
        assertEq(collAsset.balanceOf(address(attacker)), 42 ether, "attacker got wrong payout");
        assertEq(debtAsset.balanceOf(address(attacker)), 0, "attacker did not spend its debt tokens");
    }
}
