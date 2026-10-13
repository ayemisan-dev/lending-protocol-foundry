// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LendingPool} from "../../../src/core/LendingPool.sol";
import {ITokenReceiver} from "./MaliciousERC20.sol";

/// @notice Attempts to re-enter LendingPool.liquidate from within the
///         collateral transfer callback.
contract AttackerLiquidator is ITokenReceiver {
    LendingPool public immutable pool;

    address public borrower;
    address public debtAsset;
    address public collateralAsset;
    uint256 public debtToCover;

    bool public reentryAttempted;
    bool public reentrySucceeded;
    bytes4 public reentryRevertSelector;

    constructor(LendingPool pool_) {
        pool = pool_;
    }

    function configure(address borrower_, address debtAsset_, address collateralAsset_, uint256 debtToCover_) external {
        borrower = borrower_;
        debtAsset = debtAsset_;
        collateralAsset = collateralAsset_;
        debtToCover = debtToCover_;
    }

    function attack() external {
        // Pre-approve so the pool can pull the debt token.
        IERC20(debtAsset).approve(address(pool), debtToCover);
        // First (and only intended) liquidation.
        pool.liquidate(borrower, debtAsset, collateralAsset, debtToCover);
    }

    /// @dev Called by MaliciousERC20 when the pool transfers collateral to
    ///      this contract, *after* the pool has already updated state.
    function onTokenTransfer(address, uint256) external override {
        if (reentryAttempted) {
            return; // limit reentrancy to one level for deterministic assertions
        }
        reentryAttempted = true;

        try pool.liquidate(borrower, debtAsset, collateralAsset, debtToCover) {
            reentrySucceeded = true;
        } catch (bytes memory reason) {
            if (reason.length >= 4) {
                bytes4 selector;
                assembly {
                    selector := mload(add(reason, 32))
                }
                reentryRevertSelector = selector;
            }
        }
    }
}
