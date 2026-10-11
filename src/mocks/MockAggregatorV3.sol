// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

contract MockAggregatorV3 {
    uint8 private immutable _decimals;

    int256 private _answer;
    uint80 private _roundId;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;

    constructor(uint8 decimals_, int256 answer_, uint80 roundId_, uint256 updatedAt_, uint80 answeredInRound_) {
        _decimals = decimals_;
        _answer = answer_;
        _roundId = roundId_;
        _updatedAt = updatedAt_;
        _answeredInRound = answeredInRound_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, 0, _updatedAt, _answeredInRound);
    }

    function setAnswer(int256 answer_) external {
        _answer = answer_;
    }

    function setRoundData(uint80 roundId_, uint256 updatedAt_, uint80 answeredInRound_) external {
        _roundId = roundId_;
        _updatedAt = updatedAt_;
        _answeredInRound = answeredInRound_;
    }
}
