// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {LendingPool} from "../src/core/LendingPool.sol";
import {ILendingPool} from "../src/interfaces/ILendingPool.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// @notice Minimal end-to-end check against an already-deployed LendX.
///         Reads the pool and test token addresses from the environment,
///         performs one deposit and one borrow, then asserts the resulting
///         position. If this script succeeds, the deployed protocol is
///         functional at the level a demo needs.
contract SmokeTestLendX is Script {
    function run() external {
        address poolAddr = vm.envAddress("LENDING_POOL");
        address tokenAddr = vm.envAddress("TEST_TOKEN");

        LendingPool pool = LendingPool(poolAddr);
        MockERC20 token = MockERC20(tokenAddr);

        vm.startBroadcast();

        address user = msg.sender;
        uint256 depositAmount = 1_000 ether;
        uint256 borrowAmount = 100 ether;

        // MockERC20 exposes public mint; this is intentional for the demo
        // and is why the protocol must never be deployed with mock tokens
        // in any environment that holds real value.
        token.mint(user, depositAmount);

        token.approve(poolAddr, depositAmount);
        pool.deposit(tokenAddr, depositAmount);

        ILendingPool.UserPosition memory pos = pool.getUserPosition(user, tokenAddr);
        require(pos.supplied == depositAmount, "smoke: deposit accounting mismatch");

        pool.borrow(tokenAddr, borrowAmount);

        pos = pool.getUserPosition(user, tokenAddr);
        require(pos.borrowed == borrowAmount, "smoke: borrow accounting mismatch");

        vm.stopBroadcast();

        console2.log("Smoke test passed");
        console2.log("User:     ", user);
        console2.log("Supplied: ", pos.supplied);
        console2.log("Borrowed: ", pos.borrowed);
    }
}
