// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ILendingPool} from "../interfaces/ILendingPool.sol";

contract MockLendingPool is ILendingPool {
    mapping(address user => mapping(address asset => ILendingPool.UserPosition)) internal positions;

    error InsufficientSupply();
    error InvalidAmount();

    function setPosition(address user, address asset, uint256 supplied, uint256 borrowed) external {
        positions[user][asset] = ILendingPool.UserPosition({supplied: supplied, borrowed: borrowed});
    }

    function deposit(address asset, uint256 amount) external override {
        positions[msg.sender][asset].supplied += amount;
    }

    function withdraw(address asset, uint256 amount) external override {
        if (amount == 0) {
            revert InvalidAmount();
        }
        ILendingPool.UserPosition storage position = positions[msg.sender][asset];
        if (amount > position.supplied) {
            revert InsufficientSupply();
        }
        // Reduce the user's supplied balance.
        position.supplied -= amount;
    }

    function borrow(address, uint256) external override {}

    function repay(address, uint256) external override {}

    function getUserPosition(address user, address asset)
        external
        view
        override
        returns (ILendingPool.UserPosition memory)
    {
        return positions[user][asset];
    }
}
