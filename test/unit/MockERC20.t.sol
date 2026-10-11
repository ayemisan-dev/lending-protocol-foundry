//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract MockERC20Test is Test {
    MockERC20 internal asset;

    function setUp() public {
        asset = new MockERC20("Mock USD Coin", "mUSDC");
    }

    function test_Mint() public {
        address alice = makeAddr("alice");
        asset.mint(alice, 1000 ether);
        assertEq(asset.balanceOf(alice), 1000 ether);
    }

    function test_Approve() public {
        address alice = makeAddr("alice");
        address pool = makeAddr("pool");

        asset.mint(alice, 1_000 ether);

        vm.prank(alice);
        asset.approve(pool, 300 ether);

        assertEq(asset.allowance(alice, pool), 300 ether);
    }

    function test_TransferFrom() public {
        address alice = makeAddr("alice");
        address pool = makeAddr("pool");

        asset.mint(alice, 1_000 ether);

        vm.prank(alice);
        asset.approve(pool, 500 ether);

        vm.prank(pool);
        asset.transferFrom(alice, pool, 500 ether);

        assertEq(asset.balanceOf(alice), 500 ether);
        assertEq(asset.balanceOf(pool), 500 ether);
        assertEq(asset.allowance(alice, pool), 0);
    }

    function test_RevertWhenTransferFromExceedsAllowance() public {
        address alice = makeAddr("alice");
        address pool = makeAddr("pool");

        asset.mint(alice, 1_000 ether);

        vm.prank(alice);
        asset.approve(pool, 300 ether);

        vm.prank(pool);
        vm.expectRevert();
        asset.transferFrom(alice, pool, 500 ether);

        assertEq(asset.balanceOf(alice), 1_000 ether);
        assertEq(asset.balanceOf(pool), 0);
        assertEq(asset.allowance(alice, pool), 300 ether);
    }

    function test_RevertWhenTransferFromExceedsBalance() public {
        address alice = makeAddr("alice");
        address pool = makeAddr("pool");

        asset.mint(alice, 1_000 ether);

        vm.prank(alice);
        asset.approve(pool, 1_500 ether);

        vm.prank(pool);
        vm.expectRevert();
        asset.transferFrom(alice, pool, 1_500 ether);

        assertEq(asset.balanceOf(alice), 1_000 ether);
        assertEq(asset.balanceOf(pool), 0);
        assertEq(asset.allowance(alice, pool), 1_500 ether);
    }
}
