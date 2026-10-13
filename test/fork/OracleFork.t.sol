// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {OracleReader} from "../../src/oracles/OracleReader.sol";

/// @notice Minimal fork test: verify OracleReader can read a real Ethereum
///         Sepolia Chainlink ETH/USD feed end-to-end.
contract OracleForkTest is Test {
    /// @dev Ethereum Sepolia Chainlink ETH/USD aggregator.
    address internal constant ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    /// @dev Ethereum Sepolia WETH. We use it as the asset key so that the
    ///      address registered in OracleReader matches what we query.
    address internal constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

    OracleReader internal oracleReader;
    address internal owner = makeAddr("owner");

    function setUp() public {
        string memory rpcUrl = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(rpcUrl);

        // maxPriceAge is generous because testnet Chainlink feeds update
        // less frequently than mainnet. 7 days is safe against normal
        // testnet cadence without masking truly stale data.
        oracleReader = new OracleReader(owner, 7 days);
        vm.prank(owner);
        oracleReader.setPriceFeed(WETH, ETH_USD_FEED);
    }

    function test_Fork_ReadsRealChainlinkEthPrice() public view {
        uint256 price = oracleReader.getPrice(WETH);

        // Sanity bounds on the 18-decimal normalized price. Asserting a
        // range instead of an exact value because the real market price
        // moves between fork blocks.
        assertGt(price, 10e18, "price unexpectedly low");
        assertLt(price, 1_000_000e18, "price unexpectedly high");

        // The feed reports 8 decimals; OracleReader must normalize to 18.
        // A correctly normalized ETH price must be >= 1e18.
        assertGe(price, 1e18, "normalization may have been skipped");
    }

    function test_Fork_StalePriceRevertsAfterTimeAdvance() public {
        //price is fresh at the current fork block.
        uint256 price = oracleReader.getPrice(WETH);
        assertGt(price, 0, "fresh price should be readable");

        // Advance the EVM clock past maxPriceAge (7 days).
        vm.warp(block.timestamp + 8 days);
        vm.expectRevert(OracleReader.StalePrice.selector);
        oracleReader.getPrice(WETH);
    }
}
