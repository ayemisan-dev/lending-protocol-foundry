//SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;
import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {OracleReader} from "../../src/oracles/OracleReader.sol";

contract DependencyIntegrationTest is Test {
    function test_OpenZeppelinERC20Works() public {
        MockERC20 token = new MockERC20("LendX Test Token", "LXTEST");
        address alice = address(0xA11CE);
        uint256 amount = 100 ether;

        token.mint(alice, amount);

        assertEq(token.balanceOf(alice), amount);
    }

    function test_ChainlinkInterfaceCanBeReferenced() public {
        address owner = makeAddr("owner");
        OracleReader reader = new OracleReader(owner, 1 hours);
        assertEq(reader.owner(), owner);
    }
}
