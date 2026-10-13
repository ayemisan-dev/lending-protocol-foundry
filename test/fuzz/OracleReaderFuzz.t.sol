// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {OracleReader} from "../../src/oracles/OracleReader.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockAggregatorV3} from "../../src/mocks/MockAggregatorV3.sol";

/// @notice Fuzz OracleReader 18-decimal normalization across decimals 0..18.
contract OracleReaderFuzzTest is Test {
    OracleReader internal oracleReader;
    MockERC20 internal asset;

    address internal owner = makeAddr("owner");

    function setUp() public {
        oracleReader = new OracleReader(owner, 1 days);
        asset = new MockERC20("Mock", "MCK");
    }

    /// Property: for any positive answer and feedDecimals in [0, 18],
    /// getPrice returns answer * 10^(18 - feedDecimals), provided no overflow.
    function testFuzz_GetPriceScalesTo18Decimals(uint256 answerSeed, uint8 feedDecimals) public {
        feedDecimals = uint8(bound(feedDecimals, 0, 18));
        uint256 scale = 10 ** uint256(18 - feedDecimals);

        // Ensure answer * scale fits in uint256 AND fits in int256 (the feed's answer type).
        uint256 maxSafeUint = type(uint256).max / scale;
        uint256 maxInt = uint256(type(int256).max);
        uint256 upper = maxSafeUint < maxInt ? maxSafeUint : maxInt;
        uint256 answer = bound(answerSeed, 1, upper);

        MockAggregatorV3 feed = new MockAggregatorV3(feedDecimals, int256(answer), 1, block.timestamp, 1);
        vm.prank(owner);
        oracleReader.setPriceFeed(address(asset), address(feed));

        assertEq(oracleReader.getPrice(address(asset)), answer * scale);
    }

    /// Property: any answer that would overflow the normalization must revert,
    /// not silently truncate.
    function testFuzz_GetPriceRevertsOnNormalizationOverflow(uint256 answerSeed, uint8 feedDecimals) public {
        // feedDecimals = 18 leaves scale = 1, which cannot overflow. Restrict to [0, 17] so that scale >= 10 and an overflowing input exists.
        feedDecimals = uint8(bound(feedDecimals, 0, 17));
        uint256 scale = 10 ** uint256(18 - feedDecimals);

        uint256 minOverflow = type(uint256).max / scale + 1;
        uint256 maxInt = uint256(type(int256).max);
        vm.assume(minOverflow <= maxInt);

        uint256 answer = bound(answerSeed, minOverflow, maxInt);

        MockAggregatorV3 feed = new MockAggregatorV3(feedDecimals, int256(answer), 1, block.timestamp, 1);
        vm.prank(owner);
        oracleReader.setPriceFeed(address(asset), address(feed));

        vm.expectRevert(OracleReader.PriceNormalizationOverflow.selector);
        oracleReader.getPrice(address(asset));
    }
}
