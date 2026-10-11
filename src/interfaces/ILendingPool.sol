// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

interface ILendingPool {
    struct UserPosition {
        uint256 supplied;
        uint256 borrowed;
    }

    function deposit(address asset, uint256 amount) external;

    function withdraw(address asset, uint256 amount) external;

    function borrow(address asset, uint256 amount) external;

    function repay(address asset, uint256 amount) external;

    function getUserPosition(address user, address asset) external view returns (UserPosition memory);
}
