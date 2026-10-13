// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {LendingPool} from "../../../src/core/LendingPool.sol";
import {MockERC20} from "../../../src/mocks/MockERC20.sol";

/// @notice Routes the fuzzer through a bounded, actor-constrained action set.
///         The fuzzer only calls these four functions; every input is projected
///         into the valid domain so each call has a real chance to change state.
contract LendingPoolHandler is CommonBase, StdCheats, StdUtils {
    LendingPool public immutable pool;
    MockERC20 public immutable asset;
    address[] public actors;

    address internal currentActor;

    modifier useActor(uint256 actorSeed) {
        currentActor = actors[bound(actorSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor(LendingPool pool_, MockERC20 asset_, address[] memory actors_) {
        pool = pool_;
        asset = asset_;
        actors = actors_;
    }

    function deposit(uint256 amount, uint256 actorSeed) external useActor(actorSeed) {
        amount = bound(amount, 1, 1_000 ether);
        asset.mint(currentActor, amount);
        asset.approve(address(pool), amount);
        try pool.deposit(address(asset), amount) {} catch {}
    }

    function withdraw(uint256 amount, uint256 actorSeed) external useActor(actorSeed) {
        uint256 supplied = pool.getUserPosition(currentActor, address(asset)).supplied;
        if (supplied == 0) return;
        amount = bound(amount, 1, supplied);
        try pool.withdraw(address(asset), amount) {} catch {}
    }

    function borrow(uint256 amount, uint256 actorSeed) external useActor(actorSeed) {
        amount = bound(amount, 1, 100 ether);
        try pool.borrow(address(asset), amount) {} catch {}
    }

    function repay(uint256 amount, uint256 actorSeed) external useActor(actorSeed) {
        uint256 borrowed = pool.getUserPosition(currentActor, address(asset)).borrowed;
        if (borrowed == 0) return;
        amount = bound(amount, 1, borrowed);
        asset.mint(currentActor, amount);
        asset.approve(address(pool), amount);
        try pool.repay(address(asset), amount) {} catch {}
    }
}
