// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {OracleReader} from "../../src/oracles/OracleReader.sol";
import {MockAggregatorV3} from "../../src/mocks/MockAggregatorV3.sol";

contract OracleReaderTest is Test {
    OracleReader oracleReader;

    MockAggregatorV3 feed8;
    MockAggregatorV3 feed18;
    MockAggregatorV3 feed20;
    uint256 constant MAX_PRICE_AGE = 1 hours;

    address eth = makeAddr("eth");
    address usdc = makeAddr("usdc");
    address wbtc = makeAddr("wbtc");

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");

    function setUp() public {
        oracleReader = new OracleReader(owner, MAX_PRICE_AGE);
        uint256 updatedAt = block.timestamp;
        //MockAggregatorV3(decimal, answer, roundId, updatedAt, anseredInRound)
        feed8 = new MockAggregatorV3(8, 2500e8, 1, updatedAt, 1);
        feed18 = new MockAggregatorV3(18, 2500e18, 1, updatedAt, 1);
        feed20 = new MockAggregatorV3(20, 2500e20, 1, updatedAt, 1);
    }

    function test_OwnerCanSetPriceFeed() public {
        vm.prank(owner);
        oracleReader.setPriceFeed(eth, address(feed8));
        assertEq(address(oracleReader.priceFeeds(eth)), address(feed8));
    }

    function test_NonOwnerCannotSetPriceFeed() public {
        vm.prank(alice);
        vm.expectRevert();
        oracleReader.setPriceFeed(eth, address(feed8));
    }

    function test_SetPriceFeedRevertsWhenAssetIsZero() public {
        vm.prank(owner);

        vm.expectRevert(OracleReader.InvalidAsset.selector);
        oracleReader.setPriceFeed(address(0), address(feed8));
    }

    function test_SetPriceFeedRevertsWhenPriceFeedIsZero() public {
        vm.prank(owner);
        vm.expectRevert(OracleReader.InvalidPriceFeed.selector);
        oracleReader.setPriceFeed(eth, address(0));
    }

    function test_SetPriceRevertsWhenFeedDecimalsExceed18() public {
        vm.prank(owner);
        vm.expectRevert(OracleReader.InvalidFeedDecimals.selector);
        oracleReader.setPriceFeed(wbtc, address(feed20));
    }

    function test_GetPriceRevertsWhenFeedIsNotConfigured() public {
        vm.expectRevert(OracleReader.PriceFeedNotConfigured.selector);
        oracleReader.getPrice(address(0));
    }

    function test_GetPriceNormalizes8DecimalsTo18() public {
        vm.prank(owner);
        oracleReader.setPriceFeed(eth, address(feed8));
        uint256 price = oracleReader.getPrice(eth);
        assertEq(price, 2500e18);
    }

    function test_GetPriceKeeps18DecimalsUnchanged() public {
        vm.prank(owner);
        oracleReader.setPriceFeed(usdc, address(feed18));
        uint256 price = oracleReader.getPrice(usdc);
        assertEq(price, 2500e18);
    }

    function test_GetPriceRevertsWhenPriceIsZero() public {
        MockAggregatorV3 zeroFeed = new MockAggregatorV3(8, 0, 1, block.timestamp, 1);
        vm.prank(owner);
        oracleReader.setPriceFeed(eth, address(zeroFeed));
        vm.expectRevert(OracleReader.InvalidPrice.selector);
        oracleReader.getPrice(eth);
    }

    function test_GetPriceRevertsWhenPriceIsNegative() public {
        MockAggregatorV3 negativeFeed = new MockAggregatorV3(8, -1, 1, block.timestamp, 1);
        vm.prank(owner);
        oracleReader.setPriceFeed(eth, address(negativeFeed));
        vm.expectRevert(OracleReader.InvalidPrice.selector);
        oracleReader.getPrice(eth);
    }

    function test_GetPriceAcceptsFreshPrice() public {
        vm.warp(1_000_000);
        uint256 updateAt = block.timestamp - 30 minutes;
        MockAggregatorV3 freshFeed = new MockAggregatorV3(8, 2500e8, 1, updateAt, 1);
        vm.prank(owner);
        oracleReader.setPriceFeed(eth, address(freshFeed));
        uint256 price = oracleReader.getPrice(eth);
        assertEq(price, 2500e18);
    }

    function test_GetPriceRevertsWhenPriceIsStale() public {
        vm.warp(1_000_000);
        uint256 updateAt = block.timestamp - 2 hours;
        MockAggregatorV3 staleFeed = new MockAggregatorV3(8, 2500e8, 1, updateAt, 1);
        vm.prank(owner);
        oracleReader.setPriceFeed(eth, address(staleFeed));
        vm.expectRevert(OracleReader.StalePrice.selector);
        oracleReader.getPrice(eth);
    }

    function test_GetPriceRevertsWhenTimestampIsInTheFuture() public {
        vm.warp(1_000_000);
        uint256 updateAt = block.timestamp + 1 hours;
        MockAggregatorV3 futureFeed = new MockAggregatorV3(8, 2500e8, 1, updateAt, 1);
        vm.prank(owner);
        oracleReader.setPriceFeed(eth, address(futureFeed));
        vm.expectRevert(OracleReader.InvalidTimestamp.selector);
        oracleReader.getPrice(eth);
    }

    function test_GetPriceRevertsWhenTimestampIsZero() public {
        uint256 updateAt = 0;
        MockAggregatorV3 zeroTimestampFeed = new MockAggregatorV3(8, 2500e8, 1, updateAt, 1);
        vm.prank(owner);
        oracleReader.setPriceFeed(eth, address(zeroTimestampFeed));
        vm.expectRevert(OracleReader.InvalidTimestamp.selector);
        oracleReader.getPrice(eth);
    }

    function test_GetPriceRevertsWhenRoundIsInvalid() public {
        //answerInRound < roundId
        MockAggregatorV3 invalidRoundFeed = new MockAggregatorV3(8, 2500e8, 2, block.timestamp, 1);
        vm.prank(owner);
        oracleReader.setPriceFeed(eth, address(invalidRoundFeed));
        vm.expectRevert(OracleReader.InvalidRound.selector);
        oracleReader.getPrice(eth);
    }

    function test_OwnerCanUpdateMaxPriceAge() public {
        vm.prank(owner);
        oracleReader.setMaxPriceAge(2 hours);
        assertEq(oracleReader.maxPriceAge(), 2 hours);
    }

    function test_NonOwnerCannotUpdateMaxPriceAge() public {
        vm.prank(alice);
        vm.expectRevert();
        oracleReader.setMaxPriceAge(2 hours);
    }

    function test_SetMaxPriceAgeRevertsWhenMaxAgeIsZero() public {
        vm.prank(owner);
        vm.expectRevert(OracleReader.InvalidMaxPriceAge.selector);
        oracleReader.setMaxPriceAge(0);
    }

    function test_SetPriceFeedRevertsWhenAddressHasNoCode() public {
        address nonContract = makeAddr("nonContract");
        vm.prank(owner);
        vm.expectRevert(OracleReader.InvalidPriceFeed.selector);
        oracleReader.setPriceFeed(eth, nonContract);
    }

    function test_SetPriceFeedRevertsWhenDecimalsExceedLimit() public {
        MockAggregatorV3 unsupportedFeed = new MockAggregatorV3(37, 2500e8, 1, block.timestamp, 1);
        vm.prank(owner);
        vm.expectRevert(OracleReader.InvalidFeedDecimals.selector);
        oracleReader.setPriceFeed(eth, address(unsupportedFeed));
    }

    function test_GetPriceRevertsWhenNormalizationOverflows() public {
        MockAggregatorV3 extremeFeed = new MockAggregatorV3(0, type(int256).max, 1, block.timestamp, 1);

        vm.prank(owner);
        oracleReader.setPriceFeed(eth, address(extremeFeed));
        vm.expectRevert(OracleReader.PriceNormalizationOverflow.selector);
        oracleReader.getPrice(eth);
    }

    function test_ConstructorRevertsWhenMaxPriceAgeIsZero() public {
        vm.expectRevert(OracleReader.InvalidMaxPriceAge.selector);
        oracleReader = new OracleReader(owner, 0);
    }

    function test_OwnerCanUpdateMaxPriceAgeEmitsEvent() public {
        vm.prank(owner);
        uint256 maxPriceAge_ = 2 hours;
        vm.expectEmit(false, false, false, true);
        emit OracleReader.MaxPriceAgeUpdated(MAX_PRICE_AGE, maxPriceAge_);
        oracleReader.setMaxPriceAge(maxPriceAge_);
    }
}
