// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract OracleReader {
    AggregatorV3Interface public immutable priceFeed;

    constructor(address priceFeed_) {
        priceFeed = AggregatorV3Interface(priceFeed_);
    }

    function latestPrice() external view returns (int256) {
        (, int256 answer,,,) = priceFeed.latestRoundData();
        return answer;
    }
}
