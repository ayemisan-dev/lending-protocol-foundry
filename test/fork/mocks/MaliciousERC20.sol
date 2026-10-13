// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ITokenReceiver {
    function onTokenTransfer(address from, uint256 amount) external;
}

/// @notice ERC20 that calls back into a designated receiver on transfer.
///         Used to prove that LendingPool.liquidate follows CEI ordering:
///         the callback fires *after* the recipient's balance is updated,
///         but the LendingPool's state was already finalized before the
///         external call.
contract MaliciousERC20 is ERC20 {
    address public callbackTarget;
    bool public callbackEnabled;

    constructor() ERC20("Malicious", "MAL") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setCallback(address target, bool enabled) external {
        callbackTarget = target;
        callbackEnabled = enabled;
    }

    /// @dev OZ v5 routes every transfer through _update.
    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        if (callbackEnabled && to == callbackTarget) {
            ITokenReceiver(to).onTokenTransfer(from, value);
        }
    }
}
