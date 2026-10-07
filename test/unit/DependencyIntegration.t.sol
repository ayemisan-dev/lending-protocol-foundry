//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {OracleReader} from "../../src/oracles/OracleReader.sol";

contract DependencyIntegrationTest is Test {
    MockERC20 internal token;

    function setUp() public {
        token = new MockERC20("LendX Test Token", "LXTEST");
    }

    function test_OpenZeppelinERC20Works() public {
        address alice = address(0xA11CE);
        uint256 amount = 100 ether;

        token.mint(alice, amount);

        assertEq(token.balanceOf(alice), amount);
    }

    function test_ChainlinkInterfaceCanBeReferenced() public {
        address feed = address(0x1234);

        OracleReader reader = new OracleReader(feed);

        assertEq(address(reader.priceFeed()), feed);
    }
}
