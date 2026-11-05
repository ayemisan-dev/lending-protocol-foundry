// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract OracleReader is Ownable {
    mapping(address asset => AggregatorV3Interface priceFeed) public priceFeeds;

    uint256 public maxPriceAge;

    error InvalidAsset();
    error InvalidPriceFeed();
    error PriceFeedNotConfigured();
    error InvalidPrice();
    error InvalidTimestamp();
    error StalePrice();
    error InvalidRound();
    error InvalidMaxPriceAge();
    error InvalidFeedDecimals();
    error PriceNormalizationOverflow();

    event PriceFeedUpdated(address indexed asset, address indexed priceFeed);

    event MaxPriceAgeUpdated(uint256 oldValue, uint256 newValue);

    constructor(address initialOwner, uint256 maxPriceAge_) Ownable(initialOwner) {
        if (maxPriceAge_ == 0) {
            revert InvalidMaxPriceAge();
        }

        maxPriceAge = maxPriceAge_;
    }

    function setPriceFeed(address asset, address priceFeed_) external onlyOwner {
        if (asset == address(0)) revert InvalidAsset();
        if (priceFeed_ == address(0)) revert InvalidPriceFeed();
        if (priceFeed_.code.length == 0) revert InvalidPriceFeed();

        try AggregatorV3Interface(priceFeed_).decimals() returns (uint8 decimals_) {
            if (decimals_ > 18) {
                revert InvalidFeedDecimals();
            }
        } catch {
            revert InvalidPriceFeed();
        }
        emit PriceFeedUpdated(asset, priceFeed_);
        priceFeeds[asset] = AggregatorV3Interface(priceFeed_);
    }

    function setMaxPriceAge(uint256 maxPriceAge_) external onlyOwner {
        if (maxPriceAge_ == 0) {
            revert InvalidMaxPriceAge();
        }
        uint256 oldValue = maxPriceAge;
        maxPriceAge = maxPriceAge_;

        emit MaxPriceAgeUpdated(oldValue, maxPriceAge_);
    }

    function getPrice(address asset) external view returns (uint256) {
        AggregatorV3Interface priceFeed = priceFeeds[asset];
        if (address(priceFeed) == address(0)) revert PriceFeedNotConfigured();

        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();

        if (answer <= 0) revert InvalidPrice();
        if (roundId == 0 || answeredInRound < roundId) revert InvalidRound();
        if (updatedAt == 0 || updatedAt > block.timestamp) {
            revert InvalidTimestamp();
        }
        if (block.timestamp - updatedAt > maxPriceAge) revert StalePrice();

        uint8 feedDecimals = priceFeed.decimals();
        return _normalizePrice(uint256(answer), feedDecimals);
    }

    function _normalizePrice(uint256 price, uint8 feedDecimals) internal pure returns (uint256) {
        if (feedDecimals > 18) revert InvalidFeedDecimals();
        if (feedDecimals == 18) return price;

        uint256 scale = 10 ** uint256(18 - feedDecimals);

        if (price > type(uint256).max / scale) {
            revert PriceNormalizationOverflow();
        }

        return price * scale;
    }
}
